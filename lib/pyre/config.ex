defmodule Pyre.Config do
  @moduledoc """
  Behaviour and default configuration for Pyre.

  Applications can provide a custom config module by:

  1. Creating a module that `use Pyre.Config`
  2. Overriding any callbacks they need
  3. Configuring it in `config.exs`:

         config :pyre, config: MyApp.PyreConfig

  If no config module is set, `Pyre.Config` itself provides the default
  implementations for all callbacks.

  ## Example

      defmodule MyApp.PyreConfig do
        use Pyre.Config

        @impl true
        def after_flow_start(%Pyre.Events.FlowStarted{flow_module: mod}) do
          IO.puts("Flow started: \#{inspect(mod)}")
          :ok
        end

        @impl true
        def list_llm_backends do
          Pyre.Config.included_llm_backends() ++ [
            %{module: MyApp.LLM.Ollama, name: "ollama",
              label: "Ollama", description: "Local models via Ollama"}
          ]
        end
      end

  Any callback not overridden in the custom module will fall back to the
  default implementation provided by `Pyre.Config`.

  ## Dispatching

  Use `Pyre.Config.notify/2` to dispatch events. Exceptions raised inside
  user-provided callbacks are rescued and logged — they never crash the
  calling flow.
  """

  require Logger

  # -- Types --

  @type llm_backend_entry :: %{
          module: module(),
          name: String.t(),
          label: String.t(),
          description: String.t()
        }

  @type workflow_entry :: %{
          name: atom(),
          module: module(),
          label: String.t(),
          description: String.t(),
          mode: :interactive | :background,
          stages: [{atom(), String.t()}]
        }

  # -- Callbacks --

  @callback after_flow_start(event :: Pyre.Events.FlowStarted.t()) :: :ok | {:error, term()}
  @callback after_flow_complete(event :: Pyre.Events.FlowCompleted.t()) :: :ok | {:error, term()}
  @callback after_flow_error(event :: Pyre.Events.FlowError.t()) :: :ok | {:error, term()}
  @callback after_action_start(event :: Pyre.Events.ActionStarted.t()) :: :ok | {:error, term()}
  @callback after_action_complete(event :: Pyre.Events.ActionCompleted.t()) ::
              :ok | {:error, term()}
  @callback after_action_error(event :: Pyre.Events.ActionError.t()) :: :ok | {:error, term()}
  @callback after_llm_call_complete(event :: Pyre.Events.LLMCallCompleted.t()) ::
              :ok | {:error, term()}
  @callback after_llm_call_error(event :: Pyre.Events.LLMCallError.t()) :: :ok | {:error, term()}

  @doc """
  Returns the list of available LLM backends.

  Each entry is a map with `:module`, `:name`, `:label`, and `:description`.
  The default implementation delegates to `included_llm_backends/0`.
  """
  @callback list_llm_backends() :: [llm_backend_entry()]

  @doc """
  Returns the LLM backend module for the given argument.

  The meaning of `arg` is defined by the implementing Config module.
  The default implementation ignores `arg` and selects based on the
  `PYRE_LLM_BACKEND` environment variable, falling back to the first
  entry from `list_llm_backends/0`.
  """
  @callback get_llm_backend(arg :: any()) :: module()

  @doc """
  Returns the list of available workflows.

  Each entry is a map with `:name`, `:module`, `:label`, `:description`,
  `:mode`, and `:stages`. The default implementation delegates to
  `included_workflows/0`.
  """
  @callback list_workflows() :: [workflow_entry()]

  # -- Public API --

  @doc """
  Returns the configured Pyre config module.

  Reads `config :pyre, config: MyApp.PyreConfig` from the application environment.
  Falls back to `Pyre.Config` (default implementations) if none is configured.
  """
  def get_module do
    Application.get_env(:pyre, :config) || __MODULE__
  end

  @doc """
  Dispatches a lifecycle event to the configured config module.

  Rescues any exception raised inside the user's callback implementation
  and logs a warning — callbacks never crash the calling flow.
  """
  @spec notify(atom(), struct()) :: :ok
  def notify(hook, event) do
    mod = get_module()

    try do
      apply(mod, hook, [event])
    rescue
      e ->
        Logger.warning("Pyre.Config hook #{hook} raised: #{Exception.message(e)}")
    end

    :ok
  end

  @doc """
  Returns all available LLM backends from the configured config module.
  """
  @spec list_llm_backends() :: [llm_backend_entry()]
  def list_llm_backends do
    mod = get_module()

    if mod == __MODULE__ do
      included_llm_backends()
    else
      mod.list_llm_backends()
    end
  end

  @doc """
  Returns the LLM backend module for the given argument.

  The meaning of `arg` is defined by the Config module implementation.
  The default implementation handles two cases:

  - `nil` — selects based on the `PYRE_LLM_BACKEND` environment variable,
    falling back to the first entry from `list_llm_backends/0`
  - a binary name (e.g. `"claude_cli"`) — looks up by `name` in
    `list_llm_backends/0` and returns the module, falling back to the
    default when no match is found

  ## Examples

      Pyre.Config.get_llm_backend()            # env var or first backend
      Pyre.Config.get_llm_backend("claude_cli") # => Pyre.LLM.ClaudeCLI
      Pyre.Config.get_llm_backend("unknown")    # falls back to default
  """
  @spec get_llm_backend(any()) :: module()
  def get_llm_backend(arg \\ nil) do
    mod = get_module()

    if mod == __MODULE__ do
      default_get_llm_backend(arg)
    else
      mod.get_llm_backend(arg)
    end
  end

  @doc """
  Returns all available workflows from the configured config module.
  """
  @spec list_workflows() :: [workflow_entry()]
  def list_workflows do
    mod = get_module()

    if mod == __MODULE__ do
      included_workflows()
    else
      mod.list_workflows()
    end
  end

  @doc """
  Returns the workflow entry for the given name atom.

  Returns `{:ok, entry}` if found, `:error` otherwise.

      iex> {:ok, entry} = Pyre.Config.get_workflow(:chat)
      iex> entry.module
      Pyre.Flows.Chat
  """
  @spec get_workflow(atom()) :: {:ok, workflow_entry()} | :error
  def get_workflow(name) when is_atom(name) do
    case Enum.find(list_workflows(), fn w -> w.name == name end) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  # -- Helpers (public, for use in custom Config implementations) --

  @doc """
  Returns the list of LLM backends included with Pyre.

  This is the canonical source for the built-in backend list. The default
  implementations of `list_llm_backends/0` delegate to this function.

  Custom Config modules can reference it to extend rather than replace
  the built-in list:

      @impl true
      def list_llm_backends do
        Pyre.Config.included_llm_backends() ++ [
          %{module: MyApp.LLM.Ollama, name: "ollama",
            label: "Ollama", description: "Local models"}
        ]
      end
  """
  @spec included_llm_backends() :: [llm_backend_entry()]
  def included_llm_backends do
    [
      %{
        module: Pyre.LLM.ReqLLM,
        name: "req_llm",
        label: "API (ReqLLM)",
        description: "Any major provider"
      },
      %{
        module: Pyre.LLM.ClaudeCLI,
        name: "claude_cli",
        label: "Claude CLI",
        description: "From Anthropic"
      },
      %{
        module: Pyre.LLM.CursorCLI,
        name: "cursor_cli",
        label: "Cursor CLI",
        description: "From Cursor"
      },
      %{
        module: Pyre.LLM.CodexCLI,
        name: "codex_cli",
        label: "Codex CLI",
        description: "From OpenAI"
      }
    ]
  end

  @doc """
  Returns the list of workflows included with Pyre.

  This is the canonical source for the built-in workflow list. The default
  implementations of `list_workflows/0` delegate to this function.

  Custom Config modules can reference it to extend rather than replace
  the built-in list:

      @impl true
      def list_workflows do
        Pyre.Config.included_workflows() ++ [
          %{name: :my_flow, module: MyApp.Flows.Custom, label: "Custom",
            description: "My custom flow", mode: :background,
            stages: [{:doing, "Worker"}]}
        ]
      end
  """
  @spec included_workflows() :: [workflow_entry()]
  def included_workflows do
    [
      %{
        name: :chat,
        module: Pyre.Flows.Chat,
        label: "Chat",
        description: "Build anything interactively",
        mode: :interactive,
        stages: [{:generalist, "Generalist"}]
      },
      %{
        name: :prototype,
        module: Pyre.Flows.Prototype,
        label: "Prototype",
        description: "Visual prototype",
        mode: :interactive,
        stages: [{:prototyping, "Prototype Engineer"}]
      },
      %{
        name: :feature,
        module: Pyre.Flows.Feature,
        label: "Feature",
        description: "Architect, PR, and engineer",
        mode: :interactive,
        stages: [
          {:architecting, "Software Architect"},
          {:pr_setup, "PR Setup"},
          {:engineering, "Software Engineer"}
        ]
      },
      %{
        name: :overnight_feature,
        module: Pyre.Flows.OvernightFeature,
        label: "Overnight Feature",
        description: "Full pipeline, plan to ship",
        mode: :background,
        stages: [
          {:planning, "Product Manager"},
          {:designing, "Designer"},
          {:implementing, "Programmer"},
          {:testing, "Test Writer"},
          {:reviewing, "QA Reviewer"},
          {:shipping, "Shipper"}
        ]
      },
      %{
        name: :task,
        module: Pyre.Flows.Task,
        label: "Task",
        description: "Single-step generalist task",
        mode: :background,
        stages: [{:tasking, "Generalist"}]
      },
      %{
        name: :code_review,
        module: Pyre.Flows.CodeReview,
        label: "Code Review",
        description: "Review existing code",
        mode: :background,
        stages: [{:reviewing, "PR Reviewer"}]
      }
    ]
  end

  @doc """
  Finds the backend entry with the given `name` in a list of backends.

  Returns `{:ok, entry}` if found, `:error` otherwise.

      iex> backends = Pyre.Config.included_llm_backends()
      iex> {:ok, entry} = Pyre.Config.find_backend_by_name(backends, "claude_cli")
      iex> entry.module
      Pyre.LLM.ClaudeCLI
  """
  @spec find_backend_by_name([llm_backend_entry()], String.t()) ::
          {:ok, llm_backend_entry()} | :error
  def find_backend_by_name(backends, name) when is_binary(name) do
    case Enum.find(backends, fn b -> b.name == name end) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @doc """
  Returns the backend name for the given module, or `"other"` if not found.

  Looks up the module in the current `list_llm_backends/0` and returns its
  `name` field. Useful for converting a module reference back to a backend
  identifier string.

      Pyre.Config.backend_name_for_module(Pyre.LLM.ClaudeCLI)
      # => "claude_cli"
  """
  @spec backend_name_for_module(module()) :: String.t()
  def backend_name_for_module(mod) do
    backends = list_llm_backends()

    case Enum.find(backends, fn b -> b.module == mod end) do
      %{name: name} -> name
      nil -> "other"
    end
  end

  @doc """
  Resolves the default backend module from a list of backend entries.

  Checks the `PYRE_LLM_BACKEND` environment variable and matches it
  against the `name` field. Falls back to the first entry in the list.

  Custom Config modules can reuse this in their `get_llm_backend/1`:

      @impl true
      def get_llm_backend(_arg) do
        Pyre.Config.resolve_llm_backend(list_llm_backends())
      end
  """
  @spec resolve_llm_backend([llm_backend_entry()]) :: module()
  def resolve_llm_backend(backends) do
    case System.get_env("PYRE_LLM_BACKEND") do
      nil ->
        first_backend_module(backends)

      env_value ->
        case Enum.find(backends, fn b -> b.name == env_value end) do
          %{module: mod} -> mod
          nil -> first_backend_module(backends)
        end
    end
  end

  defp default_get_llm_backend(nil) do
    resolve_llm_backend(included_llm_backends())
  end

  defp default_get_llm_backend(name) when is_binary(name) do
    backends = included_llm_backends()

    case find_backend_by_name(backends, name) do
      {:ok, %{module: mod}} -> mod
      :error -> resolve_llm_backend(backends)
    end
  end

  defp default_get_llm_backend(_other) do
    resolve_llm_backend(included_llm_backends())
  end

  defp first_backend_module(backends) do
    case backends do
      [%{module: mod} | _] -> mod
      _ -> Pyre.LLM.ReqLLM
    end
  end

  # -- __using__ macro --

  defmacro __using__(_opts) do
    quote do
      @behaviour Pyre.Config

      @impl Pyre.Config
      def after_flow_start(_event), do: :ok
      @impl Pyre.Config
      def after_flow_complete(_event), do: :ok
      @impl Pyre.Config
      def after_flow_error(_event), do: :ok
      @impl Pyre.Config
      def after_action_start(_event), do: :ok
      @impl Pyre.Config
      def after_action_complete(_event), do: :ok
      @impl Pyre.Config
      def after_action_error(_event), do: :ok
      @impl Pyre.Config
      def after_llm_call_complete(_event), do: :ok
      @impl Pyre.Config
      def after_llm_call_error(_event), do: :ok

      @impl Pyre.Config
      def list_llm_backends, do: Pyre.Config.included_llm_backends()

      @impl Pyre.Config
      def list_workflows, do: Pyre.Config.included_workflows()

      @impl Pyre.Config
      def get_llm_backend(nil) do
        Pyre.Config.resolve_llm_backend(list_llm_backends())
      end

      def get_llm_backend(name) when is_binary(name) do
        case Pyre.Config.find_backend_by_name(list_llm_backends(), name) do
          {:ok, %{module: mod}} -> mod
          :error -> Pyre.Config.resolve_llm_backend(list_llm_backends())
        end
      end

      def get_llm_backend(_arg) do
        Pyre.Config.resolve_llm_backend(list_llm_backends())
      end

      defoverridable after_flow_start: 1,
                     after_flow_complete: 1,
                     after_flow_error: 1,
                     after_action_start: 1,
                     after_action_complete: 1,
                     after_action_error: 1,
                     after_llm_call_complete: 1,
                     after_llm_call_error: 1,
                     list_llm_backends: 0,
                     get_llm_backend: 1,
                     list_workflows: 0
    end
  end

  # -- Default implementations (used when no custom config module is configured) --

  def after_flow_start(_event), do: :ok
  def after_flow_complete(_event), do: :ok
  def after_flow_error(_event), do: :ok
  def after_action_start(_event), do: :ok
  def after_action_complete(_event), do: :ok
  def after_action_error(_event), do: :ok
  def after_llm_call_complete(_event), do: :ok
  def after_llm_call_error(_event), do: :ok
end
