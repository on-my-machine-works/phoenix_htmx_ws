defmodule PhoenixHtmxWs.IntegrationSocket do
  use PhoenixHtmxWs.Socket, require_session: false

  @impl true
  def mount(%{"room_id" => room_id}, socket) do
    Phoenix.PubSub.subscribe(PhoenixHtmxWs.IntegrationPubSub, "room:#{room_id}")
    notify({:mounted, self(), room_id})
    {:ok, assign(socket, :room_id, room_id)}
  end

  @impl true
  def handle_event("echo", params, socket) do
    notify({:event, self(), "echo", params})
    {:reply, params["message"], socket}
  end

  def handle_event("params", _params, socket) do
    {:reply, Jason.encode!(socket.params), socket}
  end

  def handle_event("envelope", _params, socket) do
    {:reply, "<p>enveloped</p>", [target: "#messages", swap: "beforeend"], socket}
  end

  def handle_event("broadcast", %{"message" => message}, socket) do
    Phoenix.PubSub.broadcast(
      PhoenixHtmxWs.IntegrationPubSub,
      "room:#{socket.assigns.room_id}",
      {:broadcast, message}
    )

    {:noreply, socket}
  end

  def handle_event("crash", _params, _socket), do: raise("integration crash")
  def handle_event("close", _params, socket), do: {:stop, :normal, socket}
  def handle_event("shutdown", _params, socket), do: {:stop, :shutdown, socket}

  def handle_event("large", %{"size" => size}, socket) when is_integer(size) do
    {:reply, :binary.copy("x", size), socket}
  end

  @impl true
  def handle_info({:broadcast, message}, socket) do
    escaped = message |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    {:push, "<p class=\"message\">#{escaped}</p>", socket}
  end

  defp notify(message) do
    case Process.whereis(PhoenixHtmxWs.IntegrationObserver) do
      nil -> :ok
      pid -> send(pid, message)
    end
  end
end

defmodule PhoenixHtmxWs.IntegrationAuthSocket do
  use PhoenixHtmxWs.Socket

  @impl true
  def handle_event("echo", %{"message" => message}, socket), do: {:reply, message, socket}
end

defmodule PhoenixHtmxWs.IntegrationRouter do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/health" do
    Plug.Conn.send_resp(conn, 200, "ok")
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end

defmodule PhoenixHtmxWs.IntegrationEndpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_htmx_ws

  @session_options [
    store: :cookie,
    key: "_phoenix_htmx_ws_test",
    signing_salt: "session-signing-salt",
    same_site: "Lax"
  ]

  socket "/htmx/:room_id", PhoenixHtmxWs.IntegrationSocket,
    websocket: [
      path: "/",
      timeout: 60_000,
      connect_info: [:uri, session: @session_options]
    ],
    longpoll: false

  socket "/auth", PhoenixHtmxWs.IntegrationAuthSocket,
    websocket: [
      path: "/",
      timeout: 60_000,
      connect_info: [session: @session_options]
    ],
    longpoll: false

  plug(Plug.Session, @session_options)
  plug(PhoenixHtmxWs.IntegrationRouter)
end

defmodule PhoenixHtmxWs.IntegrationClient do
  use WebSockex

  def start_link(url, owner), do: WebSockex.start_link(url, __MODULE__, owner)
  def send_frame(pid, frame), do: WebSockex.send_frame(pid, {:text, frame})

  @impl true
  def handle_connect(_conn, owner) do
    send(owner, {:ws_connected, self()})
    {:ok, owner}
  end

  @impl true
  def handle_frame({opcode, body}, owner) do
    send(owner, {:ws_frame, self(), opcode, body})
    {:ok, owner}
  end

  @impl true
  def handle_disconnect(disconnect, owner) do
    send(owner, {:ws_disconnected, self(), disconnect})
    {:ok, owner}
  end

  @impl true
  def handle_ping(frame, owner) do
    send(owner, {:ws_ping, self(), frame})
    {:reply, pong_for(frame), owner}
  end

  @impl true
  def handle_pong(frame, owner) do
    send(owner, {:ws_pong, self(), frame})
    {:ok, owner}
  end

  defp pong_for(:ping), do: :pong
  defp pong_for({:ping, payload}), do: {:pong, payload}
end

defmodule PhoenixHtmxWs.CowboyIntegrationEndpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_htmx_ws

  socket "/htmx/:room_id", PhoenixHtmxWs.IntegrationSocket,
    websocket: [path: "/", timeout: 60_000],
    longpoll: false

  plug(PhoenixHtmxWs.IntegrationRouter)
end
