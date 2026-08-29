# PhoenixHtmxWs example chat

From this directory, run:

```sh
mix deps.get
mix run --no-halt
```

Open <http://localhost:4000> in two windows. A submitted message travels from
htmx through the socket and chat context, then through PubSub to both windows.
The application has no custom JavaScript.

The endpoint puts the WebSocket transport at the root of the socket path, so
the browser connects to `/htmx/chat/general`, not
`/htmx/chat/general/websocket`. It sets a five-minute idle timeout. This keeps
an idle chat open longer than Phoenix's one-minute default without retaining
idle processes indefinitely. A shorter timeout saves resources but causes more
reconnections and repeated `mount/2` calls.
