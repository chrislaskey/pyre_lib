defmodule Pyre.Events.ActionCompleted do
  @moduledoc """
  Emitted when an action completes successfully within a flow stage.
  """

  @enforce_keys [:action_module, :stage_name, :result, :model, :elapsed_ms]
  defstruct [:action_module, :stage_name, :result, :model, :elapsed_ms]

  @type t :: %__MODULE__{
          action_module: module(),
          stage_name: atom(),
          result: map(),
          model: String.t(),
          elapsed_ms: integer()
        }
end
