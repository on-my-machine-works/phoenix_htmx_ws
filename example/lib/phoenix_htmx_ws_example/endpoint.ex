defmodule PhoenixHtmxWsExample.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_htmx_ws_example

  @session_options [
    store: :cookie,
    key: "_phoenix_htmx_ws_example",
    signing_salt: "phoenix-htmx-ws",
    same_site: "Lax"
  ]

  socket "/htmx/chat/:room_id", PhoenixHtmxWsExample.ChatSocket,
    websocket: [
      path: "/",
      timeout: 300_000,
      connect_info: [:uri, :peer_data, session: @session_options]
    ],
    longpoll: false

  plug(Plug.Session, @session_options)
  plug(PhoenixHtmxWsExample.Router)
end
