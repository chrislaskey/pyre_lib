defmodule PyreWeb.Config do
  @moduledoc """
  Behaviour and default configuration for PyreWeb hooks.

  Applications can provide a custom config module by:

  1. Creating a module that `use PyreWeb.Config`
  2. Overriding any callbacks they need
  3. Configuring it in `config.exs`:

         config :pyre_web, config: MyApp.PyreWebConfig

  If no config module is set, `PyreWeb.Config` itself provides the default
  implementations for all callbacks (permit all / no-op).

  ## Example

      defmodule MyApp.PyreWebConfig do
        use PyreWeb.Config

        @impl true
        def authorize_socket_connect(params, _connect_info) do
          case Map.get(params, "token") do
            nil -> {:error, :missing_token}
            _token -> :ok
          end
        end

        @impl true
        def update_github_app(credentials) do
          MyApp.Repo.insert_or_update_github_app(credentials)
        end

        @impl true
        def list_github_apps do
          MyApp.Repo.list_github_apps()
        end
      end

  Any callback not overridden in the custom module will fall back to the
  default implementation provided by `PyreWeb.Config`.

  ## Dispatching

  Use `PyreWeb.Config.authorize/2` to dispatch authorization checks.
  Use `PyreWeb.Config.call/2` to dispatch data-returning callbacks.
  Exceptions raised inside user-provided callbacks are rescued and logged —
  authorization returns `:ok` (fail-open), data callbacks return `nil`.
  """

  require Logger
  import Phoenix.Component, only: [sigil_H: 2]

  # -- Authorization Callbacks --

  @callback authorize_socket_connect(params :: map(), connect_info :: map()) ::
              :ok | {:error, term()}

  @callback authorize_channel_join(topic :: String.t(), socket :: Phoenix.Socket.t()) ::
              :ok | {:error, term()}

  @callback authorize_run_create(run_params :: map(), socket :: Phoenix.LiveView.Socket.t()) ::
              :ok | {:error, term()}

  @callback authorize_run_control(action :: map(), socket :: Phoenix.LiveView.Socket.t()) ::
              :ok | {:error, term()}

  @callback authorize_remote_action(action :: map(), socket :: Phoenix.LiveView.Socket.t()) ::
              :ok | {:error, term()}

  @callback authorize_webhook(event :: String.t(), payload :: map()) ::
              :ok | {:error, term()}

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

  # -- Workflow Callbacks --

  @doc """
  Called when a user submits a new workflow run from the UI.

  Receives the feature description and fully-prepared options keyword list
  containing:

    * `:workflow` - atom (`:chat`, `:feature`, `:prototype`, etc.)
    * `:skipped_stages` - list of atoms
    * `:interactive_stages` - list of atoms
    * `:attachments` - list of `%{filename, content, media_type}` maps
    * `:llm` - LLM backend module (e.g., `Pyre.LLM.ClaudeCLI`)
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
    * `:backend` - backend name string
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
  Returns the configured PyreWeb config module.

  Reads `config :pyre_web, config: MyApp.PyreWebConfig` from the application environment.
  Falls back to `PyreWeb.Config` (default implementations) if none is configured.
  """
  def get_module do
    Application.get_env(:pyre_web, :config) || __MODULE__
  end

  @doc """
  Dispatches an authorization check to the configured config module.

  Returns `:ok` or `{:error, reason}`. Rescues any exception raised inside
  the user's callback and returns `:ok` (fail-open) with a logged warning.
  """
  @spec authorize(atom(), list()) :: :ok | {:error, term()}
  def authorize(hook, args) do
    mod = get_module()

    try do
      apply(mod, hook, args)
    rescue
      e ->
        Logger.warning("PyreWeb.Config hook #{hook} raised: #{Exception.message(e)}")

        :ok
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
        Logger.warning("PyreWeb.Config hook #{hook} raised: #{Exception.message(e)}")
        nil
    end
  end

  # -- __using__ macro --

  defmacro __using__(_opts) do
    quote do
      @behaviour PyreWeb.Config

      @impl PyreWeb.Config
      def authorize_socket_connect(_params, _connect_info), do: :ok
      @impl PyreWeb.Config
      def authorize_channel_join(_topic, _socket), do: :ok
      @impl PyreWeb.Config
      def authorize_run_create(_run_params, _socket), do: :ok
      @impl PyreWeb.Config
      def authorize_run_control(_action, _socket), do: :ok
      @impl PyreWeb.Config
      def authorize_remote_action(_action, _socket), do: :ok
      @impl PyreWeb.Config
      def authorize_webhook(_event, _payload), do: :ok
      @impl PyreWeb.Config
      def update_github_app(_credentials), do: :ok
      @impl PyreWeb.Config
      def list_github_apps, do: PyreWeb.Config.list_github_apps_from_env()
      @impl PyreWeb.Config
      def additional_nav_links(var!(assigns)), do: ~H""
      @impl PyreWeb.Config
      def sidebar_footer(var!(assigns)), do: ~H""

      @impl PyreWeb.Config
      def run_submit(description, opts) do
        case apply(Pyre.RunServer, :start_run, [description, opts]) do
          {:ok, run_id} -> {:ok, redirect_to: "/runs/#{run_id}"}
          {:error, _} = error -> error
        end
      end

      @impl PyreWeb.Config
      def list_runs, do: apply(Pyre.RunServer, :list_runs, [])
      @impl PyreWeb.Config
      def get_run(run_id), do: apply(Pyre.RunServer, :get_state, [run_id])
      @impl PyreWeb.Config
      def render_run(var!(assigns)), do: ~H""
      @impl PyreWeb.Config
      def run_stop(run_id), do: apply(Pyre.RunServer, :stop_run, [run_id])

      defoverridable authorize_socket_connect: 2,
                     authorize_channel_join: 2,
                     authorize_run_create: 2,
                     authorize_run_control: 2,
                     authorize_remote_action: 2,
                     authorize_webhook: 2,
                     update_github_app: 1,
                     list_github_apps: 0,
                     additional_nav_links: 1,
                     sidebar_footer: 1,
                     run_submit: 2,
                     list_runs: 0,
                     get_run: 1,
                     render_run: 1,
                     run_stop: 1
    end
  end

  # -- Default implementations (used when no custom config module is configured) --

  def authorize_socket_connect(_params, _connect_info), do: :ok
  def authorize_channel_join(_topic, _socket), do: :ok
  def authorize_run_create(_run_params, _socket), do: :ok
  def authorize_run_control(_action, _socket), do: :ok
  def authorize_remote_action(_action, _socket), do: :ok
  def authorize_webhook(_event, _payload), do: :ok
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
  def run_stop(run_id), do: apply(Pyre.RunServer, :stop_run, [run_id])

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
end
