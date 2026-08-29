defmodule PhoenixHtmxWs do
  @moduledoc """
  Helpers for connecting htmx 4's `hx-ws` extension to a Phoenix socket.
  """

  @doc "Builds a connection path containing the session CSRF token."
  @spec connect_path(binary()) :: binary()
  def connect_path(path), do: connect_path(path, %{})

  @doc "Builds a connection path containing the session CSRF token and query parameters."
  @spec connect_path(binary(), map() | keyword()) :: binary()
  def connect_path(path, params) when is_binary(path) and (is_map(params) or is_list(params)) do
    params =
      params
      |> Enum.into(%{})
      |> Map.put("_csrf_token", Plug.CSRFProtection.get_csrf_token())

    separator = if String.contains?(path, "?"), do: "&", else: "?"
    path <> separator <> URI.encode_query(params)
  end
end
