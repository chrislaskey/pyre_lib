defmodule PyreWeb.GitHubCallbackController do
  @moduledoc """
  Handles the redirect from GitHub after App manifest registration.

  Exchanges the temporary code for App credentials and stores them
  via the `PyreWeb.Config.update_github_app/1` callback.
  """

  use Phoenix.Controller, formats: [:html]

  require Logger

  def callback(conn, %{"code" => code}) do
    case exchange_code(code) do
      {:ok, credentials} ->
        Logger.info("GitHub App created successfully. App ID: #{credentials.app_id}")

        # Store via Config callback (no-op by default, consuming apps persist)
        PyreWeb.Config.call(:update_github_app, [credentials])

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, render_credentials_page(credentials))

      {:error, reason} ->
        Logger.error("GitHub App manifest exchange failed: #{inspect(reason)}")

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(500, render_error_page(reason))
    end
  end

  def callback(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(400, render_error_page(:missing_code))
  end

  defp exchange_code(code) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      case apply(Req, :post, [
             "https://api.github.com/app-manifests/#{code}/conversions",
             [headers: [{"accept", "application/vnd.github+json"}]]
           ]) do
        {:ok, %{status: 201, body: body}} ->
          {:ok,
           %{
             app_id: to_string(body["id"]),
             private_key: body["pem"],
             webhook_secret: body["webhook_secret"],
             client_id: body["client_id"],
             client_secret: body["client_secret"],
             bot_slug: body["slug"],
             html_url: body["html_url"]
           }}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body["message"]}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp render_credentials_page(credentials) do
    """
    <!DOCTYPE html>
    <html>
    <head><title>GitHub App Created</title></head>
    <body style="font-family: system-ui, sans-serif; max-width: 800px; margin: 2rem auto; padding: 0 1rem;">
      <h1>GitHub App Created Successfully</h1>
      <p>Your GitHub App has been registered. Set the following environment variables and restart your application:</p>
      <pre style="background: #f4f4f4; padding: 1rem; border-radius: 4px; overflow-x: auto;">
    GITHUB_APP_ID=#{credentials.app_id}
    GITHUB_APP_PRIVATE_KEY="#{String.replace(credentials.private_key || "", "\n", "\\n")}"
    GITHUB_WEBHOOK_SECRET=#{credentials.webhook_secret}
    GITHUB_APP_BOT_SLUG=#{credentials.bot_slug}</pre>

      <p><strong>Important:</strong> Save the private key now — GitHub will not show it again.</p>

      <p>Next steps:</p>
      <ol>
        <li>Set the environment variables above in your deployment configuration.</li>
        <li>Restart the application.</li>
        <li>
          Install the App on your repositories:
          <a href="#{credentials.html_url}/installations/new">Install #{credentials.bot_slug}</a>
        </li>
        <li>Mention <code>@#{credentials.bot_slug} review</code> in a PR comment to trigger a review.</li>
      </ol>
    </body>
    </html>
    """
  end

  defp render_error_page(reason) do
    """
    <!DOCTYPE html>
    <html>
    <head><title>GitHub App Setup Failed</title></head>
    <body style="font-family: system-ui, sans-serif; max-width: 800px; margin: 2rem auto; padding: 0 1rem;">
      <h1>GitHub App Setup Failed</h1>
      <p>Error: <code>#{inspect(reason)}</code></p>
      <p><a href="javascript:history.back()">Go back and try again</a></p>
    </body>
    </html>
    """
  end
end
