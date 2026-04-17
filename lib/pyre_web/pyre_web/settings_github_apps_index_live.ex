defmodule PyreWeb.SettingsGithubAppsIndexLive do
  @moduledoc """
  GitHub Apps landing page showing current configuration and a link to register.
  """
  use PyreWeb.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    all_apps = PyreWeb.Config.call(:list_github_apps, []) || []

    apps =
      Enum.map(all_apps, fn config ->
        %{
          app_id: config[:app_id],
          bot_slug: config[:bot_slug],
          webhook_secret_set: config[:webhook_secret] != nil,
          private_key_set: config[:private_key] != nil
        }
      end)

    {:ok, assign(socket, page_title: "GitHub Apps", apps: apps)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end
end
