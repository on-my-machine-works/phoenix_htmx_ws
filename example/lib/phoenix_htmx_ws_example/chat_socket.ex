defmodule PhoenixHtmxWsExample.ChatSocket do
  use PhoenixHtmxWs.Socket

  alias PhoenixHtmxWsExample.{Chat, ChatComponents}

  @impl true
  def connect(_params, session, socket) when is_map(session), do: {:ok, socket}
  def connect(_params, _session, _socket), do: :error

  @impl true
  def mount(%{"room_id" => room_id}, socket) do
    Phoenix.PubSub.subscribe(PhoenixHtmxWsExample.PubSub, "room:#{room_id}")

    if room_id == "browser-reconnect" do
      send(self(), {:mount_count, Chat.increment_mount(room_id)})
    end

    {:ok, assign(socket, :room_id, room_id)}
  end

  @impl true
  def handle_event("send_message", %{"message" => body}, socket) do
    case String.trim(body) do
      "" -> :ok
      body -> {:ok, _message} = Chat.create_message(socket.assigns.room_id, body)
    end

    {:noreply, socket}
  end

  def handle_event("plain", _params, socket) do
    {:reply, ~s(<p id="plain-result">plain reply</p>), socket}
  end

  def handle_event("override", _params, socket) do
    {:reply, ~s(<p id="override-result">override reply</p>),
     [target: "#override-target", swap: "innerHTML"], socket}
  end

  def handle_event("partial", _params, socket) do
    html =
      ~s(<hx-partial hx-target="#secondary" hx-swap="innerHTML"><span>partial reply</span></hx-partial>)

    {:reply, html, socket}
  end

  def handle_event("oob", _params, socket) do
    {:reply, ~s(<span id="oob-target" hx-swap-oob="true">oob reply</span>), socket}
  end

  @impl true
  def handle_info({:message_created, message}, socket) do
    {:push, ChatComponents.message(%{message: message}), socket}
  end

  def handle_info({:mount_count, count}, socket) do
    {:push, Integer.to_string(count), [target: "#mount-count", swap: "innerHTML"], socket}
  end
end
