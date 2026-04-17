defmodule Pyre.Events.LLMCallError do
  @moduledoc """
  Emitted when an LLM call fails with an error.
  """

  @enforce_keys [:backend, :model, :error, :call_type, :elapsed_ms]
  defstruct [:backend, :model, :error, :call_type, :elapsed_ms]

  @type t :: %__MODULE__{
          backend: module(),
          model: String.t(),
          error: term(),
          call_type: :generate | :stream | :chat | :agentic_loop,
          elapsed_ms: integer()
        }
end
