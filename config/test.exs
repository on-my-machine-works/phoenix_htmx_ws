import Config

config :phoenix_htmx_ws, PhoenixHtmxWs.IntegrationEndpoint,
  url: [host: "127.0.0.1"],
  secret_key_base: String.duplicate("phoenix-htmx-ws-secret-", 4),
  check_origin: false,
  server: false

config :phoenix_htmx_ws, PhoenixHtmxWs.CowboyIntegrationEndpoint,
  url: [host: "127.0.0.1"],
  secret_key_base: String.duplicate("phoenix-htmx-ws-secret-", 4),
  check_origin: false,
  server: false
