defmodule PhoenixHtmxWs.Transport.State do
  @moduledoc false
  @enforce_keys [:handler, :socket]
  defstruct [:handler, :socket]

  @type t :: %__MODULE__{handler: module(), socket: PhoenixHtmxWs.Socket.t()}
end
