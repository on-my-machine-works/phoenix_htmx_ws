alias PhoenixHtmxWs.SocketTest

defmodule PhoenixHtmxWs.BenchmarkSocket do
  use PhoenixHtmxWs.Socket, require_session: false

  @impl true
  def handle_event("echo", %{"message" => message}, socket), do: {:reply, message, socket}

  @impl true
  def handle_info({:push, body}, socket), do: {:push, body, socket}
end

{:ok, socket} = SocketTest.connect(PhoenixHtmxWs.BenchmarkSocket)
frame = ~s({"event":"echo","message":"<p>hello</p>"})

Benchee.run(
  %{
    "connections" => fn -> SocketTest.connect(PhoenixHtmxWs.BenchmarkSocket) end,
    "incoming events" => fn -> SocketTest.send_frame(socket, frame) end,
    "outgoing pushes" => fn -> SocketTest.send_info(socket, {:push, "<p>hello</p>"}) end,
    "safe rendering" => fn -> Phoenix.HTML.Safe.to_iodata({:safe, ["<p>", "hello", "</p>"]}) end
  },
  time: 5,
  memory_time: 2,
  print: [benchmarking: true, configuration: true, fast_warning: false]
)

before = :erlang.memory(:processes_used)
owner = self()

connections =
  for _ <- 1..5_000 do
    spawn(fn ->
      {:ok, state} = SocketTest.connect(PhoenixHtmxWs.BenchmarkSocket)
      send(owner, {:idle_connection_ready, self()})

      receive do
        :stop -> SocketTest.terminate(state, :normal)
      end
    end)
  end

for pid <- connections do
  receive do
    {:idle_connection_ready, ^pid} -> :ok
  end
end

after_allocation = :erlang.memory(:processes_used)
bytes_per_idle_connection = div(after_allocation - before, length(connections))

IO.puts("Approximate state allocation per idle connection: #{bytes_per_idle_connection} bytes")

Enum.each(connections, &send(&1, :stop))
