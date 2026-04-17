defmodule Pyre.Events.FlowStarted do
  @moduledoc """
  Emitted when a flow begins execution, after setup completes.
  """

  @enforce_keys [:flow_module, :description, :run_dir, :working_dir]
  defstruct [:flow_module, :description, :run_dir, :working_dir]

  @type t :: %__MODULE__{
          flow_module: module(),
          description: String.t(),
          run_dir: String.t(),
          working_dir: String.t()
        }
end
