defmodule Pyre.Events.FlowError do
  @moduledoc """
  Emitted when a flow fails with an error.
  """

  @enforce_keys [:flow_module, :description, :run_dir, :error, :elapsed_ms]
  defstruct [:flow_module, :description, :run_dir, :error, :elapsed_ms]

  @type t :: %__MODULE__{
          flow_module: module(),
          description: String.t(),
          run_dir: String.t(),
          error: term(),
          elapsed_ms: integer()
        }
end
