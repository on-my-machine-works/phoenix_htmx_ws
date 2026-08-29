import Config

config :phoenix_htmx_ws_example, PhoenixHtmxWsExample.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: PhoenixHtmxWsExample.ErrorHTML], layout: false],
  pubsub_server: PhoenixHtmxWsExample.PubSub,
  secret_key_base: String.duplicate("phoenix-htmx-ws-example-secret-", 3),
  server: true,
  http: [ip: {127, 0, 0, 1}, port: 4000]

config :logger, level: :info
