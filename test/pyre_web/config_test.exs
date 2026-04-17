defmodule PyreWeb.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    previous = Application.get_env(:pyre_web, :config)
    previous_apps = Application.get_env(:pyre, :github_apps)

    on_exit(fn ->
      Application.put_env(:pyre_web, :config, previous)

      if previous_apps do
        Application.put_env(:pyre, :github_apps, previous_apps)
      else
        Application.delete_env(:pyre, :github_apps)
      end
    end)

    Application.delete_env(:pyre, :github_apps)
    :ok
  end

  describe "authorize/2 with defaults" do
    test "returns :ok for authorize_socket_connect" do
      Application.delete_env(:pyre_web, :config)
      assert :ok = PyreWeb.Config.authorize(:authorize_socket_connect, [%{}, %{}])
    end

    test "returns :ok for authorize_channel_join" do
      Application.delete_env(:pyre_web, :config)
      assert :ok = PyreWeb.Config.authorize(:authorize_channel_join, ["pyre:connections", %{}])
    end

    test "returns :ok for authorize_run_create" do
      Application.delete_env(:pyre_web, :config)
      assert :ok = PyreWeb.Config.authorize(:authorize_run_create, [%{}, %{}])
    end

    test "returns :ok for authorize_run_control" do
      Application.delete_env(:pyre_web, :config)
      assert :ok = PyreWeb.Config.authorize(:authorize_run_control, [%{}, %{}])
    end

    test "returns :ok for authorize_remote_action" do
      Application.delete_env(:pyre_web, :config)
      assert :ok = PyreWeb.Config.authorize(:authorize_remote_action, [%{}, %{}])
    end

    test "returns :ok for authorize_webhook" do
      Application.delete_env(:pyre_web, :config)
      assert :ok = PyreWeb.Config.authorize(:authorize_webhook, ["issue_comment", %{}])
    end
  end

  describe "call/2 with defaults" do
    test "update_github_app returns :ok" do
      Application.delete_env(:pyre_web, :config)
      assert :ok = PyreWeb.Config.call(:update_github_app, [%{app_id: "123"}])
    end

    test "list_github_apps returns empty list" do
      Application.delete_env(:pyre_web, :config)
      assert [] == PyreWeb.Config.call(:list_github_apps, [])
    end
  end

  describe "call/2 with custom module" do
    test "dispatches update_github_app to configured module" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.WithGitHub)
      assert :ok = PyreWeb.Config.call(:update_github_app, [%{app_id: "123"}])
    end

    test "dispatches list_github_apps to configured module" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.WithGitHub)
      result = PyreWeb.Config.call(:list_github_apps, [])
      assert [%{app_id: "test-app"}] = result
    end

    test "rescues exception and returns nil" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.DataCrasher)

      log =
        capture_log(fn ->
          assert nil == PyreWeb.Config.call(:list_github_apps, [])
        end)

      assert log =~ "PyreWeb.Config hook list_github_apps raised"
    end
  end

  describe "authorize/2 with custom module" do
    test "dispatches to configured module" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.AllowAll)
      assert :ok = PyreWeb.Config.authorize(:authorize_socket_connect, [%{}, %{}])
    end

    test "propagates {:error, reason} from custom module" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.DenyAll)

      assert {:error, :unauthorized} =
               PyreWeb.Config.authorize(:authorize_socket_connect, [%{}, %{}])
    end

    test "propagates {:error, reason} for each hook" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.DenyAll)

      assert {:error, :unauthorized} =
               PyreWeb.Config.authorize(:authorize_channel_join, ["topic", %{}])

      assert {:error, :unauthorized} =
               PyreWeb.Config.authorize(:authorize_run_create, [%{}, %{}])

      assert {:error, :unauthorized} =
               PyreWeb.Config.authorize(:authorize_run_control, [%{}, %{}])

      assert {:error, :unauthorized} =
               PyreWeb.Config.authorize(:authorize_remote_action, [%{}, %{}])

      assert {:error, :unauthorized} =
               PyreWeb.Config.authorize(:authorize_webhook, ["event", %{}])
    end
  end

  describe "authorize/2 crash recovery" do
    test "rescues exception and returns :ok" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.Crasher)

      log =
        capture_log(fn ->
          assert :ok = PyreWeb.Config.authorize(:authorize_socket_connect, [%{}, %{}])
        end)

      assert log =~ "PyreWeb.Config hook authorize_socket_connect raised"
      assert log =~ "boom"
    end
  end

  describe "call/2 sidebar_footer" do
    test "returns empty rendered by default" do
      Application.delete_env(:pyre_web, :config)
      result = PyreWeb.Config.call(:sidebar_footer, [%{}])
      assert %Phoenix.LiveView.Rendered{} = result
    end

    test "dispatches to configured module" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.WithSidebarFooter)
      result = PyreWeb.Config.call(:sidebar_footer, [%{}])
      assert %Phoenix.LiveView.Rendered{} = result
      assert result.static |> Enum.join() =~ "Custom Footer"
    end

    test "returns nil on crash" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.DataCrasher)

      log =
        capture_log(fn ->
          assert nil == PyreWeb.Config.call(:sidebar_footer, [%{}])
        end)

      assert log =~ "PyreWeb.Config hook sidebar_footer raised"
    end
  end

  describe "list_github_apps" do
    test "returns empty list when no config set" do
      Application.delete_env(:pyre_web, :config)
      Application.delete_env(:pyre, :github_apps)
      assert [] == PyreWeb.Config.call(:list_github_apps, [])
    end

    test "returns normalized maps from keyword list config" do
      Application.delete_env(:pyre_web, :config)

      Application.put_env(:pyre, :github_apps, [
        [app_id: "111", webhook_secret: "sec1", bot_slug: "bot1"],
        [app_id: "222", webhook_secret: "sec2", bot_slug: "bot2"]
      ])

      result = PyreWeb.Config.call(:list_github_apps, [])
      assert length(result) == 2
      assert Enum.at(result, 0) == %{app_id: "111", webhook_secret: "sec1", bot_slug: "bot1"}
      assert Enum.at(result, 1) == %{app_id: "222", webhook_secret: "sec2", bot_slug: "bot2"}
    end

    test "dispatches list_github_apps to custom module" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.WithGitHub)
      result = PyreWeb.Config.call(:list_github_apps, [])
      assert [%{app_id: "test-app"}] = result
    end
  end

  describe "__using__ macro" do
    test "produces all overridable callbacks with defaults" do
      mod = PyreWeb.ConfigTest.AllowAll

      assert :ok = mod.authorize_socket_connect(%{}, %{})
      assert :ok = mod.authorize_channel_join("topic", %{})
      assert :ok = mod.authorize_run_create(%{}, %{})
      assert :ok = mod.authorize_run_control(%{}, %{})
      assert :ok = mod.authorize_remote_action(%{}, %{})
      assert :ok = mod.authorize_webhook("event", %{})
      assert :ok = mod.update_github_app(%{})
      assert [] == mod.list_github_apps()
      assert %Phoenix.LiveView.Rendered{} = mod.sidebar_footer(%{})
    end

    test "allows overriding individual callbacks" do
      mod = PyreWeb.ConfigTest.DenyAll

      assert {:error, :unauthorized} = mod.authorize_socket_connect(%{}, %{})
      # Non-overridden callbacks still return :ok
      # (DenyAll overrides all, so test with partial override)
    end
  end

  describe "get_module/0" do
    test "returns PyreWeb.Config when no config set" do
      Application.delete_env(:pyre_web, :config)
      assert PyreWeb.Config.get_module() == PyreWeb.Config
    end

    test "returns configured module" do
      Application.put_env(:pyre_web, :config, PyreWeb.ConfigTest.AllowAll)
      assert PyreWeb.Config.get_module() == PyreWeb.ConfigTest.AllowAll
    end
  end

  # -- Test helper modules --

  defmodule AllowAll do
    use PyreWeb.Config
  end

  defmodule DenyAll do
    use PyreWeb.Config

    @impl true
    def authorize_socket_connect(_params, _connect_info), do: {:error, :unauthorized}
    @impl true
    def authorize_channel_join(_topic, _socket), do: {:error, :unauthorized}
    @impl true
    def authorize_run_create(_run_params, _socket), do: {:error, :unauthorized}
    @impl true
    def authorize_run_control(_action, _socket), do: {:error, :unauthorized}
    @impl true
    def authorize_remote_action(_action, _socket), do: {:error, :unauthorized}
    @impl true
    def authorize_webhook(_event, _payload), do: {:error, :unauthorized}
  end

  defmodule WithGitHub do
    use PyreWeb.Config

    @impl true
    def update_github_app(_credentials), do: :ok

    @impl true
    def list_github_apps, do: [%{app_id: "test-app", bot_slug: "test-bot"}]
  end

  defmodule Crasher do
    use PyreWeb.Config

    @impl true
    def authorize_socket_connect(_params, _connect_info), do: raise("boom")
  end

  defmodule WithSidebarFooter do
    use PyreWeb.Config
    import Phoenix.Component, only: [sigil_H: 2]

    @impl true
    def sidebar_footer(assigns) do
      ~H"""
      <div>Custom Footer</div>
      """
    end
  end

  defmodule DataCrasher do
    use PyreWeb.Config

    @impl true
    def list_github_apps, do: raise("data boom")
    @impl true
    def sidebar_footer(_assigns), do: raise("sidebar boom")
  end
end
