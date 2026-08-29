defmodule PhoenixHtmxWsExample.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: PhoenixHtmxWsExample.PubSub},
      PhoenixHtmxWsExample.Chat,
      PhoenixHtmxWsExample.Endpoint
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: PhoenixHtmxWsExample.Supervisor
    )
  end

  @impl true
  def config_change(changed, _new, removed) do
    PhoenixHtmxWsExample.Endpoint.config_change(changed, removed)
    :ok
  end
end
