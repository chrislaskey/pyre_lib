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
        def authorize_socket_connect(params, _connect_info) do
          case Map.get(params, "token") do
            nil -> {:error, :missing_token}
            _token -> :ok
          end
        end
      end

  Any callback not overridden in the custom module will fall back to the
  default implementation provided by `Pyre.Config`.

  ## Dispatching

  Use `Pyre.Config.notify/2` to dispatch lifecycle events.
  Use `Pyre.Config.authorize/2` to dispatch authorization checks.
  Use `Pyre.Config.call/2` to dispatch data-returning callbacks.
  Exceptions raised inside user-provided callbacks are rescued and logged —
  they never crash the calling flow.
  """

  import Phoenix.Component, only: [sigil_H: 2]

  require Logger

  # -- Types --

  @type workflow_entry :: %{
          name: atom(),
          module: module(),
          label: String.t(),
          description: String.t(),
          mode: :interactive | :background,
          stages: [{atom(), String.t()}]
        }

  # -- Lifecycle Callbacks --

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
  Returns the maximum number of concurrent workflows this instance supports.

  Used by the queue manager and UI to determine overall system capacity.
  The default implementation returns `1`.

  Override in consuming apps to set a higher limit or compute it dynamically
  based on available resources.
  """
  @callback max_capacity() :: non_neg_integer()

  @doc """
  Returns the list of available workflows.

  Each entry is a map with `:name`, `:module`, `:label`, `:description`,
  `:mode`, and `:stages`. The default implementation delegates to
  `included_workflows/0`.
  """
  @callback list_workflows() :: [workflow_entry()]

  # -- Authorization Callbacks --

  @callback authorize_socket_connect(params :: map(), connect_info :: map()) ::
              :ok | {:error, term()}

  @callback authorize_channel_join(topic :: String.t(), params :: map(), socket :: Phoenix.Socket.t()) ::
              :ok | {:error, term()}

  @callback authorize_run_create(run_params :: map(), socket :: Phoenix.LiveView.Socket.t()) ::
              :ok | {:error, term()}

  @callback authorize_run_control(action :: map(), socket :: Phoenix.LiveView.Socket.t()) ::
              :ok | {:error, term()}

  @callback authorize_remote_action(action :: map(), socket :: Phoenix.LiveView.Socket.t()) ::
              :ok | {:error, term()}

  @callback authorize_webhook(event :: String.t(), payload :: map()) ::
              :ok | {:error, term()}

  # -- WebSocket Service Token Callbacks --

  @doc """
  Returns the list of valid WebSocket service tokens.

  Default reads `config :pyre, :websocket_service_tokens`. Accepts a
  comma-separated string or a list. Returns `[]` if unconfigured,
  which means no tokens are valid and all connections are rejected.

  Override in host apps to load tokens from a database, vault, etc.
  """
  @callback websocket_service_tokens() :: [String.t()]

  @doc """
  Returns whether the given WebSocket service token is valid.

  Default checks membership in `websocket_service_tokens/0` using
  timing-safe comparison via `Plug.Crypto.secure_compare/2`.

  Override in host apps for token scoping, expiry, rate tracking, etc.
  """
  @callback websocket_service_token_valid?(token :: String.t()) :: boolean()

  # -- GitHub App Persistence Callbacks --

  @doc """
  Called after the GitHub App manifest flow to store App credentials.

  The `credentials` map contains:

    * `:app_id` - GitHub App ID (string)
    * `:private_key` - PEM-encoded RSA private key
    * `:webhook_secret` - Webhook HMAC secret
    * `:client_id` - OAuth client ID
    * `:client_secret` - OAuth client secret
    * `:bot_slug` - App slug (used for @mention detection)
    * `:html_url` - URL of the App on GitHub

  Default implementation: no-op (returns `:ok`). Override in consuming apps
  to persist credentials to a database.
  """
  @callback update_github_app(credentials :: map()) :: :ok | {:error, term()}

  @doc """
  Returns all configured GitHub Apps.

  Should return a list of maps, each with the same keys as
  `update_github_app/1`.

  Default implementation: reads from `config :pyre, :github_apps`
  and normalizes each entry to a map.

  Override in consuming apps to load from a database.
  """
  @callback list_github_apps() :: [map()]

  # -- Render Callbacks --

  @doc """
  Returns HEEx markup to render additional items in the sidebar.

  The `assigns` map includes `:current_page`, `:prefix`, and `:uri` from the
  sidebar component.

  Default implementation: renders nothing (empty HEEx).

  Override in consuming apps to inject custom content (e.g. user info,
  environment badge, version number).
  """
  @callback additional_nav_links(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Returns HEEx markup to render at the bottom of the sidebar.

  The `assigns` map includes `:current_page`, `:prefix`, and `:uri` from the
  sidebar component.

  Default implementation: renders nothing (empty HEEx).

  Override in consuming apps to inject custom content (e.g. user info,
  environment badge, version number).
  """
  @callback sidebar_footer(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Returns HEEx markup summarizing workflow capacity across all
  workflow types. Intended for dashboard/overview pages.

  The `assigns` map includes:
    - `:capacity_by_type` — result of
      `Pyre.WorkflowAvailability.capacity_by_type/2`
    - `:workflows` — result of `Pyre.Config.list_workflows()`
    - Any other assigns from the calling LiveView
  """
  @callback render_workflow_capacities(assigns :: map()) ::
              Phoenix.LiveView.Rendered.t()

  @doc """
  Returns HEEx markup summarizing capacity for a single workflow
  type. Intended for the run show page.

  The `assigns` map includes:
    - `:capacity_info` — the capacity_info map for this workflow
      type from `Pyre.WorkflowAvailability.capacity_by_type/2`
    - `:workflow_label` — display label (e.g., "Chat", "Feature")
    - Any other assigns from the calling LiveView
  """
  @callback render_workflow_capacity(assigns :: map()) ::
              Phoenix.LiveView.Rendered.t()

  # -- Workflow Callbacks --

  @doc """
  Called when a user submits a new workflow run from the UI.

  Receives the feature description and fully-prepared options keyword list
  containing:

    * `:workflow` - atom (`:chat`, `:feature`, `:prototype`, etc.)
    * `:skipped_stages` - list of atoms
    * `:interactive_stages` - list of atoms
    * `:attachments` - list of `%{filename, content, media_type}` maps
    * `:feature` - optional feature name string or nil

  Returns `{:ok, opts}` where `opts` is a keyword list. Recognized keys:

    * `:redirect_to` - path string relative to the pyre_web mount point
      (e.g., `"/runs/abc123"` or `"/workflows/42"`). When present, the UI
      navigates to that path. When absent, the UI stays on the current
      page and shows a success flash.

  Default implementation: starts the run immediately via
  `Pyre.RunServer.start_run/2` and redirects to the run show page.

  Override in consuming apps to implement a more complex workflow like job
  queuing and delayed execution.
  """
  @callback run_submit(description :: String.t(), opts :: keyword()) ::
              {:ok, keyword()} | {:error, term()}

  # -- Run Callbacks --

  @doc """
  Returns a list of runs for the index page.

  Each entry should be a map with at least these keys:

    * `:id` - the run ID string (used for links)
    * `:status` - atom (e.g., `:queued`, `:running`, `:complete`, `:error`)
    * `:workflow` - atom (e.g., `:chat`, `:feature`, `:prototype`)
    * `:feature` - feature name string or nil
    * `:phase` - current phase atom or nil
    * `:feature_description` - the original description string
    * `:started_at` - `DateTime` or nil

  Default implementation: calls `Pyre.RunServer.list_runs/0`, which only
  returns runs with an active in-memory process.

  Override in consuming apps to return persisted runs from a database,
  merged with live RunServer state when available.
  """
  @callback list_runs() :: [map()]

  @doc """
  Returns the full run state for a given run ID.

  Called by `RunShowLive` on mount as the single source of run data.
  The default implementation fetches state from `Pyre.RunServer.get_state/1`.

  Host apps can override this callback to:

    * Merge in additional data from a database
    * Provide a fallback when the RunServer process is not alive
      (e.g., for queued or completed runs)
    * Add custom keys that `render_run/1` can use

  Should return a map with any of the following keys:

    * `:status` - atom (e.g., `:queued`, `:running`, `:complete`, `:error`)
    * `:phase` - current phase atom
    * `:feature` - feature name string or nil
    * `:feature_description` - the original description string
    * `:workflow` - atom (`:chat`, `:feature`, etc.)
    * `:skipped_stages` - MapSet of skipped stage atoms
    * `:interactive_stages` - MapSet of interactive stage atoms
    * `:waiting_for_input` - boolean
    * `:session_ids` - map of phase to session ID
    * `:log` - list of log entries for streaming output
    * Any other keys the host app wants to make available to `render_run/1`

  Returns `nil` when the run cannot be found (triggers a redirect).

  Default implementation: calls `Pyre.RunServer.get_state/1`.
  """
  @callback get_run(run_id :: String.t()) :: {:ok, any()} | {:error, any()}

  @doc """
  Returns HEEx markup to render host-app-specific content on the run
  show page.

  The `assigns` map includes `:run_id` and all assigns from `RunShowLive`,
  plus `:run` containing the full map returned by `get_run/1`.

  Default implementation: renders nothing (empty HEEx).

  Override in consuming apps to render queue status, worker assignment,
  or other host-app-specific information on the run page.
  """
  @callback render_run(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Called when a user confirms stopping a running workflow.

  Receives the `run_id` string. The default implementation stops the
  in-memory RunServer process via `Pyre.RunServer.stop_run/1`.

  Override in consuming apps to also cancel queued jobs, update
  persistent records, or perform other cleanup.

  Returns `:ok` or `{:error, reason}`.
  """
  @callback run_stop(run_id :: String.t()) :: :ok | {:error, term()}

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
  Dispatches an authorization check to the configured config module.

  Returns `:ok` or `{:error, reason}`. Rescues any exception raised inside
  the user's callback and returns `{:error, :auth_error}` (fail-closed)
  with a logged error.
  """
  @spec authorize(atom(), list()) :: :ok | {:error, term()}
  def authorize(hook, args) do
    mod = get_module()

    try do
      apply(mod, hook, args)
    rescue
      e ->
        Logger.error("Pyre.Config hook #{hook} raised: #{Exception.message(e)}")

        {:error, :auth_error}
    end
  end

  @doc """
  Dispatches a data-returning callback to the configured config module.

  Returns whatever the callback returns. Rescues any exception and returns
  `nil` with a logged warning.
  """
  @spec call(atom(), list()) :: term()
  def call(hook, args) do
    mod = get_module()

    try do
      apply(mod, hook, args)
    rescue
      e ->
        Logger.warning("Pyre.Config hook #{hook} raised: #{Exception.message(e)}")
        nil
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

  @doc false
  def list_github_apps_from_env do
    case Application.get_env(:pyre, :github_apps) do
      nil ->
        []

      apps when is_list(apps) ->
        apps
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn
          entry when is_list(entry) -> Map.new(entry)
          entry when is_map(entry) -> entry
        end)
    end
  end

  # -- __using__ macro --

  defmacro __using__(_opts) do
    quote do
      @behaviour Pyre.Config

      import Phoenix.Component, only: [sigil_H: 2]

      # -- Lifecycle defaults --

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

      # -- Workflow defaults --

      @impl Pyre.Config
      def max_capacity, do: 1

      @impl Pyre.Config
      def list_workflows, do: Pyre.Config.included_workflows()

      # -- Authorization defaults --

      @impl Pyre.Config
      def authorize_socket_connect(_params, _connect_info), do: :ok
      @impl Pyre.Config
      def authorize_channel_join(_topic, _params, _socket), do: :ok
      @impl Pyre.Config
      def authorize_run_create(_run_params, _socket), do: :ok
      @impl Pyre.Config
      def authorize_run_control(_action, _socket), do: :ok
      @impl Pyre.Config
      def authorize_remote_action(_action, _socket), do: :ok
      @impl Pyre.Config
      def authorize_webhook(_event, _payload), do: :ok

      # -- WebSocket Service Token defaults --

      @impl Pyre.Config
      def websocket_service_tokens do
        case Application.get_env(:pyre, :websocket_service_tokens) do
          nil -> []
          tokens when is_list(tokens) -> tokens
          csv when is_binary(csv) ->
            csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
        end
      end

      @impl Pyre.Config
      def websocket_service_token_valid?(token) when is_binary(token) do
        Enum.any?(websocket_service_tokens(), &Plug.Crypto.secure_compare(&1, token))
      end

      def websocket_service_token_valid?(_), do: false

      # -- GitHub App defaults --

      @impl Pyre.Config
      def update_github_app(_credentials), do: :ok
      @impl Pyre.Config
      def list_github_apps, do: Pyre.Config.list_github_apps_from_env()

      # -- Render defaults --

      @impl Pyre.Config
      def additional_nav_links(var!(assigns)), do: ~H""
      @impl Pyre.Config
      def sidebar_footer(var!(assigns)), do: ~H""

      # -- Run defaults --

      @impl Pyre.Config
      def run_submit(description, opts) do
        case apply(Pyre.RunServer, :start_run, [description, opts]) do
          {:ok, run_id} -> {:ok, redirect_to: "/runs/#{run_id}"}
          {:error, _} = error -> error
        end
      end

      @impl Pyre.Config
      def list_runs, do: apply(Pyre.RunServer, :list_runs, [])
      @impl Pyre.Config
      def get_run(run_id), do: apply(Pyre.RunServer, :get_state, [run_id])
      @impl Pyre.Config
      def render_run(var!(assigns)), do: ~H""

      @impl Pyre.Config
      def render_workflow_capacities(var!(assigns)) do
        ~H"""
        <PyreWeb.Components.WorkflowCapacity.capacity_grid
          capacity_by_type={@capacity_by_type}
          workflows={@workflows}
        />
        """
      end

      @impl Pyre.Config
      def render_workflow_capacity(var!(assigns)) do
        ~H"""
        <PyreWeb.Components.WorkflowCapacity.capacity_inline
          :if={@capacity_info}
          info={@capacity_info}
          workflow_label={@workflow_label}
        />
        """
      end

      @impl Pyre.Config
      def run_stop(run_id), do: apply(Pyre.RunServer, :stop_run, [run_id])

      defoverridable after_flow_start: 1,
                     after_flow_complete: 1,
                     after_flow_error: 1,
                     after_action_start: 1,
                     after_action_complete: 1,
                     after_action_error: 1,
                     after_llm_call_complete: 1,
                     after_llm_call_error: 1,
                     max_capacity: 0,
                     list_workflows: 0,
                     authorize_socket_connect: 2,
                     authorize_channel_join: 3,
                     authorize_run_create: 2,
                     authorize_run_control: 2,
                     authorize_remote_action: 2,
                     authorize_webhook: 2,
                     websocket_service_tokens: 0,
                     websocket_service_token_valid?: 1,
                     update_github_app: 1,
                     list_github_apps: 0,
                     additional_nav_links: 1,
                     sidebar_footer: 1,
                     run_submit: 2,
                     list_runs: 0,
                     get_run: 1,
                     render_run: 1,
                     render_workflow_capacities: 1,
                     render_workflow_capacity: 1,
                     run_stop: 1
    end
  end

  # -- Default implementations (used when no custom config module is configured) --

  def max_capacity, do: 1

  def after_flow_start(_event), do: :ok
  def after_flow_complete(_event), do: :ok
  def after_flow_error(_event), do: :ok
  def after_action_start(_event), do: :ok
  def after_action_complete(_event), do: :ok
  def after_action_error(_event), do: :ok
  def after_llm_call_complete(_event), do: :ok
  def after_llm_call_error(_event), do: :ok

  def authorize_socket_connect(_params, _connect_info), do: :ok
  def authorize_channel_join(_topic, _params, _socket), do: :ok
  def authorize_run_create(_run_params, _socket), do: :ok
  def authorize_run_control(_action, _socket), do: :ok
  def authorize_remote_action(_action, _socket), do: :ok
  def authorize_webhook(_event, _payload), do: :ok

  def websocket_service_tokens do
    case Application.get_env(:pyre, :websocket_service_tokens) do
      nil -> []
      tokens when is_list(tokens) -> tokens
      csv when is_binary(csv) ->
        csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    end
  end

  def websocket_service_token_valid?(token) when is_binary(token) do
    Enum.any?(websocket_service_tokens(), &Plug.Crypto.secure_compare(&1, token))
  end

  def websocket_service_token_valid?(_), do: false

  def update_github_app(_credentials), do: :ok
  def list_github_apps, do: list_github_apps_from_env()
  def additional_nav_links(assigns), do: ~H""
  def sidebar_footer(assigns), do: ~H""

  def run_submit(description, opts) do
    case apply(Pyre.RunServer, :start_run, [description, opts]) do
      {:ok, run_id} -> {:ok, redirect_to: "/runs/#{run_id}"}
      {:error, _} = error -> error
    end
  end

  def list_runs, do: apply(Pyre.RunServer, :list_runs, [])
  def get_run(run_id), do: apply(Pyre.RunServer, :get_state, [run_id])
  def render_run(assigns), do: ~H""

  def render_workflow_capacities(assigns) do
    ~H"""
    <PyreWeb.Components.WorkflowCapacity.capacity_grid
      capacity_by_type={@capacity_by_type}
      workflows={@workflows}
    />
    """
  end

  def render_workflow_capacity(assigns) do
    ~H"""
    <PyreWeb.Components.WorkflowCapacity.capacity_inline
      :if={@capacity_info}
      info={@capacity_info}
      workflow_label={@workflow_label}
    />
    """
  end

  def run_stop(run_id), do: apply(Pyre.RunServer, :stop_run, [run_id])
end
