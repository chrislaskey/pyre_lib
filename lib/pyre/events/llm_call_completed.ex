defmodule Pyre.Events.LLMCallCompleted do
  @moduledoc """
  Emitted when an LLM call completes successfully.
  """

  @enforce_keys [:backend, :model, :call_type, :elapsed_ms]
  defstruct [:backend, :model, :call_type, :elapsed_ms]

  @type t :: %__MODULE__{
          backend: module(),
          model: String.t(),
          call_type: :generate | :stream | :chat | :agentic_loop,
          elapsed_ms: integer()
        }
end
