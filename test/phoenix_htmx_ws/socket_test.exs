defmodule PhoenixHtmxWs.SocketTestTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PhoenixHtmxWs.SocketTest

  describe "connection" do
    test "accepts a connection, passes values, and mounts" do
      params = %{"room_id" => "123", "query" => "yes"}
      session = %{"user_token" => "token"}

      assert {:ok, state} =
               SocketTest.connect(PhoenixHtmxWs.TestSocket,
                 params: params,
                 session: session
               )

      socket = SocketTest.socket(state)
      assert socket.params == params
      assert socket.session == session
      assert socket.assigns.connect_params == params
      assert socket.assigns.connect_session == session
      assert socket.assigns.mounted
      assert is_binary(socket.id)
      assert %DateTime{} = socket.connected_at
    end

    test "rejects an unauthorized connection without mounting" do
      refute_receive {:mounted, _}

      assert :error =
               SocketTest.connect(PhoenixHtmxWs.TestSocket,
                 params: %{"authorized" => false, "notify" => self()}
               )

      refute_receive {:mounted, _}
    end

    test "rejects a missing configured session and logs the fix" do
      log =
        capture_log(fn ->
          assert :error =
                   SocketTest.connect(PhoenixHtmxWs.TestSocket,
                     session_configured: true
                   )
        end)

      assert log =~ "session could not be read"
      assert log =~ "PhoenixHtmxWs.connect_path/1"
    end

    test "allows a missing configured session when it is optional" do
      assert {:ok, _state} =
               SocketTest.connect(PhoenixHtmxWs.OptionalSessionSocket,
                 session_configured: true
               )
    end

    test "wraps mount stops and removes their connection registration" do
      assert {:stop, :maintenance, state} =
               SocketTest.connect(PhoenixHtmxWs.MountStopSocket)

      socket = SocketTest.socket(state)
      assert socket.assigns.mounted == false

      refute Enum.any?(
               Registry.lookup(
                 PhoenixHtmxWs.ConnectionRegistry,
                 {PhoenixHtmxWs.SocketTest.Endpoint, PhoenixHtmxWs.MountStopSocket}
               ),
               fn {_pid, id} -> id == socket.id end
             )
    end
  end

  describe "incoming frames and dispatch" do
    setup do
      {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.TestSocket)
      %{socket: socket}
    end

    test "extracts event, params, JSON types, and headers", %{socket: socket} do
      frame =
        Jason.encode!(%{
          "event" => "inspect",
          "message" => "hello",
          "tag" => ["urgent", "public"],
          "count" => 2,
          "active" => true,
          "headers" => %{"HX-Request" => "true"}
        })

      assert {:ok, [{:text, body}], socket} = SocketTest.send_frame(socket, frame)
      decoded = Jason.decode!(body)

      assert decoded["params"] == %{
               "message" => "hello",
               "tag" => ["urgent", "public"],
               "count" => 2,
               "active" => true
             }

      assert decoded["headers"] == %{"HX-Request" => "true"}
      assert SocketTest.socket(socket).meta == %{}
    end

    test "uses the default event when the key is absent", %{socket: socket} do
      assert {:ok, [], _socket} = SocketTest.send_frame(socket, ~s({"message":"hello"}))
    end

    test "supports configurable event and default keys" do
      {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.ActionSocket)

      assert {:ok, [{:text, body}], socket} =
               SocketTest.send_frame(socket, ~s({"action":"save","value":1}))

      assert Jason.decode!(body) == %{"event" => "save", "params" => %{"value" => 1}}

      assert {:ok, [{:text, body}], _socket} = SocketTest.send_frame(socket, ~s({"value":2}))
      assert Jason.decode!(body) == %{"event" => "fallback", "params" => %{"value" => 2}}

      assert {:ok, [{:text, body}], _socket} =
               SocketTest.send_event(socket, "save", %{"value" => 3})

      assert Jason.decode!(body) == %{"event" => "save", "params" => %{"value" => 3}}
    end

    test "uses the default event for a non-string event value", %{socket: socket} do
      assert {:ok, [], _socket} = SocketTest.send_frame(socket, ~s({"event":12}))
      assert {:ok, [], _socket} = SocketTest.send_frame(socket, ~s({"event":null}))
    end

    test "keeps assigns and returned state between events", %{socket: socket} do
      assert {:ok, [{:text, "1"}], socket} = SocketTest.send_event(socket, "increment")
      assert {:ok, [{:text, "2"}], socket} = SocketTest.send_event(socket, "increment")
      assert SocketTest.socket(socket).assigns.count == 2

      assert {:ok, [], socket} = SocketTest.send_event(socket, "noreply")
      assert SocketTest.socket(socket).assigns.stored
    end

    test "unknown events use the injected catch-all and keep the connection", %{socket: socket} do
      assert {:ok, [], socket} = SocketTest.send_event(socket, "not-defined")

      assert {:ok, [{:text, "ok"}], _socket} =
               SocketTest.send_event(socket, "echo", %{"message" => "ok"})
    end

    test "malformed JSON, arrays, and binary frames stay open", %{socket: socket} do
      assert {:ok, [], socket} = SocketTest.send_frame(socket, "not json")
      assert {:ok, [], socket} = SocketTest.send_frame(socket, "[1,2]")
      assert {:ok, [], socket} = SocketTest.send_binary(socket, <<1, 2, 3>>)

      assert {:ok, [{:text, "ok"}], _socket} =
               SocketTest.send_event(socket, "echo", %{"message" => "ok"})
    end
  end

  describe "replies and server push" do
    setup do
      {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.TestSocket)
      %{socket: socket}
    end

    test "sends plain HTML without an envelope", %{socket: socket} do
      html = "<p>Hello</p>"

      assert {:ok, [{:text, ^html}], _socket} =
               SocketTest.send_event(socket, "echo", %{"message" => html})
    end

    test "renders HEEx through Phoenix.HTML.Safe", %{socket: socket} do
      assert {:ok, [{:text, "<p>Hello, World!</p>"}], _socket} =
               SocketTest.send_event(socket, "heex")
    end

    test "keeps raw iodata and safe iodata as frame data", %{socket: socket} do
      assert {:ok, [{:text, "<p>iodata</p>"}], socket} =
               SocketTest.send_event(socket, "iodata")

      assert {:ok, [{:text, "<p>safe</p>"}], _socket} =
               SocketTest.send_event(socket, "safe")
    end

    test "builds envelopes with only supplied keys and preserves swap modifiers", %{
      socket: socket
    } do
      params = %{"target" => "#messages", "swap" => "beforeend settle:10ms"}

      assert {:ok, [{:text, frame}], socket} = SocketTest.send_event(socket, "envelope", params)

      assert Jason.decode!(frame) == %{
               "content" => "<p>ok</p>",
               "target" => "#messages",
               "swap" => "beforeend settle:10ms"
             }

      assert {:ok, [{:text, frame}], _socket} =
               SocketTest.send_event(socket, "envelope", %{"select" => ".message"})

      assert Jason.decode!(frame) == %{"content" => "<p>ok</p>", "select" => ".message"}
    end

    test "stops using the documented tuple", %{socket: socket} do
      assert {:stop, :normal, _socket} = SocketTest.send_event(socket, "stop")
    end

    test "raises for an unknown option and unsupported body", %{socket: socket} do
      assert_raise ArgumentError, ~r/bogus/, fn -> SocketTest.send_event(socket, "bad_option") end

      assert_raise ArgumentError, ~r/PhoenixHtmxWs.TestSocket.*bad_body.*map/, fn ->
        SocketTest.send_event(socket, "bad_body")
      end

      assert_raise ArgumentError, ~r/PhoenixHtmxWs.TestSocket.*bad_tuple.*tuple/, fn ->
        SocketTest.send_event(socket, "bad_tuple")
      end
    end

    test "pushes plain HTML and envelopes without a client frame", %{socket: socket} do
      assert {:ok, [{:text, "<p>push</p>"}], socket} =
               SocketTest.send_info(socket, {:push, "<p>push</p>"})

      assert {:ok, [{:text, frame}], _socket} =
               SocketTest.send_info(
                 socket,
                 {:push, "<p>push</p>", target: "#feed", swap: "beforeend"}
               )

      assert Jason.decode!(frame) == %{
               "content" => "<p>push</p>",
               "target" => "#feed",
               "swap" => "beforeend"
             }
    end
  end

  test "connect_path appends one encoded CSRF token and keeps parameters" do
    path = PhoenixHtmxWs.connect_path("/socket?room=123", page: 2)
    uri = URI.parse(path)
    params = URI.decode_query(uri.query)

    assert uri.path == "/socket"
    assert params["room"] == "123"
    assert params["page"] == "2"
    assert is_binary(params["_csrf_token"])
    refute params["_csrf_token"] =~ "%"
  end

  test "a custom error callback sends an HTML envelope and keeps the connection" do
    {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.ErrorReplySocket)
    assert {:ok, [{:text, frame}], socket} = SocketTest.send_frame(socket, "not json")

    assert Jason.decode!(frame) == %{
             "content" => ~s(<p class="error">Bad request</p>),
             "target" => "#errors"
           }

    assert {:ok, [], _socket} = SocketTest.send_frame(socket, ~s({"event":"unknown"}))
  end

  test "a clause for one error reason keeps the default for the other reasons" do
    {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.ErrorReplySocket)

    assert {:ok, [], socket} = SocketTest.send_frame(socket, "[1,2]")
    assert {:ok, [], socket} = SocketTest.send_binary(socket, <<1, 2, 3>>)

    assert {:ok, [{:text, _frame}], _socket} = SocketTest.send_frame(socket, "not json")
  end

  test "an invalid error callback return names handle_error" do
    {:ok, socket} = SocketTest.connect(PhoenixHtmxWs.InvalidErrorReturnSocket)

    assert_raise ArgumentError, ~r/InvalidErrorReturnSocket\.handle_error/, fn ->
      SocketTest.send_frame(socket, "not json")
    end
  end
end
