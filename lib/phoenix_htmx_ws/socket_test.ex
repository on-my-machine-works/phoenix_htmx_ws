defmodule PhoenixHtmxWs.SocketTest do
  @moduledoc """
  Test helpers that exercise the same transport callbacks as a real connection.

  The returned socket value is opaque transport state. `frames` always contains
  `{:text, binary}` tuples, matching the WebSocket wire contract.
  """

  alias PhoenixHtmxWs.Transport.State

  @enforce_keys [:state]
  defstruct [:state]

  @opaque t :: %__MODULE__{state: State.t()}

  @doc "Connects and mounts a socket module through its real callbacks."
  @spec connect(module(), keyword()) ::
          {:ok, t()} | {:stop, term(), t()} | :error | {:error, term()}
  def connect(module, opts \\ []) when is_atom(module) and is_list(opts) do
    params = Keyword.get(opts, :params, %{})
    explicit_session? = Keyword.has_key?(opts, :session)
    session = Keyword.get(opts, :session)
    connect_info = Keyword.get(opts, :connect_info, %{})

    connect_info =
      if explicit_session?, do: Map.put(connect_info, :session, session), else: connect_info

    transport_options =
      if explicit_session? or Keyword.get(opts, :session_configured, false) do
        [connect_info: [session: :configured]]
      else
        [connect_info: []]
      end

    info = %{
      endpoint: Keyword.get(opts, :endpoint, PhoenixHtmxWs.SocketTest.Endpoint),
      transport: :websocket,
      params: params,
      connect_info: connect_info,
      options: Keyword.get(opts, :transport_options, transport_options)
    }

    with {:ok, state} <- module.connect(info) do
      case module.init(state) do
        {:ok, state} ->
          {:ok, %__MODULE__{state: state}}

        {:stop, reason, state} ->
          unregister_connection(state)
          {:stop, reason, %__MODULE__{state: state}}
      end
    end
  end

  @doc "Sends an event using the htmx 4 JSON frame shape."
  @spec send_event(t(), binary(), map()) :: {:ok, [{:text, binary()}], t()} | tuple()
  def send_event(%__MODULE__{state: %State{socket: public_socket}} = socket, event, params \\ %{})
      when is_binary(event) and is_map(params) do
    event_key = public_socket.private.config.event_key
    payload = params |> Map.put(event_key, event) |> Jason.encode!()
    send_frame(socket, payload)
  end

  @doc "Sends one raw text frame, including malformed JSON."
  @spec send_frame(t(), binary()) :: {:ok, [{:text, binary()}], t()} | tuple()
  def send_frame(%__MODULE__{state: %State{handler: module} = state}, payload)
      when is_binary(payload) do
    module.handle_in({payload, opcode: :text}, state)
    |> normalize_result()
  end

  @doc "Sends one raw binary frame."
  @spec send_binary(t(), binary()) :: {:ok, [{:text, binary()}], t()} | tuple()
  def send_binary(%__MODULE__{state: %State{handler: module} = state}, payload)
      when is_binary(payload) do
    module.handle_in({payload, opcode: :binary}, state)
    |> normalize_result()
  end

  @doc "Delivers a process message through the real transport callback."
  @spec send_info(t(), term()) :: {:ok, [{:text, binary()}], t()} | tuple()
  def send_info(%__MODULE__{state: %State{handler: module} = state}, message) do
    module.handle_info(message, state)
    |> normalize_result()
  end

  @doc "Returns the public socket state for assertions."
  @spec socket(t()) :: PhoenixHtmxWs.Socket.t()
  def socket(%__MODULE__{state: %State{socket: socket}}), do: socket

  @doc "Terminates the transport state through the real callback."
  @spec terminate(t(), term()) :: :ok
  def terminate(%__MODULE__{state: %State{handler: module} = state}, reason) do
    try do
      module.terminate(reason, state)
    after
      unregister_connection(state)
    end
  end

  defp normalize_result({:ok, state}), do: {:ok, [], %__MODULE__{state: state}}

  defp normalize_result({:reply, _status, {opcode, body}, state}) do
    {:ok, [{opcode, IO.iodata_to_binary(body)}], %__MODULE__{state: state}}
  end

  defp normalize_result({:push, {opcode, body}, state}) do
    {:ok, [{opcode, IO.iodata_to_binary(body)}], %__MODULE__{state: state}}
  end

  defp normalize_result({:stop, reason, state}),
    do: {:stop, reason, %__MODULE__{state: state}}

  defp unregister_connection(%State{handler: handler, socket: socket}) do
    Registry.unregister_match(
      PhoenixHtmxWs.ConnectionRegistry,
      {socket.endpoint, handler},
      socket.id
    )
  end
end

defmodule PhoenixHtmxWs.SocketTest.Endpoint do
  @moduledoc false
end
