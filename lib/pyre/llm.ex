defmodule Pyre.LLM do
  @moduledoc """
  LLM behaviour for Pyre.

  ## Built-in implementations

  - `Pyre.LLM.ReqLLM` — API-based (default), uses ReqLLM/jido_ai
  - `Pyre.LLM.ClaudeCLI` — Claude CLI subprocess backend
  - `Pyre.LLM.CursorCLI` — Cursor CLI subprocess backend
  - `Pyre.LLM.CodexCLI` — OpenAI Codex CLI subprocess backend
  - `Pyre.LLM.Mock` — test mock

  ## Custom backends

  Use `use Pyre.LLM` to define a custom backend:

      defmodule MyApp.LLM.Ollama do
        use Pyre.LLM

        @impl true
        def generate(model, messages, opts), do: ...
        @impl true
        def stream(model, messages, opts), do: ...
        @impl true
        def chat(model, messages, tools, opts), do: ...
      end

  Then register it in your `Pyre.Config` module. See `Pyre.Config` for details.

  ## Backend selection

  The default backend is determined by `Pyre.Config.get_llm_backend/1`.
  The `:llm` key in action context can override it per-call.
  """

  @type message :: %{role: :system | :user | :assistant, content: String.t() | [map()]}
  @type model :: String.t()

  @doc """
  Generates text from the LLM without streaming.
  """
  @callback generate(model(), [message()], keyword()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Generates text from the LLM with token-by-token streaming.

  Calls `output_fn` (default `&IO.write/1`) with each token as it arrives.
  Returns the complete response text.
  """
  @callback stream(model(), [message()], keyword()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Calls the LLM with tool support, returning the full response.

  Used by the agentic loop for multi-turn tool-use conversations.
  ReqLLM-backed implementations return `ReqLLM.Response.t()`.
  CLI backends return plain `String.t()` (they manage their own tool loop).
  """
  @callback chat(model(), [message()] | ReqLLM.Context.t(), [ReqLLM.Tool.t()], keyword()) ::
              {:ok, ReqLLM.Response.t() | String.t()} | {:error, term()}

  @doc """
  Returns true if this backend manages its own tool-use loop internally.

  When true, `Pyre.Actions.Helpers.call_llm/4` calls `chat/4` directly
  instead of routing through `Pyre.Tools.AgenticLoop`.

  The `use Pyre.LLM` macro provides a default implementation returning `false`.
  Override to return `true` for CLI-style backends that manage their own loop.
  """
  @callback manages_tool_loop?() :: boolean()

  @optional_callbacks [manages_tool_loop?: 0]

  @doc """
  Defines a custom LLM backend.

  Provides `@behaviour Pyre.LLM` and a default `manages_tool_loop?/0`
  returning `false`. Override it to `true` for backends that manage their
  own tool-calling loop.

      defmodule MyApp.LLM.Ollama do
        use Pyre.LLM

        @impl true
        def generate(model, messages, opts), do: ...
        @impl true
        def stream(model, messages, opts), do: ...
        @impl true
        def chat(model, messages, tools, opts), do: ...
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Pyre.LLM

      @impl Pyre.LLM
      def manages_tool_loop?, do: false
      defoverridable manages_tool_loop?: 0
    end
  end

  @doc """
  Returns the default LLM module.

  Delegates to `Pyre.Config.get_llm_backend/1`.
  """
  def default do
    Pyre.Config.get_llm_backend(nil)
  end

  @doc """
  Validates that the configured default backend implements required callbacks.

  Called automatically at application startup by `Pyre.Application`.
  Raises `ArgumentError` with a clear message if the backend is missing
  required callbacks.
  """
  def validate_backend! do
    mod = default()
    Code.ensure_loaded!(mod)
    required = [{:generate, 3}, {:stream, 3}, {:chat, 4}]

    missing =
      Enum.reject(required, fn {fun, arity} ->
        function_exported?(mod, fun, arity)
      end)

    case missing do
      [] ->
        :ok

      fns ->
        names = Enum.map_join(fns, ", ", fn {f, a} -> "#{f}/#{a}" end)

        raise ArgumentError,
              "Configured LLM backend #{inspect(mod)} is missing: #{names}. " <>
                "Use `use Pyre.LLM` and implement the required callbacks."
    end
  end
end
