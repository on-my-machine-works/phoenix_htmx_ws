defmodule PhoenixHtmxWs.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/on-my-machine-works/phoenix_htmx_ws"

  def project do
    [
      app: :phoenix_htmx_ws,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Phoenix WebSocket transport for the htmx 4 hx-ws extension",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: [main: "readme", extras: ["README.md", "docs/adapter-behavior.md"]],
      test_paths: ["test"],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {PhoenixHtmxWs.Application, []},
      extra_applications: [:crypto, :logger]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:jason, "~> 1.4"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.1", only: [:dev, :test], optional: true},
      {:bandit, "~> 1.7", only: :test},
      {:plug_cowboy, "~> 2.7", only: :test},
      {:websockex, "~> 0.4", only: :test},
      {:benchee, "~> 1.3", only: :dev},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/phoenix_htmx_ws"
      },
      files:
        ~w(lib docs bench example/config example/lib example/test example/mix.exs example/mix.lock example/README.md example/package.json example/package-lock.json example/playwright.config.ts mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
