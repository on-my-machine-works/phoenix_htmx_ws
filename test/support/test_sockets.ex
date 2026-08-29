defmodule PhoenixHtmxWs.TestComponent do
  use Phoenix.Component

  def greeting(assigns) do
    ~H"<p>Hello, {@name}!</p>"
  end
end

defmodule PhoenixHtmxWs.TestSocket do
  use PhoenixHtmxWs.Socket

  @impl true
  def connect(%{"authorized" => false}, _session, _socket), do: :error

  def connect(params, session, socket) do
    {:ok, assign(socket, %{connect_params: params, connect_session: session})}
  end

  @impl true
  def mount(params, socket) do
    if pid = params["notify"] do
      send(pid, {:mounted, self()})
    end

    {:ok, assign(socket, %{mounted: true, count: 0})}
  end

  @impl true
  def handle_event("echo", params, socket), do: {:reply, params["message"], socket}

  def handle_event("inspect", params, socket) do
    body = Jason.encode!(%{"params" => params, "headers" => socket.meta.headers})
    {:reply, body, socket}
  end

  def handle_event("envelope", params, socket) do
    opts =
      [:target, :swap, :select]
      |> Enum.flat_map(fn key ->
        case params[Atom.to_string(key)] do
          nil -> []
          value -> [{key, value}]
        end
      end)

    {:reply, "<p>ok</p>", opts, socket}
  end

  def handle_event("heex", _params, socket) do
    {:reply, PhoenixHtmxWs.TestComponent.greeting(%{name: "World"}), socket}
  end

  def handle_event("iodata", _params, socket), do: {:reply, ["<p>", "iodata", "</p>"], socket}

  def handle_event("safe", _params, socket),
    do: {:reply, {:safe, ["<p>", "safe", "</p>"]}, socket}

  def handle_event("increment", _params, socket) do
    socket = update(socket, :count, &(&1 + 1))
    {:reply, Integer.to_string(socket.assigns.count), socket}
  end

  def handle_event("noreply", _params, socket), do: {:noreply, assign(socket, :stored, true)}
  def handle_event("stop", _params, socket), do: {:stop, :normal, socket}
  def handle_event("bad_option", _params, socket), do: {:reply, "x", [bogus: "x"], socket}
  def handle_event("bad_body", _params, socket), do: {:reply, %{html: "no"}, socket}
  def handle_event("bad_tuple", _params, socket), do: {:reply, {:not, :safe}, socket}
  def handle_event("crash", _params, _socket), do: raise("socket exploded")

  @impl true
  def handle_info({:push, body}, socket), do: {:push, body, socket}

  def handle_info({:push, body, opts}, socket), do: {:push, body, opts, socket}
end

defmodule PhoenixHtmxWs.ErrorReplySocket do
  use PhoenixHtmxWs.Socket

  @impl true
  def handle_error(:invalid_json, _payload, socket) do
    {:reply, ~s(<p class="error">Bad request</p>), [target: "#errors"], socket}
  end
end

defmodule PhoenixHtmxWs.TelemetryParamsSocket do
  use PhoenixHtmxWs.Socket, telemetry_params: true

  @impl true
  def handle_event("echo", %{"message" => message}, socket), do: {:reply, message, socket}
end

defmodule PhoenixHtmxWs.ActionSocket do
  use PhoenixHtmxWs.Socket, event_key: "action", default_event: "fallback"

  @impl true
  def handle_event("save" = event, params, socket) do
    {:reply, Jason.encode!(%{"event" => event, "params" => params}), socket}
  end

  def handle_event("fallback" = event, params, socket) do
    {:reply, Jason.encode!(%{"event" => event, "params" => params}), socket}
  end
end

defmodule PhoenixHtmxWs.OptionalSessionSocket do
  use PhoenixHtmxWs.Socket, require_session: false

  @impl true
  def handle_event("ping", _params, socket), do: {:reply, "pong", socket}
end

defmodule PhoenixHtmxWs.MountStopSocket do
  use PhoenixHtmxWs.Socket

  @impl true
  def mount(_params, socket), do: {:stop, :maintenance, assign(socket, :mounted, false)}
end

defmodule PhoenixHtmxWs.ExceptionCallbacksSocket do
  use PhoenixHtmxWs.Socket

  @impl true
  def handle_error(:invalid_json, _payload, _socket), do: raise("error callback exploded")

  @impl true
  def handle_info(:crash, _socket), do: raise("info callback exploded")
end

defmodule PhoenixHtmxWs.InvalidErrorReturnSocket do
  use PhoenixHtmxWs.Socket

  @impl true
  def handle_error(:invalid_json, _payload, _socket), do: :invalid
end
