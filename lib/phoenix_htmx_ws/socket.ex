defmodule PhoenixHtmxWs.Socket do
  @moduledoc """
  Connection state and the `use` macro for an htmx WebSocket handler.

  `meta` describes only the event currently being dispatched. It is reset to
  `%{}` before the transport stores the returned socket. `private` belongs to
  this library and application code must not modify it.
  """

  @type t :: %__MODULE__{
          endpoint: module(),
          params: %{optional(binary()) => term()},
          session: map() | nil,
          connect_info: map(),
          assigns: map(),
          meta: map(),
          id: binary(),
          connected_at: DateTime.t(),
          private: map()
        }

  @type options :: keyword(binary())
  @type event_result ::
          {:noreply, t()}
          | {:reply, term(), t()}
          | {:reply, term(), options(), t()}
          | {:stop, term(), t()}
  @type info_result ::
          {:noreply, t()}
          | {:push, term(), t()}
          | {:push, term(), options(), t()}
          | {:stop, term(), t()}

  @enforce_keys [:endpoint, :params, :session, :connect_info, :id, :connected_at]
  defstruct endpoint: nil,
            params: %{},
            session: nil,
            connect_info: %{},
            assigns: %{},
            meta: %{},
            id: nil,
            connected_at: nil,
            private: %{}

  @callback connect(params :: map(), session :: map() | nil, socket :: t()) ::
              {:ok, t()} | :error | {:error, term()}
  @callback mount(params :: map(), socket :: t()) :: {:ok, t()} | {:stop, term(), t()}
  @callback handle_event(event :: binary(), params :: map(), socket :: t()) ::
              event_result()
  @callback handle_error(reason :: atom(), payload :: term(), socket :: t()) ::
              event_result()
  @callback handle_info(message :: term(), socket :: t()) :: info_result()
  @callback terminate(reason :: term(), socket :: t()) :: term()

  @optional_callbacks connect: 3, mount: 2, handle_error: 3, handle_info: 2, terminate: 2

  @doc false
  defmacro __using__(opts \\ []) do
    event_key = Keyword.get(opts, :event_key, "event")
    default_event = Keyword.get(opts, :default_event, "message")
    require_session = Keyword.get(opts, :require_session, true)
    telemetry_params = Keyword.get(opts, :telemetry_params, false)

    unless is_binary(event_key), do: raise(ArgumentError, ":event_key must be a string")
    unless is_binary(default_event), do: raise(ArgumentError, ":default_event must be a string")

    unless is_boolean(require_session),
      do: raise(ArgumentError, ":require_session must be a boolean")

    unless is_boolean(telemetry_params),
      do: raise(ArgumentError, ":telemetry_params must be a boolean")

    config = %{
      event_key: event_key,
      default_event: default_event,
      require_session: require_session,
      telemetry_params: telemetry_params
    }

    quote bind_quoted: [config: Macro.escape(config)] do
      @behaviour PhoenixHtmxWs.Socket
      @phoenix_htmx_ws_config config
      @before_compile PhoenixHtmxWs.Socket

      require Logger

      import PhoenixHtmxWs.Socket, only: [assign: 2, assign: 3, update: 3]

      # Phoenix.Socket.Transport callbacks. Application code never defines these.
      @doc false
      def child_spec(_opts), do: :ignore

      @doc false
      def drainer_spec(opts), do: PhoenixHtmxWs.Drainer.child_spec({__MODULE__, opts})

      @doc false
      def connect(transport_info) when is_map(transport_info) do
        PhoenixHtmxWs.Transport.connect(__MODULE__, transport_info, @phoenix_htmx_ws_config)
      end

      @doc false
      def init(%PhoenixHtmxWs.Transport.State{} = state) do
        PhoenixHtmxWs.Transport.init(state)
      end

      @doc false
      def handle_in(frame, %PhoenixHtmxWs.Transport.State{} = state) do
        PhoenixHtmxWs.Transport.handle_in(frame, state)
      end

      # These transport clauses use a distinct state struct. Application
      # callback clauses receive PhoenixHtmxWs.Socket instead.
      @doc false
      def handle_info(message, %PhoenixHtmxWs.Transport.State{} = state) do
        PhoenixHtmxWs.Transport.handle_info(message, state)
      end

      @doc false
      def terminate(reason, %PhoenixHtmxWs.Transport.State{} = state) do
        PhoenixHtmxWs.Transport.terminate(reason, state)
      end

      @impl PhoenixHtmxWs.Socket
      def connect(_params, _session, socket), do: {:ok, socket}

      @impl PhoenixHtmxWs.Socket
      def mount(_params, socket), do: {:ok, socket}

      defoverridable connect: 3, mount: 2
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @impl PhoenixHtmxWs.Socket
      def handle_event(event, _params, socket) do
        Logger.debug(fn ->
          "PhoenixHtmxWs: ignored unknown event #{inspect(event)} on #{inspect(__MODULE__)}"
        end)

        {:noreply, socket}
      end

      @impl PhoenixHtmxWs.Socket
      def handle_error(reason, payload, socket) do
        Logger.debug(fn ->
          "PhoenixHtmxWs: ignored #{inspect(reason)} payload on #{inspect(__MODULE__)}: " <>
            inspect(payload, limit: 20)
        end)

        {:noreply, socket}
      end

      @impl PhoenixHtmxWs.Socket
      def handle_info(_message, %PhoenixHtmxWs.Socket{} = socket), do: {:noreply, socket}

      @impl PhoenixHtmxWs.Socket
      def terminate(_reason, %PhoenixHtmxWs.Socket{}), do: :ok

      defoverridable handle_event: 3, handle_error: 3, handle_info: 2, terminate: 2
    end
  end

  @doc "Assigns one value for the life of this connection."
  @spec assign(t(), atom(), term()) :: t()
  def assign(%__MODULE__{} = socket, key, value) when is_atom(key) do
    %{socket | assigns: Map.put(socket.assigns, key, value)}
  end

  @doc "Merges a map or keyword list into the connection assigns."
  @spec assign(t(), map() | keyword()) :: t()
  def assign(%__MODULE__{} = socket, attrs) when is_map(attrs) or is_list(attrs) do
    %{socket | assigns: Map.merge(socket.assigns, Map.new(attrs))}
  end

  @doc "Updates an existing assign with a unary function."
  @spec update(t(), atom(), (term() -> term())) :: t()
  def update(%__MODULE__{} = socket, key, fun) when is_atom(key) and is_function(fun, 1) do
    %{socket | assigns: Map.update!(socket.assigns, key, fun)}
  end
end
