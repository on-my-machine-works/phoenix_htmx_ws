defmodule PhoenixHtmxWs.Drainer do
  @moduledoc false
  use GenServer

  def child_spec({handler, opts} = argument) do
    endpoint = Keyword.fetch!(opts, :endpoint)

    %{
      id: {__MODULE__, endpoint, handler},
      start: {__MODULE__, :start_link, [argument]},
      shutdown: 30_000
    }
  end

  def start_link(argument), do: GenServer.start_link(__MODULE__, argument)

  @impl true
  def init({handler, opts}) do
    Process.flag(:trap_exit, true)
    {:ok, {Keyword.fetch!(opts, :endpoint), handler}}
  end

  @impl true
  def terminate(_reason, {endpoint, handler}) do
    PhoenixHtmxWs.ConnectionRegistry
    |> Registry.lookup({endpoint, handler})
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.each(&send(&1, :phoenix_htmx_ws_drain))

    :ok
  end
end
