defmodule PhoenixHtmxWs.AdapterBehaviorExperimentTest do
  use ExUnit.Case, async: false

  @moduletag :experiment
  @moduletag timeout: 120_000

  alias PhoenixHtmxWs.IntegrationClient

  test "idle timeouts, large replies, control frames, and shutdown drain on both adapters" do
    Process.flag(:trap_exit, true)
    {:ok, _pubsub} = start_supervised({Phoenix.PubSub, name: PhoenixHtmxWs.IntegrationPubSub})
    bandit_port = free_port()
    cowboy_port = free_port()

    configure_endpoint(
      PhoenixHtmxWs.IntegrationEndpoint,
      Bandit.PhoenixAdapter,
      bandit_port
    )

    configure_endpoint(
      PhoenixHtmxWs.CowboyIntegrationEndpoint,
      Phoenix.Endpoint.Cowboy2Adapter,
      cowboy_port
    )

    {:ok, _bandit} = start_supervised(PhoenixHtmxWs.IntegrationEndpoint)
    {:ok, _cowboy} = start_supervised(PhoenixHtmxWs.CowboyIntegrationEndpoint)

    bandit_url = "ws://127.0.0.1:#{bandit_port}/htmx/experiment"
    cowboy_url = "ws://127.0.0.1:#{cowboy_port}/htmx/experiment"

    {:ok, bandit_client} = IntegrationClient.start_link(bandit_url, self())
    {:ok, cowboy_client} = IntegrationClient.start_link(cowboy_url, self())
    assert_receive {:ws_connected, ^bandit_client}
    assert_receive {:ws_connected, ^cowboy_client}

    # This reply exceeds both adapter defaults for incoming frame size.
    reply_size = 10_100_000
    send_event(bandit_client, %{"event" => "large", "size" => reply_size})
    send_event(cowboy_client, %{"event" => "large", "size" => reply_size})
    assert_receive {:ws_frame, ^bandit_client, :text, body}, 5_000
    assert byte_size(body) == reply_size
    assert_receive {:ws_frame, ^cowboy_client, :text, body}, 5_000
    assert byte_size(body) == reply_size

    :ok = WebSockex.send_frame(bandit_client, {:ping, "probe"})
    :ok = WebSockex.send_frame(cowboy_client, {:ping, "probe"})
    assert_receive {:ws_pong, ^bandit_client, {:pong, "probe"}}
    assert_receive {:ws_pong, ^cowboy_client, {:pong, "probe"}}

    # Send no data for 90 seconds. Neither adapter sends a ping that keeps the
    # connection alive. Both endpoints use Phoenix's 60-second timeout.
    assert_receive {:ws_disconnected, ^bandit_client, %{reason: bandit_idle_reason}}, 90_000
    assert bandit_idle_reason == {:remote, 1002, ""}
    assert_receive {:ws_disconnected, ^cowboy_client, %{reason: cowboy_idle_reason}}, 35_000
    assert cowboy_idle_reason == {:remote, 1000, ""}

    {:ok, bandit_shutdown_client} = IntegrationClient.start_link(bandit_url, self())
    {:ok, cowboy_shutdown_client} = IntegrationClient.start_link(cowboy_url, self())
    assert_receive {:ws_connected, ^bandit_shutdown_client}
    assert_receive {:ws_connected, ^cowboy_shutdown_client}

    :ok = stop_supervised(PhoenixHtmxWs.IntegrationEndpoint)
    :ok = stop_supervised(PhoenixHtmxWs.CowboyIntegrationEndpoint)

    assert_receive {:ws_disconnected, ^bandit_shutdown_client, %{reason: bandit_shutdown}}, 5_000
    assert_receive {:ws_disconnected, ^cowboy_shutdown_client, %{reason: cowboy_shutdown}}, 5_000
    assert bandit_shutdown == {:remote, 1012, ""}
    assert cowboy_shutdown == {:remote, 1012, ""}
  end

  defp send_event(client, payload) do
    :ok = IntegrationClient.send_frame(client, Jason.encode!(payload))
  end

  defp configure_endpoint(endpoint, adapter, port) do
    Application.put_env(:phoenix_htmx_ws, endpoint,
      url: [host: "127.0.0.1", port: port],
      http: [ip: {127, 0, 0, 1}, port: port],
      adapter: adapter,
      secret_key_base: String.duplicate("phoenix-htmx-ws-secret-", 4),
      check_origin: false,
      server: true
    )
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
