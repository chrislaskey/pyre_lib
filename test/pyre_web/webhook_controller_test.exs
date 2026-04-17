defmodule PyreWeb.WebhookControllerTest do
  use PyreWeb.Test.ConnCase, async: false

  @webhook_secret "test_webhook_secret_123"

  setup do
    previous_config = Application.get_env(:pyre_web, :config)
    previous_github_apps = Application.get_env(:pyre, :github_apps)

    Application.put_env(:pyre, :github_apps, [
      [
        app_id: "12345",
        private_key: "test-key",
        webhook_secret: @webhook_secret,
        bot_slug: "pyre-test-bot"
      ]
    ])

    on_exit(fn ->
      Application.put_env(:pyre_web, :config, previous_config)

      if previous_github_apps do
        Application.put_env(:pyre, :github_apps, previous_github_apps)
      else
        Application.delete_env(:pyre, :github_apps)
      end
    end)

    :ok
  end

  describe "signature verification" do
    test "rejects requests with invalid signature", %{conn: conn} do
      payload = Jason.encode!(%{"action" => "created"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issue_comment")
        |> put_req_header("x-hub-signature-256", "sha256=invalid")
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 401) == %{"error" => "invalid signature"}
    end

    test "accepts requests with valid signature", %{conn: conn} do
      payload = Jason.encode!(%{"action" => "created", "comment" => %{"body" => "hello"}})
      signature = compute_signature(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "ping")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 200) == %{"status" => "accepted"}
    end

    test "skips verification when no secret configured", %{conn: conn} do
      Application.put_env(:pyre, :github_apps, [[app_id: "12345", private_key: "test-key"]])

      payload = Jason.encode!(%{"action" => "created"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "ping")
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 200) == %{"status" => "accepted"}
    end
  end

  describe "multi-app signature verification" do
    test "accepts when second app's secret matches", %{conn: conn} do
      Application.put_env(:pyre, :github_apps, [
        [app_id: "11111", webhook_secret: "wrong_secret", bot_slug: "bot1"],
        [app_id: "22222", webhook_secret: @webhook_secret, bot_slug: "bot2"]
      ])

      payload = Jason.encode!(%{"action" => "created"})
      signature = compute_signature(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "ping")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 200) == %{"status" => "accepted"}
    end

    test "rejects when no app secret matches", %{conn: conn} do
      Application.put_env(:pyre, :github_apps, [
        [app_id: "11111", webhook_secret: "wrong1", bot_slug: "bot1"],
        [app_id: "22222", webhook_secret: "wrong2", bot_slug: "bot2"]
      ])

      payload = Jason.encode!(%{"action" => "created"})
      signature = compute_signature(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "ping")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 401) == %{"error" => "invalid signature"}
    end
  end

  describe "authorization" do
    test "rejects when authorize_webhook returns error", %{conn: conn} do
      Application.put_env(:pyre_web, :config, PyreWeb.WebhookControllerTest.DenyWebhooks)

      payload = Jason.encode!(%{"action" => "created"})
      signature = compute_signature(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issue_comment")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 403)
    end
  end

  describe "event dispatch" do
    test "accepts and handles issue_comment events", %{conn: conn} do
      payload =
        Jason.encode!(%{
          "action" => "created",
          "issue" => %{"number" => 42, "pull_request" => %{"url" => "..."}},
          "comment" => %{"id" => 1, "body" => "just a regular comment"},
          "repository" => %{"name" => "test-repo", "owner" => %{"login" => "test-owner"}},
          "installation" => %{"id" => 99}
        })

      signature = compute_signature(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issue_comment")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 200) == %{"status" => "accepted"}
    end

    test "ignores issue_comment on non-PR issues", %{conn: conn} do
      payload =
        Jason.encode!(%{
          "action" => "created",
          "issue" => %{"number" => 42},
          "comment" => %{"id" => 1, "body" => "@pyre-test-bot review"},
          "repository" => %{"name" => "test-repo", "owner" => %{"login" => "test-owner"}},
          "installation" => %{"id" => 99}
        })

      signature = compute_signature(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issue_comment")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 200) == %{"status" => "accepted"}
    end

    test "ignores unknown event types", %{conn: conn} do
      payload = Jason.encode!(%{"action" => "completed"})
      signature = compute_signature(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "check_run")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_private(:raw_body, payload)
        |> post("/pyre/webhooks/github", Jason.decode!(payload))

      assert json_response(conn, 200) == %{"status" => "accepted"}
    end
  end

  # --- Helpers ---

  defp compute_signature(payload) do
    mac = :crypto.mac(:hmac, :sha256, @webhook_secret, payload)
    "sha256=" <> Base.encode16(mac, case: :lower)
  end

  # --- Test modules ---

  defmodule DenyWebhooks do
    use PyreWeb.Config

    @impl true
    def authorize_webhook(_event, _payload), do: {:error, :not_allowed}
  end
end
