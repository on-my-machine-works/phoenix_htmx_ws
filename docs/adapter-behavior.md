# Adapter behavior record

The experiments ran on 2026-08-29 with Elixir 1.20.3 and OTP 29.
They used Phoenix 1.8.13, Bandit 1.12.5, Cowboy 2.18.0, and WebSockAdapter 0.6.0.

Run the recorded probes with these commands:

```sh
mix test test/phoenix_htmx_ws/integration_test.exs
mix test test/phoenix_htmx_ws/cowboy_integration_test.exs
mix test --include experiment test/phoenix_htmx_ws/adapter_behavior_experiment_test.exs
```

The short tests send stop reasons, raise an exception, and send ping frames.
The long test opens both adapters at the same time.
It sends no client data for more than 60 seconds.
It also sends a 10.1 MB reply and stops both endpoints.

## Close codes

The browser-facing results were:

| Socket result | Bandit | Cowboy | htmx reconnects |
|---|---:|---:|---|
| `{:stop, :normal, socket}` | 1000 | 1000 | No |
| `{:stop, :shutdown, socket}` | 1011 | 1000 | Bandit only |
| Unhandled exception | 1011 | 1011 | Yes |

A handler can use `{:stop, :normal, socket}` to stop htmx reconnection on both tested adapters.
The documented callback does not accept an explicit close code.

Do not use another stop reason to request one portable reconnect behavior.
Bandit and Cowboy map generic stop reasons differently.

Use the htmx connection option `ws.reconnect:false` when the client must disable all automatic reconnects.

## Idle timeout and ping frames

Both endpoints used `timeout: 60_000`.
The clients sent no application data after the initial probe.

Bandit closed at approximately 60 seconds with code 1002.
Cowboy closed at approximately 66 seconds with code 1000.
Neither connection survived for 90 seconds.

The clients received no server ping frame before either close.
The adapters did not reset the timeout with an automatic ping.

The close-code difference does not change the default htmx result.
The default reconnect list does not contain 1002.
Code 1000 also stops reconnection.

Applications must select an explicit timeout for idle htmx connections.
A long timeout retains idle processes.
A short timeout repeats authentication and `mount/2` work.

## Drain on shutdown

The first experiment used `drainer_spec/1` with `:ignore`.
Bandit closed with code 1000, so htmx did not reconnect.
Cowboy closed without a close frame, which browsers report as 1006.
htmx reconnects for 1006.

These inconsistent results showed that `:ignore` was not correct.
The package now registers active socket processes and supplies a drainer.
The drainer sends `{:shutdown, :restart}` through the transport before endpoint shutdown.

The final experiment received code 1012 from Bandit and Cowboy.
The default htmx reconnect list contains 1012.

## Control frames

The clients sent a ping with the payload `probe` to each adapter.
Both clients received a pong with the same payload.

The socket module does not define `handle_control/2`.
Bandit and Cowboy handle ping and pong frames without that callback.

## Frame size

The WebSockAdapter default incoming frame limit is 10 MB.
Cowboy itself has a 1 MB default, but WebSockAdapter supplies its own limit.
Bandit has an 8 MB default outside WebSockAdapter.

The experiment produced one 10.1 MB text reply from each server.
Both clients received the complete reply.
The incoming frame limit did not limit an outgoing reply.

An incoming frame beyond the configured limit closes with code 1009.
Applications can set `max_frame_size` in WebSocket configuration.

Keep the limit finite for untrusted client input.
Also limit response data in the application because large replies consume memory and network capacity.
