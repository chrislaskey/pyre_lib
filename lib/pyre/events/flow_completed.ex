defmodule Pyre.Events.FlowCompleted do
  @moduledoc """
  Emitted when a flow completes successfully.
  """

  @enforce_keys [:flow_module, :description, :run_dir, :result, :elapsed_ms]
  defstruct [:flow_module, :description, :run_dir, :result, :elapsed_ms]

  @type t :: %__MODULE__{
          flow_module: module(),
          description: String.t(),
          run_dir: String.t(),
          result: map(),
          elapsed_ms: integer()
        }
end
