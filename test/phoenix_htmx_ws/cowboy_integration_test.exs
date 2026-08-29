defmodule PhoenixHtmxWs.CowboyIntegrationTest do
  use ExUnit.Case, async: false

  alias PhoenixHtmxWs.IntegrationClient

  setup_all do
    {:ok, _pubsub} = start_supervised({Phoenix.PubSub, name: PhoenixHtmxWs.IntegrationPubSub})
    port = free_port()

    Application.put_env(:phoenix_htmx_ws, PhoenixHtmxWs.CowboyIntegrationEndpoint,
      url: [host: "127.0.0.1", port: port],
      http: [ip: {127, 0, 0, 1}, port: port],
      adapter: Phoenix.Endpoint.Cowboy2Adapter,
      secret_key_base: String.duplicate("phoenix-htmx-ws-secret-", 4),
      check_origin: false,
      server: true
    )

    {:ok, _endpoint} = start_supervised(PhoenixHtmxWs.CowboyIntegrationEndpoint)
    %{url: "ws://127.0.0.1:#{port}/htmx/cowboy"}
  end

  setup do
    if Process.whereis(PhoenixHtmxWs.IntegrationObserver) do
      Process.unregister(PhoenixHtmxWs.IntegrationObserver)
    end

    Process.register(self(), PhoenixHtmxWs.IntegrationObserver)
    :ok
  end

  test "records Cowboy close codes for stop reasons and exceptions", %{url: url} do
    Process.flag(:trap_exit, true)

    for {event, expected_reason} <- [
          {"close", {:remote, 1000, ""}},
          {"shutdown", {:remote, 1000, ""}},
          {"crash", {:remote, 1011, ""}}
        ] do
      {:ok, client} = IntegrationClient.start_link(url, self())
      assert_receive {:ws_connected, ^client}
      assert_receive {:mounted, _, "cowboy"}
      :ok = IntegrationClient.send_frame(client, Jason.encode!(%{"event" => event}))

      assert_receive {:ws_disconnected, ^client, %{reason: ^expected_reason}}, 1_000
    end
  end

  test "handles ping and pong without handle_control/2", %{url: url} do
    {:ok, client} = IntegrationClient.start_link(url, self())
    assert_receive {:ws_connected, ^client}
    assert_receive {:mounted, _, "cowboy"}
    :ok = WebSockex.send_frame(client, {:ping, "probe"})
    assert_receive {:ws_pong, ^client, {:pong, "probe"}}
  end

  test "sends a reply above the default incoming frame limit", %{url: url} do
    size = 10_100_000
    {:ok, client} = IntegrationClient.start_link(url, self())
    assert_receive {:ws_connected, ^client}
    assert_receive {:mounted, _, "cowboy"}

    :ok =
      IntegrationClient.send_frame(client, Jason.encode!(%{"event" => "large", "size" => size}))

    assert_receive {:ws_frame, ^client, :text, body}, 5_000
    assert byte_size(body) == size
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
