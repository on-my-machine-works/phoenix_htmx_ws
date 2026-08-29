defmodule PhoenixHtmxWsExample.ChatComponents do
  use Phoenix.Component

  attr(:message, :any, required: true)

  def message(assigns) do
    ~H"""
    <p id={"message-#{@message.id}"} class="message">{@message.body}</p>
    """
  end

  attr(:messages, :list, required: true)
  attr(:connect_path, :string, required: true)

  def page(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>PhoenixHtmxWs chat</title>
        <script src="https://cdn.jsdelivr.net/npm/htmx.org@4.0.0/dist/htmx.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/htmx.org@4.0.0/dist/ext/hx-ws.min.js"></script>
        <style>
          body { font: 16px system-ui; max-width: 42rem; margin: 3rem auto; padding: 0 1rem; }
          #messages { min-height: 12rem; border: 1px solid #ddd; padding: 1rem; }
          form { display: flex; gap: .5rem; margin-top: 1rem; }
          input { flex: 1; }
        </style>
      </head>
      <body>
        <h1>Chat</h1>
        <div
          id="chat"
          hx-ws:connect={@connect_path}
          hx-target="#messages"
          hx-swap="beforeend"
        >
          <div id="messages">
            <.message :for={message <- @messages} message={message} />
          </div>

          <form hx-ws:send hx-vals='{"event": "send_message"}'>
            <input name="message" autocomplete="off" aria-label="Message" />
            <button type="submit">Send</button>
          </form>
        </div>
      </body>
    </html>
    """
  end

  attr(:mode, :string, required: true)
  attr(:connect_path, :string, required: true)

  def browser_fixture(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>hx-ws browser fixture</title>
        <script src="https://cdn.jsdelivr.net/npm/htmx.org@4.0.0/dist/htmx.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/htmx.org@4.0.0/dist/ext/hx-ws.min.js"></script>
      </head>
      <body>
        <div :if={@mode == "default"} id="connection" hx-ws:connect={@connect_path}>
          <button hx-ws:send name="event" value="plain">Send plain</button>
          <span id="original">original</span>
        </div>

        <div
          :if={@mode == "attributes"}
          id="connection"
          hx-ws:connect={@connect_path}
          hx-target="#messages"
          hx-swap="beforeend"
        >
          <button hx-ws:send name="event" value="plain">Send plain</button>
          <div id="messages"><span>first</span></div>
        </div>

        <div
          :if={@mode == "override"}
          id="connection"
          hx-ws:connect={@connect_path}
          hx-target="#wrong-target"
          hx-swap="beforeend"
        >
          <button hx-ws:send name="event" value="override">Send override</button>
          <div id="wrong-target">wrong</div>
          <div id="override-target">old</div>
        </div>

        <div :if={@mode == "partial"}>
          <div id="connection" hx-ws:connect={@connect_path}>
            <button hx-ws:send name="event" value="partial">Send partial</button>
            <span id="stable">stable</span>
          </div>
          <div id="secondary">old</div>
        </div>

        <div :if={@mode == "oob"}>
          <div id="connection" hx-ws:connect={@connect_path}>
            <button hx-ws:send name="event" value="oob">Send OOB</button>
            <span id="stable">stable</span>
          </div>
          <span id="oob-target">old</span>
        </div>

        <div :if={@mode == "reconnect"} id="connection" hx-ws:connect={@connect_path}>
          <span id="mount-count">0</span>
          <button hx-ws:send name="event" value="plain">Send after reconnect</button>
          <div id="reconnect-result"></div>
        </div>
      </body>
    </html>
    """
  end
end
