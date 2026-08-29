# PhoenixHtmxWs

`PhoenixHtmxWs` connects the htmx 4 `hx-ws` extension to a Phoenix WebSocket.
It implements `Phoenix.Socket.Transport` and sends HTML over text frames.
It does not implement the Phoenix Channels protocol.

The library requires no LiveView process, no Phoenix Channels protocol, and no `phoenix.js`.
An application that uses HEEx must add `phoenix_live_view` itself.

Supported versions:

- Elixir 1.17 or later
- OTP 27 or later
- Phoenix 1.8 or later
- htmx 4.0.0 or later

The package has runtime dependencies on `phoenix`, `jason`, and `phoenix_html`.
The `phoenix_live_view` dependency is optional and available only in development and test environments.

## Installation

Add the package to `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_htmx_ws, "~> 0.1"}
  ]
end
```

## Endpoint setup

Phoenix puts a WebSocket transport below the socket path by default.
The default transport path is `/websocket`.

Keep the default path with this setup:

```elixir
socket "/htmx/chat/:room_id", MyAppWeb.ChatSocket, websocket: true
```

The browser must connect to `/htmx/chat/123/websocket` for this setup.

The example application puts the transport at the socket root:

```elixir
@session_options [
  store: :cookie,
  key: "_my_app_key",
  signing_salt: "session salt",
  same_site: "Lax"
]

socket "/htmx/chat/:room_id", MyAppWeb.ChatSocket,
  websocket: [
    path: "/",
    timeout: 300_000,
    connect_info: [:uri, :peer_data, session: @session_options]
  ],
  longpoll: false
```

The browser connects to `/htmx/chat/123` for this setup.
Phoenix adds path parameters and query parameters to the `params` map.

Use the same `@session_options` list for `Plug.Session` and `connect_info`.
A different list makes session authentication fail.

The Phoenix timeout is an idle timeout after the last client data.
A long timeout keeps idle processes for longer.
A short timeout causes more reconnections and more `mount/2` calls.

## Client markup

Load htmx and its separate WebSocket extension:

```html
<script src="https://cdn.jsdelivr.net/npm/htmx.org@4.0.0/dist/htmx.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/htmx.org@4.0.0/dist/ext/hx-ws.min.js"></script>
```

Use `PhoenixHtmxWs.connect_path/1` for an authenticated connection:

```heex
<div
  hx-ws:connect={PhoenixHtmxWs.connect_path(~p"/htmx/chat/#{@room.id}")}
  hx-target="#messages"
  hx-swap="beforeend"
>
  <div id="messages"></div>

  <form hx-ws:send hx-vals='{"event": "send_message"}'>
    <input name="message" autocomplete="off" />
    <button type="submit">Send</button>
  </form>
</div>
```

Use `hx-ws-connect` and `hx-ws-send` when a template cannot contain a colon.
Each connection element owns one WebSocket and one server process.
Two elements with the same URL open two connections.

An `hx-ws:send` element uses its nearest connection element.
The value of the `hx-ws:send` attribute has no effect.

The default trigger depends on the element:

- A form uses `submit`.
- A text input, textarea, or select uses `change`.
- A button or other element uses `click`.

## Socket callbacks

Define a socket module:

```elixir
defmodule MyAppWeb.ChatSocket do
  use PhoenixHtmxWs.Socket

  @impl true
  def connect(params, session, socket) do
    case Accounts.get_user_by_session_token(session["user_token"]) do
      nil -> :error
      user -> {:ok, assign(socket, :current_user, user)}
    end
  end

  @impl true
  def mount(%{"room_id" => room_id}, socket) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, "room:#{room_id}")
    {:ok, assign(socket, :room_id, room_id)}
  end

  @impl true
  def handle_event("send_message", %{"message" => body}, socket) do
    {:ok, _message} = Chat.create_message(socket.assigns.room_id, body)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:message_created, message}, socket) do
    html = MyAppWeb.ChatComponents.message(%{message: message})
    {:push, html, [target: "#messages", swap: "beforeend"], socket}
  end
end
```

The library supplies defaults for `connect/3` and `mount/2`.
It appends a final fallback clause to `handle_event/3`, `handle_error/3`, `handle_info/2`, and `terminate/2`.
A fallback runs after every application clause for the same callback.
An application clause for one event, error reason, or message therefore keeps the default for the others.
Unknown events produce a debug log and keep the connection open.

The callbacks accept these return values:

```text
connect/3:      {:ok, socket} | :error | {:error, reason}
mount/2:        {:ok, socket} | {:stop, reason, socket}
handle_event/3: {:noreply, socket}
                {:reply, html, socket}
                {:reply, html, options, socket}
                {:stop, reason, socket}
handle_info/2:  {:noreply, socket}
                {:push, html, socket}
                {:push, html, options, socket}
                {:stop, reason, socket}
```

Response options can contain `:target`, `:swap`, and `:select`.
An unknown option raises `ArgumentError` and names the option.
The library passes each `swap` string without parsing it.

One callback can send one frame.
Send a message to `self()` when one event must produce another frame.
Then send that frame from `handle_info/2`.

Use multiple `<hx-partial>` elements when one frame must update multiple regions.

The macro imports these helpers:

```elixir
assign(socket, key, value)
assign(socket, map_or_keyword)
update(socket, key, fun)
```

## Incoming frames

htmx 4 sends one JSON object in each text frame:

```json
{
  "headers": {"HX-Request": "true"},
  "event": "send_message",
  "message": "hello",
  "tag": ["urgent", "public"],
  "count": 2,
  "active": true
}
```

The library removes `headers` and puts its value in `socket.meta.headers`.
It removes `event` and uses its string value as the event name.
The handler receives all other keys in the params map.

`socket.meta` describes only the current dispatch.
The value is `%{}` outside `handle_event/3`.

The default event is `message` when the frame has no event key.
Use another key and default with these options:

```elixir
use PhoenixHtmxWs.Socket, event_key: "action", default_event: "fallback"
```

Set the event key in `hx-vals` or a named form control:

```html
<form hx-ws:send hx-vals='{"event": "send_message"}'>
<button hx-ws:send name="event" value="save">Save</button>
```

A form field named `event` becomes the event name.
A form field named `headers` never reaches the server because htmx reserves that key.

Params contain JSON values, not Plug form values.
A repeated form field becomes a list.
An `hx-vals` number stays a number, and a Boolean stays a Boolean.
Do not match every handler value as a string.

The package supports only the htmx 4 frame format.
It does not support the htmx 2 `HEADERS` key or nested values.

## Outgoing frames and swaps

A reply without options sends plain HTML:

```text
<div class="message">Hello</div>
```

The connection element controls the target and swap for plain HTML.
The default target is the connection element.
The default swap is `innerHTML`.

A reply with at least one option sends a JSON envelope:

```json
{
  "content": "<div class=\"message\">Hello</div>",
  "target": "#messages",
  "swap": "beforeend settle:10ms",
  "select": ".message"
}
```

The envelope always contains `content`.
It contains only the supplied option keys.
The envelope never uses the old beta key `payload`.

A JSON object without `content` does not produce a swap.
For this reason, error replies must also contain HTML.

The library forwards HTML without changes.
Use explicit htmx 4 extra-swap syntax in the body:

```html
<hx-partial hx-target="#messages" hx-swap="beforeend">
  <p class="message">Hello</p>
</hx-partial>

<span id="unread-count" hx-swap-oob="true">4</span>
```

htmx extracts these elements before the normal swap.
The default `swapEmpty:false` keeps the connection element unchanged when no normal content remains.

## Rendering and HTML safety

Responses can be a binary, iodata, `{:safe, iodata}`, or a `Phoenix.HTML.Safe` value.
HEEx component output implements `Phoenix.HTML.Safe` when the application includes `phoenix_live_view`.

> The library trusts the HTML you give it. Render user input through HEEx or another escaping template. Never pass raw user input as the response body.

A binary is raw HTML and the library does not escape it.
An unsupported value raises `ArgumentError` with the socket module, event, and received type.

## Session authentication and CSRF

Phoenix reads a WebSocket session only through `connect_info`.
Phoenix validates that session with the `_csrf_token` request parameter.
The request parameter name is fixed.

Use `PhoenixHtmxWs.connect_path/1` or `connect_path/2` to add the token once.
`URI.encode_query/1` performs the required encoding.

Phoenix returns a `nil` session for a missing cookie or invalid token.
Phoenix does not reject that connection itself.

`PhoenixHtmxWs` rejects a `nil` configured session by default.
It logs the cause and the `connect_path/1` fix at error level.
The library does not call `mount/2` after this rejection.

Use this option only for a socket that permits anonymous access:

```elixir
use PhoenixHtmxWs.Socket, require_session: false
```

Origin checking is active by default.
Phoenix also sets `check_csrf: true` by default.
Phoenix rejects a setup that sets both `check_origin` and `check_csrf` to `false`.

The application authenticates the connection once in `connect/3`.
Do a permission check in each event when permissions can change during a connection.

## Lifecycle and reconnects

`connect/3` can run outside the final socket process.
Do not subscribe to PubSub, start a timer, or store `self()` in `connect/3`.
Put process work in `mount/2`.

`terminate/2` runs when the transport can call it.
Do not depend on `terminate/2` for persistent data.

htmx owns reconnect behavior.
The library does not implement a reconnect protocol.

htmx reconnects for codes 1001, 1005, 1006, 1011, 1012, 1013, and 1014.
Code 1000 stops reconnection.
The first delay is 500 ms and each later delay doubles.
The maximum delay is 60000 ms, the jitter is 0.3, and attempts are unlimited.

`ws.pauseOnBackground` is `true` by default.
htmx closes the connection while the page is hidden and reconnects when the page becomes visible.

Every reconnect creates a new socket process.
It runs `connect/3` and `mount/2` again.
Connection assigns do not survive.

Keep `mount/2` inexpensive because a tab switch can run it again.
Store persistent state in a context, database, cache, or named process.
Use assigns only for connection view state.

A deterministic mount exception can create a reconnect and crash loop.
The retries use the htmx backoff values.

htmx queues at most 100 outgoing messages by default while a connection opens.
It sends those messages in order after the new connection opens.
A queued event can arrive in a new socket process after another `mount/2` call.

The package drainer sends close code 1012 during an endpoint shutdown.
This code makes htmx reconnect after an application restart.

Read [the adapter behavior record](docs/adapter-behavior.md) for close codes and idle behavior.

## Errors and telemetry

`handle_error/3` receives these reasons:

| Reason | Cause |
|---|---|
| `:invalid_json` | The text frame is not valid JSON. |
| `:invalid_payload` | The JSON value is not an object. |
| `:unsupported_frame` | The frame is binary. |

The default callback logs at debug level and keeps the connection open.
An error callback accepts the same return values as `handle_event/3`.
A clause for one reason leaves the default in place for the other reasons.

```elixir
def handle_error(:invalid_json, _payload, socket) do
  {:reply, ~s(<p class="error">Bad request</p>), [target: "#errors"], socket}
end
```

An application exception in `handle_event/3`, `handle_error/3`, or `handle_info/2`
emits the event exception telemetry event. The metadata event is the client event
name, the error reason, or `"handle_info"`, respectively. The library then raises
the same exception with its original stack trace. Only that socket process stops.

The package emits these telemetry events:

```text
[:phoenix_htmx_ws, :socket, :connect]
[:phoenix_htmx_ws, :socket, :disconnect]
[:phoenix_htmx_ws, :event, :start]
[:phoenix_htmx_ws, :event, :stop]
[:phoenix_htmx_ws, :event, :exception]
[:phoenix_htmx_ws, :push]
```

Every event carries `socket` and `socket_id` in its metadata.
Each `event` event adds `event` and `payload_size`, and the exception event adds `kind`, `reason`, and `stacktrace`.
The `[:event, :stop]` metadata also carries `response_size`.

| Event | Measurements |
|---|---|
| `[:socket, :connect]` | `system_time` |
| `[:socket, :disconnect]` | `duration` of the connection |
| `[:event, :start]` | `system_time`, `monotonic_time` |
| `[:event, :stop]` | `duration` of the handler, `monotonic_time` |
| `[:event, :exception]` | `duration`, `monotonic_time` |
| `[:push]` | `response_size` |

A `handle_info/2` dispatch reports the event name `handle_info` and a `payload_size` of zero.
An error frame reports the reason as the event name, such as `invalid_json`.
Form values are not telemetry metadata by default.

Use this option only when telemetry can contain form values:

```elixir
use PhoenixHtmxWs.Socket, telemetry_params: true
```

Normal operation produces no info-level package logs.
Bad input and protocol misuse produce debug logs.
Session configuration errors produce error logs.

## Test helpers

`PhoenixHtmxWs.SocketTest` calls the real transport callbacks.
It does not use a second dispatch path.

```elixir
alias PhoenixHtmxWs.SocketTest

{:ok, socket} =
  SocketTest.connect(MyAppWeb.ChatSocket,
    params: %{"room_id" => "123"},
    session: %{"user_token" => "token"},
    connect_info: %{}
  )

{:ok, frames, socket} =
  SocketTest.send_event(socket, "send_message", %{"message" => "hello"})

{:ok, frames, socket} =
  SocketTest.send_frame(socket, ~s({"event":"send_message","message":"hello"}))

{:ok, frames, socket} =
  SocketTest.send_info(socket, {:message_created, message})
```

Each frame is `{:text, binary}`.
Use `send_frame/2` for malformed JSON and `send_binary/2` for a binary frame.

## Operations and limits

The adapters process ping and pong frames without `handle_control/2` in this socket.
The package does not create a process for each message.
It keeps plain HTML as iodata until the adapter writes the frame.

Adapter frame-size limits apply to incoming client frames.
The experiments sent a 10.1 MB server reply through Bandit and Cowboy.
Both clients received the complete reply.

Set request-size limits for the adapter and application threat model.
Large replies still consume socket memory and network capacity.

Slow-client backpressure and outgoing queue limits are delegated to the selected transport.

Run the benchmark with:

```sh
MIX_ENV=dev mix run bench/benchmark.exs
```

The benchmark measures connection setup, incoming events, outgoing pushes, safe rendering, and idle state memory.
It defines no performance target.

## Development

Run the library and integration tests:

```sh
mix test
```

Run the long Bandit and Cowboy experiments:

```sh
mix test --include experiment test/phoenix_htmx_ws/adapter_behavior_experiment_test.exs
```

Run the real Chromium tests:

```sh
cd example
npm install
npx playwright install chromium
npm run test:browser
```

The [example chat](example/README.md) uses a real Phoenix endpoint, PubSub, HEEx, and htmx 4.
It contains no custom client JavaScript.
