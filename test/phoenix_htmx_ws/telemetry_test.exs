defmodule PhoenixHtmxWs.TelemetryTest do
  use ExUnit.Case, async: false

  alias PhoenixHtmxWs.SocketTest

  setup do
    owner = self()
    id = "telemetry-test-#{System.unique_integer([:positive])}"

    events = [
      [:phoenix_htmx_ws, :socket, :connect],
      [:phoenix_htmx_ws, :socket, :disconnect],
      [:phoenix_htmx_ws, :event, :start],
      [:phoenix_htmx_ws, :event, :stop],
      [:phoenix_htmx_ws, :event, :exception],
      [:phoenix_htmx_ws, :push]
    ]

    :ok =
      :telemetry.attach_many(
        id,
        events,
        fn event, measurements, metadata, _config ->
          send(owner, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  test "emits connect, event, push, disconnect, and exception metadata" do
    {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.TestSocket)

    assert_receive {:telemetry, [:phoenix_htmx_ws, :socket, :connect], %{system_time: _},
                    connect_meta}

    assert connect_meta.socket == PhoenixHtmxWs.TestSocket
    assert is_binary(connect_meta.socket_id)

    {:ok, [{:text, "hello"}], socket} =
      SocketTest.send_event(socket, "echo", %{"message" => "hello"})

    assert_receive {:telemetry, [:phoenix_htmx_ws, :event, :start], %{system_time: _}, start_meta}
    assert start_meta.event == "echo"
    assert start_meta.payload_size > 0
    refute Map.has_key?(start_meta, :params)

    # :telemetry.span/3 does not carry start metadata onto the stop event, so the
    # documented metadata has to be asserted on stop as well as on start.
    assert_receive {:telemetry, [:phoenix_htmx_ws, :event, :stop], %{duration: _}, stop_meta}
    assert stop_meta.response_size == 5
    assert stop_meta.socket == PhoenixHtmxWs.TestSocket
    assert stop_meta.socket_id == connect_meta.socket_id
    assert stop_meta.event == "echo"
    assert stop_meta.payload_size == start_meta.payload_size

    assert_receive {:telemetry, [:phoenix_htmx_ws, :push], %{response_size: 5}, push_meta}
    assert push_meta.event == "echo"
    assert push_meta.socket == PhoenixHtmxWs.TestSocket
    assert push_meta.socket_id == connect_meta.socket_id

    assert :ok = SocketTest.terminate(socket, :normal)
    assert_receive {:telemetry, [:phoenix_htmx_ws, :socket, :disconnect], %{duration: _}, _meta}

    {:ok, crash_socket} = SocketTest.connect(PhoenixHtmxWs.TestSocket)

    assert_raise RuntimeError, "socket exploded", fn ->
      SocketTest.send_event(crash_socket, "crash")
    end

    assert_receive {:telemetry, [:phoenix_htmx_ws, :event, :exception], %{duration: _}, metadata}
    assert metadata.event == "crash"
    assert metadata.socket == PhoenixHtmxWs.TestSocket
    assert is_binary(metadata.socket_id)
    assert metadata.kind == :error
    assert %RuntimeError{} = metadata.reason
    assert is_list(metadata.stacktrace)
  end

  test "includes params only after telemetry_params is enabled" do
    {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.TelemetryParamsSocket)

    {:ok, [{:text, "visible"}], _socket} =
      SocketTest.send_event(socket, "echo", %{"message" => "visible"})

    assert_receive {:telemetry, [:phoenix_htmx_ws, :event, :start], _measurements, metadata}
    assert metadata.params == %{"message" => "visible"}
  end

  test "emits exception telemetry for error and info callbacks" do
    {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.ExceptionCallbacksSocket)

    assert_raise RuntimeError, "error callback exploded", fn ->
      SocketTest.send_frame(socket, "not json")
    end

    assert_receive {:telemetry, [:phoenix_htmx_ws, :event, :exception], %{duration: _}, metadata}
    assert metadata.event == "invalid_json"
    assert metadata.payload_size == byte_size("not json")
    assert %RuntimeError{message: "error callback exploded"} = metadata.reason

    assert_raise RuntimeError, "info callback exploded", fn ->
      SocketTest.send_info(socket, :crash)
    end

    assert_receive {:telemetry, [:phoenix_htmx_ws, :event, :exception], %{duration: _}, metadata}
    assert metadata.event == "handle_info"
    assert %RuntimeError{message: "info callback exploded"} = metadata.reason
  end
end
