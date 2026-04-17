defmodule Pyre.Events.ActionStarted do
  @moduledoc """
  Emitted when an action begins execution within a flow stage.
  """

  @enforce_keys [:action_module, :stage_name, :model, :params]
  defstruct [:action_module, :stage_name, :model, :params]

  @type t :: %__MODULE__{
          action_module: module(),
          stage_name: atom(),
          model: String.t(),
          params: map()
        }
end
