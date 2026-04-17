defmodule Pyre.Events.ActionError do
  @moduledoc """
  Emitted when an action fails within a flow stage.
  """

  @enforce_keys [:action_module, :stage_name, :error, :model, :elapsed_ms]
  defstruct [:action_module, :stage_name, :error, :model, :elapsed_ms]

  @type t :: %__MODULE__{
          action_module: module(),
          stage_name: atom(),
          error: term(),
          model: String.t(),
          elapsed_ms: integer()
        }
end
