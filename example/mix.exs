defmodule PhoenixHtmxWsExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_htmx_ws_example,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {PhoenixHtmxWsExample.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:phoenix_htmx_ws, path: ".."},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:bandit, "~> 1.7"}
    ]
  end
end
