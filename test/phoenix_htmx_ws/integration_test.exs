defmodule PhoenixHtmxWs.IntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias PhoenixHtmxWs.IntegrationClient

  setup_all do
    {:ok, _pubsub} = start_supervised({Phoenix.PubSub, name: PhoenixHtmxWs.IntegrationPubSub})
    port = free_port()

    Application.put_env(:phoenix_htmx_ws, PhoenixHtmxWs.IntegrationEndpoint,
      url: [host: "127.0.0.1", port: port],
      http: [ip: {127, 0, 0, 1}, port: port],
      adapter: Bandit.PhoenixAdapter,
      secret_key_base: String.duplicate("phoenix-htmx-ws-secret-", 4),
      check_origin: false,
      server: true
    )

    {:ok, _endpoint} = start_supervised(PhoenixHtmxWs.IntegrationEndpoint)

    %{url: "ws://127.0.0.1:#{port}/htmx"}
  end

  setup do
    if Process.whereis(PhoenixHtmxWs.IntegrationObserver) do
      Process.unregister(PhoenixHtmxWs.IntegrationObserver)
    end

    Process.register(self(), PhoenixHtmxWs.IntegrationObserver)

    on_exit(fn ->
      if Process.whereis(PhoenixHtmxWs.IntegrationObserver) == self() do
        Process.unregister(PhoenixHtmxWs.IntegrationObserver)
      end
    end)

    :ok
  end

  test "connects, mounts, sends, and returns exact plain and envelope frames", %{url: url} do
    {:ok, client} = IntegrationClient.start_link("#{url}/room-a", self())
    assert_receive {:ws_connected, ^client}
    assert_receive {:mounted, socket_pid, "room-a"}
    assert is_pid(socket_pid)

    :ok =
      IntegrationClient.send_frame(client, ~s({"headers":{},"event":"echo","message":"hello"}))

    assert_receive {:event, ^socket_pid, "echo", %{"message" => "hello"}}
    assert_receive {:ws_frame, ^client, :text, "hello"}

    :ok = IntegrationClient.send_frame(client, ~s({"event":"envelope"}))
    assert_receive {:ws_frame, ^client, :text, envelope}

    assert Jason.decode!(envelope) == %{
             "content" => "<p>enveloped</p>",
             "target" => "#messages",
             "swap" => "beforeend"
           }
  end

  test "two clients receive one PubSub broadcast", %{url: url} do
    {:ok, first} = IntegrationClient.start_link("#{url}/shared", self())
    {:ok, second} = IntegrationClient.start_link("#{url}/shared", self())
    assert_receive {:ws_connected, ^first}
    assert_receive {:ws_connected, ^second}
    assert_receive {:mounted, first_socket, "shared"}
    assert_receive {:mounted, second_socket, "shared"}
    refute first_socket == second_socket

    :ok =
      IntegrationClient.send_frame(
        first,
        ~s({"event":"broadcast","message":"hello & goodbye"})
      )

    expected = "<p class=\"message\">hello &amp; goodbye</p>"
    assert_receive {:ws_frame, ^first, :text, ^expected}
    assert_receive {:ws_frame, ^second, :text, ^expected}
  end

  test "an exception disconnects only its own socket", %{url: url} do
    Process.flag(:trap_exit, true)
    {:ok, crashing} = IntegrationClient.start_link("#{url}/isolation", self())
    {:ok, healthy} = IntegrationClient.start_link("#{url}/isolation", self())
    assert_receive {:ws_connected, ^crashing}
    assert_receive {:ws_connected, ^healthy}
    assert_receive {:mounted, _, "isolation"}
    assert_receive {:mounted, _, "isolation"}

    :ok = IntegrationClient.send_frame(crashing, ~s({"event":"crash"}))
    assert_receive {:ws_disconnected, ^crashing, _disconnect}

    :ok = IntegrationClient.send_frame(healthy, ~s({"event":"echo","message":"still alive"}))
    assert_receive {:ws_frame, ^healthy, :text, "still alive"}
  end

  test "a malformed frame on one socket does not affect another", %{url: url} do
    {:ok, malformed} = IntegrationClient.start_link("#{url}/malformed", self())
    {:ok, healthy} = IntegrationClient.start_link("#{url}/malformed", self())
    assert_receive {:ws_connected, ^malformed}
    assert_receive {:ws_connected, ^healthy}
    assert_receive {:mounted, _, "malformed"}
    assert_receive {:mounted, _, "malformed"}

    :ok = IntegrationClient.send_frame(malformed, "not json")
    :ok = IntegrationClient.send_frame(healthy, ~s({"event":"echo","message":"healthy"}))
    assert_receive {:ws_frame, ^healthy, :text, "healthy"}
    assert Process.alive?(malformed)
  end

  test "a server close permits a fresh mounted socket and new events", %{url: url} do
    Process.flag(:trap_exit, true)
    {:ok, first} = IntegrationClient.start_link("#{url}/reconnect", self())
    assert_receive {:ws_connected, ^first}
    assert_receive {:mounted, first_socket, "reconnect"}
    :ok = IntegrationClient.send_frame(first, ~s({"event":"shutdown"}))
    assert_receive {:ws_disconnected, ^first, _}

    {:ok, second} = IntegrationClient.start_link("#{url}/reconnect", self())
    assert_receive {:ws_connected, ^second}
    assert_receive {:mounted, second_socket, "reconnect"}
    refute first_socket == second_socket
    :ok = IntegrationClient.send_frame(second, ~s({"event":"echo","message":"after"}))
    assert_receive {:ws_frame, ^second, :text, "after"}
  end

  test "a PubSub subscription ends with its socket process", %{url: url} do
    {:ok, client} = IntegrationClient.start_link("#{url}/subscription", self())
    assert_receive {:ws_connected, ^client}
    assert_receive {:mounted, socket_pid, "subscription"}
    assert Process.alive?(socket_pid)
    monitor = Process.monitor(socket_pid)

    :ok = IntegrationClient.send_frame(client, ~s({"event":"close"}))
    assert_receive {:ws_disconnected, ^client, _}
    assert_receive {:DOWN, ^monitor, :process, ^socket_pid, _reason}, 1_000
    refute Process.alive?(socket_pid)
  end

  test "rejects a session socket without a CSRF token and logs the cause", %{url: url} do
    auth_url = String.replace(url, "/htmx", "/auth")

    log =
      capture_log(fn ->
        assert {:error, %WebSockex.RequestError{code: 403}} =
                 IntegrationClient.start_link(auth_url, self())
      end)

    assert log =~ "the endpoint configures a session for this socket"
    assert log =~ ~s(did not send a valid "_csrf_token")
    assert log =~ "PhoenixHtmxWs.connect_path/1"
  end

  test "merges path parameters and query parameters into socket.params", %{url: url} do
    {:ok, client} = IntegrationClient.start_link("#{url}/room-b?tenant=acme&page=2", self())
    assert_receive {:ws_connected, ^client}
    assert_receive {:mounted, _socket_pid, "room-b"}

    :ok = IntegrationClient.send_frame(client, ~s({"event":"params"}))
    assert_receive {:ws_frame, ^client, :text, body}

    # Connect parameters arrive as strings, unlike the JSON-typed frame params.
    assert Jason.decode!(body) == %{
             "room_id" => "room-b",
             "tenant" => "acme",
             "page" => "2"
           }
  end

  test "records Bandit close codes for stop reasons and exceptions", %{url: url} do
    Process.flag(:trap_exit, true)

    for {event, expected_reason} <- [
          {"close", {:remote, 1000, ""}},
          {"shutdown", {:remote, 1011, ""}},
          {"crash", {:remote, 1011, ""}}
        ] do
      {:ok, client} = IntegrationClient.start_link("#{url}/close-codes", self())
      assert_receive {:ws_connected, ^client}
      assert_receive {:mounted, _, "close-codes"}
      :ok = IntegrationClient.send_frame(client, Jason.encode!(%{"event" => event}))

      assert_receive {:ws_disconnected, ^client, %{reason: ^expected_reason}}, 1_000
    end
  end

  test "handles ping and pong control frames without a socket callback", %{url: url} do
    {:ok, client} = IntegrationClient.start_link("#{url}/control", self())
    assert_receive {:ws_connected, ^client}
    assert_receive {:mounted, _, "control"}

    :ok = WebSockex.send_frame(client, {:ping, "probe"})
    assert_receive {:ws_pong, ^client, {:pong, "probe"}}
  end

  test "sends a reply above the default incoming frame limit", %{url: url} do
    size = 10_100_000
    {:ok, client} = IntegrationClient.start_link("#{url}/large-reply", self())
    assert_receive {:ws_connected, ^client}
    assert_receive {:mounted, _, "large-reply"}

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
