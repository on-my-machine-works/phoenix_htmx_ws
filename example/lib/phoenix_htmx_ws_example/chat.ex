defmodule PhoenixHtmxWsExample.Chat.Message do
  @enforce_keys [:id, :body]
  defstruct [:id, :body]
end

defmodule PhoenixHtmxWsExample.Chat do
  use Agent

  alias PhoenixHtmxWsExample.Chat.Message

  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def list_messages(room_id) do
    Agent.get(__MODULE__, &Map.get(&1, room_id, []))
  end

  def create_message(room_id, body) when is_binary(body) do
    message = %Message{id: System.unique_integer([:positive]), body: body}

    Agent.update(__MODULE__, fn rooms ->
      Map.update(rooms, room_id, [message], &(&1 ++ [message]))
    end)

    Phoenix.PubSub.broadcast(
      PhoenixHtmxWsExample.PubSub,
      "room:#{room_id}",
      {:message_created, message}
    )

    {:ok, message}
  end

  def increment_mount(room_id) do
    Agent.get_and_update(__MODULE__, fn rooms ->
      key = {:mount_count, room_id}
      count = Map.get(rooms, key, 0) + 1
      {count, Map.put(rooms, key, count)}
    end)
  end
end
