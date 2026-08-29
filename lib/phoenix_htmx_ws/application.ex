defmodule PhoenixHtmxWs.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: PhoenixHtmxWs.ConnectionRegistry}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: PhoenixHtmxWs.Supervisor)
  end
end
