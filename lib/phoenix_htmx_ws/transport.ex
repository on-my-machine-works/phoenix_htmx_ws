defmodule PhoenixHtmxWs.Transport do
  @moduledoc false

  require Logger

  alias PhoenixHtmxWs.Socket
  alias PhoenixHtmxWs.Transport.State

  @valid_options [:target, :swap, :select]

  @spec connect(module(), map(), map()) :: {:ok, State.t()} | :error | {:error, term()}
  def connect(handler, info, config) do
    started = System.monotonic_time()
    connect_info = Map.get(info, :connect_info, %{})
    options = Map.get(info, :options, [])
    session = Map.get(connect_info, :session)
    params = Map.get(info, :params, %{})

    socket = %Socket{
      endpoint: Map.fetch!(info, :endpoint),
      params: params,
      session: session,
      connect_info: connect_info,
      id: generate_id(),
      connected_at: DateTime.utc_now(),
      private: %{
        config: config,
        connected_monotonic: started,
        handler: handler,
        session_configured?: session_configured?(options)
      }
    }

    metadata = socket_metadata(socket)

    result =
      if config.require_session and socket.private.session_configured? and is_nil(session) do
        Logger.error(
          "PhoenixHtmxWs: the endpoint configures a session for this socket, but the " <>
            "session could not be read. The client did not send a valid \"_csrf_token\" " <>
            "parameter. Build the connect URL with PhoenixHtmxWs.connect_path/1."
        )

        :error
      else
        handler.connect(params, session, socket)
      end

    :telemetry.execute(
      [:phoenix_htmx_ws, :socket, :connect],
      %{system_time: System.system_time()},
      metadata
    )

    case result do
      {:ok, %Socket{} = socket} -> {:ok, %State{handler: handler, socket: clear_meta(socket)}}
      :error -> :error
      {:error, _reason} = error -> error
      other -> invalid_return!(handler, :connect, other)
    end
  end

  @spec init(State.t()) :: {:ok, State.t()} | {:stop, term(), State.t()}
  def init(%State{handler: handler, socket: socket} = state) do
    Registry.register(
      PhoenixHtmxWs.ConnectionRegistry,
      {socket.endpoint, handler},
      socket.id
    )

    case handler.mount(socket.params, socket) do
      {:ok, %Socket{} = socket} ->
        {:ok, %{state | socket: clear_meta(socket)}}

      {:stop, reason, %Socket{} = socket} ->
        {:stop, reason, %{state | socket: clear_meta(socket)}}

      other ->
        invalid_return!(handler, :mount, other)
    end
  end

  @spec handle_in({term(), keyword()}, State.t()) :: term()
  def handle_in({payload, opts}, %State{} = state) do
    case Keyword.get(opts, :opcode, :text) do
      :text -> decode_and_dispatch(payload, state)
      :binary -> dispatch_error(:unsupported_frame, payload, payload_size(payload), state)
      _ -> dispatch_error(:unsupported_frame, payload, payload_size(payload), state)
    end
  end

  @spec handle_info(term(), State.t()) :: term()
  def handle_info(:phoenix_htmx_ws_drain, %State{} = state) do
    {:stop, {:shutdown, :restart}, state}
  end

  def handle_info(message, %State{handler: handler, socket: socket} = state) do
    event = "handle_info"

    result =
      span_dispatch(event_metadata(socket, event, 0), fn ->
        handler.handle_info(message, socket)
        |> prepare_info_result(handler, event)
      end)

    finalize_info_result(result, state, event)
  end

  @spec terminate(term(), State.t()) :: :ok
  def terminate(reason, %State{handler: handler, socket: socket}) do
    duration = System.monotonic_time() - socket.private.connected_monotonic

    :telemetry.execute(
      [:phoenix_htmx_ws, :socket, :disconnect],
      %{duration: duration},
      socket_metadata(socket)
    )

    handler.terminate(reason, socket)
  end

  defp decode_and_dispatch(payload, state) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} when is_map(decoded) -> dispatch_event(decoded, byte_size(payload), state)
      {:ok, decoded} -> dispatch_error(:invalid_payload, decoded, byte_size(payload), state)
      {:error, _error} -> dispatch_error(:invalid_json, payload, byte_size(payload), state)
    end
  end

  defp decode_and_dispatch(payload, state),
    do: dispatch_error(:invalid_json, payload, payload_size(payload), state)

  defp dispatch_event(payload, payload_size, %State{handler: handler, socket: socket} = state) do
    config = socket.private.config
    {headers, payload} = Map.pop(payload, "headers", %{})
    {given_event, params} = Map.pop(payload, config.event_key, :phoenix_htmx_ws_missing)

    event =
      cond do
        is_binary(given_event) ->
          given_event

        given_event == :phoenix_htmx_ws_missing ->
          config.default_event

        true ->
          Logger.debug(fn ->
            "PhoenixHtmxWs: event key #{inspect(config.event_key)} must contain a string; " <>
              "using #{inspect(config.default_event)}"
          end)

          config.default_event
      end

    dispatch_socket = %{socket | meta: %{headers: headers}}

    metadata =
      dispatch_socket
      |> event_metadata(event, payload_size)
      |> maybe_put_params(config.telemetry_params, params)

    result =
      span_dispatch(metadata, fn ->
        handler.handle_event(event, params, dispatch_socket)
        |> prepare_event_result(handler, :handle_event, event)
      end)

    finalize_event_result(result, state, event)
  end

  defp dispatch_error(
         reason,
         payload,
         payload_size,
         %State{handler: handler, socket: socket} = state
       ) do
    event = Atom.to_string(reason)

    result =
      span_dispatch(event_metadata(socket, event, payload_size), fn ->
        handler.handle_error(reason, payload, socket)
        |> prepare_event_result(handler, :handle_error, event)
      end)

    finalize_event_result(result, state, event)
  end

  defp prepare_event_result({:noreply, %Socket{} = socket}, _handler, _callback, _event),
    do: {:noreply, socket}

  defp prepare_event_result({:reply, body, %Socket{} = socket}, handler, _callback, event) do
    {:reply, encode_body!(body, [], handler, event), socket}
  end

  defp prepare_event_result(
         {:reply, body, opts, %Socket{} = socket},
         handler,
         _callback,
         event
       ) do
    {:reply, encode_body!(body, opts, handler, event), socket}
  end

  defp prepare_event_result(
         {:stop, reason, %Socket{} = socket},
         _handler,
         _callback,
         _event
       ),
       do: {:stop, reason, socket}

  defp prepare_event_result(other, handler, callback, _event),
    do: invalid_return!(handler, callback, other)

  defp finalize_event_result({:noreply, socket}, state, _event),
    do: {:ok, put_socket(state, socket)}

  defp finalize_event_result({:reply, frame, socket}, state, event) do
    emit_push(socket, event, frame)
    {:reply, :ok, {:text, frame}, put_socket(state, socket)}
  end

  defp finalize_event_result({:stop, reason, socket}, state, _event),
    do: {:stop, reason, put_socket(state, socket)}

  defp prepare_info_result({:noreply, %Socket{} = socket}, _handler, _event),
    do: {:noreply, socket}

  defp prepare_info_result({:push, body, %Socket{} = socket}, handler, event) do
    {:push, encode_body!(body, [], handler, event), socket}
  end

  defp prepare_info_result({:push, body, opts, %Socket{} = socket}, handler, event) do
    {:push, encode_body!(body, opts, handler, event), socket}
  end

  defp prepare_info_result({:stop, reason, %Socket{} = socket}, _handler, _event),
    do: {:stop, reason, socket}

  defp prepare_info_result(other, handler, _event),
    do: invalid_return!(handler, :handle_info, other)

  defp finalize_info_result({:noreply, socket}, state, _event),
    do: {:ok, put_socket(state, socket)}

  defp finalize_info_result({:push, frame, socket}, state, event) do
    emit_push(socket, event, frame)
    {:push, {:text, frame}, put_socket(state, socket)}
  end

  defp finalize_info_result({:stop, reason, socket}, state, _event),
    do: {:stop, reason, put_socket(state, socket)}

  defp encode_body!(body, opts, handler, event) when is_list(opts) do
    validate_options!(opts)
    html = to_iodata!(body, handler, event)

    if opts == [] do
      html
    else
      envelope =
        Enum.reduce(opts, %{"content" => IO.iodata_to_binary(html)}, fn {key, value}, acc ->
          Map.put(acc, Atom.to_string(key), value)
        end)

      Jason.encode_to_iodata!(envelope)
    end
  end

  defp encode_body!(_body, opts, _handler, _event) do
    raise ArgumentError,
          "PhoenixHtmxWs response options must be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_options!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError,
            "PhoenixHtmxWs response options must be a keyword list, got: #{inspect(opts)}"
    end

    Enum.each(opts, fn {key, value} ->
      unless key in @valid_options do
        raise ArgumentError,
              "unknown PhoenixHtmxWs response option #{inspect(key)}; expected one of #{inspect(@valid_options)}"
      end

      unless is_binary(value) do
        raise ArgumentError,
              "PhoenixHtmxWs response option #{inspect(key)} must be a string, got: #{inspect(value)}"
      end
    end)
  end

  defp to_iodata!(body, _handler, _event) when is_binary(body), do: body
  defp to_iodata!({:safe, iodata}, handler, event), do: validate_iodata!(iodata, handler, event)

  defp to_iodata!(body, handler, event) when is_list(body) do
    validate_iodata!(body, handler, event)
  end

  defp to_iodata!(body, handler, event) do
    case Phoenix.HTML.Safe.impl_for(body) do
      nil ->
        unsupported_body!(body, handler, event)

      _impl ->
        Phoenix.HTML.Safe.to_iodata(body)
    end
  rescue
    Protocol.UndefinedError -> unsupported_body!(body, handler, event)
    ArgumentError -> unsupported_body!(body, handler, event)
  end

  defp validate_iodata!(iodata, handler, event) do
    _ = :erlang.iolist_size(iodata)
    iodata
  rescue
    ArgumentError -> unsupported_body!(iodata, handler, event)
  end

  defp unsupported_body!(body, handler, event) do
    type = if is_struct(body), do: body.__struct__, else: type_name(body)

    raise ArgumentError,
          "#{inspect(handler)} returned an unsupported response body for event " <>
            "#{inspect(event)}: #{inspect(type)}"
  end

  defp type_name(term) when is_atom(term), do: :atom
  defp type_name(term) when is_integer(term), do: :integer
  defp type_name(term) when is_float(term), do: :float
  defp type_name(term) when is_tuple(term), do: :tuple
  defp type_name(term) when is_map(term), do: :map
  defp type_name(term) when is_pid(term), do: :pid
  defp type_name(_term), do: :term

  defp emit_push(socket, event, frame) do
    :telemetry.execute(
      [:phoenix_htmx_ws, :push],
      %{response_size: :erlang.iolist_size(frame)},
      event_metadata(socket, event, 0)
    )
  end

  defp span_dispatch(metadata, fun) do
    :telemetry.span([:phoenix_htmx_ws, :event], metadata, fn ->
      result = fun.()
      {result, Map.merge(metadata, prepared_response_metadata(result))}
    end)
  end

  defp prepared_response_metadata(result) do
    case result do
      {:reply, frame, %Socket{}} -> %{response_size: :erlang.iolist_size(frame)}
      {:push, frame, %Socket{}} -> %{response_size: :erlang.iolist_size(frame)}
      _ -> %{response_size: 0}
    end
  end

  defp socket_metadata(socket) do
    %{socket: socket.private.handler, socket_id: socket.id}
  end

  defp event_metadata(socket, event, payload_size) do
    socket_metadata(socket)
    |> Map.put(:event, event)
    |> Map.put(:payload_size, payload_size)
  end

  defp maybe_put_params(metadata, true, params), do: Map.put(metadata, :params, params)
  defp maybe_put_params(metadata, false, _params), do: metadata

  defp payload_size(payload) when is_binary(payload), do: byte_size(payload)
  defp payload_size(_payload), do: 0

  defp put_socket(state, socket), do: %{state | socket: clear_meta(socket)}
  defp clear_meta(socket), do: %{socket | meta: %{}}

  defp session_configured?(options) do
    options
    |> Keyword.get(:connect_info, [])
    |> Enum.any?(fn
      {:session, _config} -> true
      _ -> false
    end)
  end

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end

  defp invalid_return!(handler, callback, value) do
    raise ArgumentError,
          "invalid return from #{inspect(handler)}.#{callback}: #{inspect(value)}"
  end
end
