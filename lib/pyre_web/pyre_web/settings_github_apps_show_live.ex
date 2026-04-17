defmodule PyreWeb.SettingsGithubAppsShowLive do
  @moduledoc """
  GitHub App setup page using the manifest flow.

  Renders a form that POSTs a manifest to GitHub to register a new App.
  After registration, GitHub redirects to the callback URL with credentials.
  """
  use PyreWeb.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    configured = github_app_configured?()
    bot_slug = github_app_config(:bot_slug)

    {:ok,
     socket
     |> assign(
       page_title: "GitHub App Setup",
       configured: configured,
       bot_slug: bot_slug,
       org_name: nil
     )}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end

  @impl true
  def handle_event("set_org", %{"org_name" => org_name}, socket) do
    org_name = if org_name == "", do: nil, else: String.trim(org_name)
    {:noreply, assign(socket, :org_name, org_name)}
  end

  def github_new_app_url(nil), do: "https://github.com/settings/apps/new"
  def github_new_app_url(org), do: "https://github.com/organizations/#{org}/settings/apps/new"

  def manifest_json(base_url) do
    %{
      name: "Pyre Code Review",
      url: base_url,
      hook_attributes: %{url: "#{base_url}/pyre/webhooks/github", active: true},
      redirect_url: "#{base_url}/pyre/github/callback",
      public: false,
      default_permissions: %{
        pull_requests: "write",
        contents: "read",
        metadata: "read",
        issues: "write"
      },
      default_events: [
        "issue_comment",
        "pull_request_review_comment"
      ]
    }
    |> Jason.encode!()
  end

  def base_url(uri) do
    case Application.get_env(:pyre_web, :public_url) do
      nil ->
        parsed = URI.parse(uri)

        "#{parsed.scheme}://#{parsed.host}#{if parsed.port not in [80, 443], do: ":#{parsed.port}", else: ""}"

      url ->
        String.trim_trailing(url, "/")
    end
  end

  defp github_app_configured? do
    config = github_app_full_config()
    config[:app_id] != nil and config[:private_key] != nil
  end

  defp github_app_config(key) do
    config = github_app_full_config()

    if is_map(config) do
      Map.get(config, key)
    else
      Keyword.get(config, key)
    end
  end

  defp github_app_full_config do
    case PyreWeb.Config.call(:list_github_apps, []) do
      [first | _] -> first
      _ -> %{}
    end
  end
end
