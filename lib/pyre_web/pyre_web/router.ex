defmodule PyreWeb.Router do
  @moduledoc """
  Provides LiveView routing for PyreWeb.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import PyreWeb.Router

        scope "/" do
          pipe_through :browser
          pyre_web "/pyre"
        end
      end

  ## Options

    * `:on_mount` - A list of `Phoenix.LiveView.on_mount/1` callbacks.
      Use this to add authentication. A single value may also be declared.

    * `:live_socket_path` - Configures the socket path. Must match the
      `socket "/live", Phoenix.LiveView.Socket` in your endpoint.
      Defaults to `"/live"`.

    * `:live_session_name` - The name of the live session. Defaults to
      `:pyre_web`. Only needed if mounting multiple instances.
  """

  @doc """
  Defines a PyreWeb route at the given `path`.
  """
  defmacro pyre_web(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote bind_quoted: binding() do
      scope path, alias: false, as: false do
        {session_name, session_opts, route_opts} =
          PyreWeb.Router.__options__(opts)

        import Phoenix.Router, only: [get: 4, post: 4]
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        live_session session_name, session_opts do
          get "/js-:md5", PyreWeb.Assets, :js, as: :pyre_web_asset

          live "/", PyreWeb.HomeLive, :index, route_opts

          live "/connected-apps", PyreWeb.ConnectedAppsListLive, :index, route_opts

          live "/runs", PyreWeb.RunListLive, :index, route_opts
          live "/runs/new", PyreWeb.RunNewLive, :new, route_opts
          live "/runs/:id", PyreWeb.RunShowLive, :show, route_opts

          live "/settings", PyreWeb.SettingsLive, :index, route_opts
          live "/settings/github-apps", PyreWeb.SettingsGithubAppsIndexLive, :index, route_opts
          live "/settings/github-apps/new", PyreWeb.SettingsGithubAppsShowLive, :new, route_opts
        end

        get "/github/callback", PyreWeb.GitHubCallbackController, :callback,
          as: :pyre_github_callback

        post "/webhooks/github", PyreWeb.WebhookController, :github, as: :pyre_webhook
      end

      unless Module.get_attribute(__MODULE__, :pyre_web_prefix) do
        @pyre_web_prefix Phoenix.Router.scoped_path(__MODULE__, path)
                         |> String.replace_suffix("/", "")

        def __pyre_web_prefix__, do: @pyre_web_prefix
      end
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:pyre_web, 2}})

  defp expand_alias(other, _env), do: other

  @doc false
  def __options__(options) do
    live_socket_path = Keyword.get(options, :live_socket_path, "/live")
    on_mount = Keyword.get(options, :on_mount)

    session_opts =
      [
        session: {__MODULE__, :__session__, []},
        root_layout: {PyreWeb.LayoutView, :root}
      ]
      |> maybe_put(:on_mount, on_mount)

    route_opts = [
      private: %{live_socket_path: live_socket_path},
      as: :pyre_web
    ]

    {
      Keyword.get(options, :live_session_name, :pyre_web),
      session_opts,
      route_opts
    }
  end

  @doc false
  def __session__(_conn) do
    %{}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
