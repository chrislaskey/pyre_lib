defmodule Pyre.ConfigTest do
  use ExUnit.Case, async: false

  alias Pyre.Config
  alias Pyre.Events.FlowStarted

  @moduletag :capture_log

  defmodule TrackingConfig do
    use Pyre.Config

    @impl true
    def after_flow_start(event) do
      send(Process.get(:test_pid), {:hook, :after_flow_start, event})
      :ok
    end
  end

  defmodule CrashingConfig do
    use Pyre.Config

    @impl true
    def after_flow_start(_event) do
      raise "boom"
    end
  end

  setup do
    original = Application.get_env(:pyre, :config)
    on_exit(fn -> Application.put_env(:pyre, :config, original) end)
    :ok
  end

  describe "notify/2" do
    test "dispatches to default no-op without error" do
      Application.delete_env(:pyre, :config)

      assert :ok =
               Config.notify(:after_flow_start, %FlowStarted{
                 flow_module: Pyre.Flows.Task,
                 description: "test",
                 run_dir: "/tmp/test",
                 working_dir: "/tmp"
               })
    end

    test "dispatches to configured custom module" do
      Process.put(:test_pid, self())
      Application.put_env(:pyre, :config, TrackingConfig)

      event = %FlowStarted{
        flow_module: Pyre.Flows.Task,
        description: "test",
        run_dir: "/tmp/test",
        working_dir: "/tmp"
      }

      Config.notify(:after_flow_start, event)

      assert_received {:hook, :after_flow_start, ^event}
    end

    test "rescues exceptions in user hook implementations" do
      Application.put_env(:pyre, :config, CrashingConfig)

      assert :ok =
               Config.notify(:after_flow_start, %FlowStarted{
                 flow_module: Pyre.Flows.Task,
                 description: "test",
                 run_dir: "/tmp/test",
                 working_dir: "/tmp"
               })
    end
  end

  describe "__using__" do
    test "produces overridable callbacks" do
      # TrackingConfig overrides after_flow_start but inherits others
      assert function_exported?(TrackingConfig, :after_flow_start, 1)
      assert function_exported?(TrackingConfig, :after_flow_complete, 1)
      assert function_exported?(TrackingConfig, :after_flow_error, 1)
      assert function_exported?(TrackingConfig, :after_action_start, 1)
      assert function_exported?(TrackingConfig, :after_action_complete, 1)
      assert function_exported?(TrackingConfig, :after_action_error, 1)
      assert function_exported?(TrackingConfig, :after_llm_call_complete, 1)
      assert function_exported?(TrackingConfig, :after_llm_call_error, 1)
    end

    test "provides default list_workflows" do
      assert function_exported?(TrackingConfig, :list_workflows, 0)
    end

    test "default list_workflows delegates to included_workflows" do
      assert TrackingConfig.list_workflows() == Config.included_workflows()
    end
  end

  describe "included_workflows/0" do
    test "returns list of workflow entries with required fields" do
      workflows = Config.included_workflows()
      assert is_list(workflows)
      refute Enum.empty?(workflows)

      for entry <- workflows do
        assert is_atom(entry.name)
        assert is_atom(entry.module)
        assert is_binary(entry.label)
        assert is_binary(entry.description)
        assert entry.mode in [:interactive, :background]
        assert is_list(entry.stages)

        for {stage_name, stage_label} <- entry.stages do
          assert is_atom(stage_name)
          assert is_binary(stage_label)
        end
      end
    end

    test "includes the built-in workflows" do
      names = Config.included_workflows() |> Enum.map(& &1.name)
      assert :chat in names
      assert :prototype in names
      assert :feature in names
      assert :overnight_feature in names
      assert :task in names
      assert :code_review in names
    end
  end

  describe "list_workflows/0" do
    test "returns included workflows when no custom config is set" do
      Application.delete_env(:pyre, :config)
      assert Config.list_workflows() == Config.included_workflows()
    end

    test "delegates to custom config module when set" do
      Application.put_env(:pyre, :config, TrackingConfig)
      assert Config.list_workflows() == Config.included_workflows()
    end
  end

  describe "get_workflow/1" do
    test "returns workflow entry for known name" do
      assert {:ok, %{module: Pyre.Flows.Chat, name: :chat}} = Config.get_workflow(:chat)
      assert {:ok, %{module: Pyre.Flows.Feature, name: :feature}} = Config.get_workflow(:feature)

      assert {:ok, %{module: Pyre.Flows.OvernightFeature}} =
               Config.get_workflow(:overnight_feature)
    end

    test "returns :error for unknown name" do
      assert :error = Config.get_workflow(:nonexistent)
    end

    test "workflow entry contains stages as {atom, string} tuples" do
      {:ok, entry} = Config.get_workflow(:overnight_feature)

      assert entry.stages == [
               {:planning, "Product Manager"},
               {:designing, "Designer"},
               {:implementing, "Programmer"},
               {:testing, "Test Writer"},
               {:reviewing, "QA Reviewer"},
               {:shipping, "Shipper"}
             ]
    end

    test "workflow entry contains mode" do
      {:ok, chat} = Config.get_workflow(:chat)
      assert chat.mode == :interactive

      {:ok, task} = Config.get_workflow(:task)
      assert task.mode == :background
    end
  end

  describe "websocket_service_tokens/0" do
    setup do
      original = Application.get_env(:pyre, :websocket_service_tokens)
      on_exit(fn ->
        if original, do: Application.put_env(:pyre, :websocket_service_tokens, original),
                     else: Application.delete_env(:pyre, :websocket_service_tokens)
      end)
      :ok
    end

    test "parses comma-separated string" do
      Application.put_env(:pyre, :websocket_service_tokens, "tok-a, tok-b, tok-c")
      assert Config.websocket_service_tokens() == ["tok-a", "tok-b", "tok-c"]
    end

    test "passes through list config" do
      Application.put_env(:pyre, :websocket_service_tokens, ["tok-a", "tok-b"])
      assert Config.websocket_service_tokens() == ["tok-a", "tok-b"]
    end

    test "returns empty list when unconfigured" do
      Application.delete_env(:pyre, :websocket_service_tokens)
      assert Config.websocket_service_tokens() == []
    end

    test "trims whitespace from CSV entries" do
      Application.put_env(:pyre, :websocket_service_tokens, "  tok-a , tok-b  ")
      assert Config.websocket_service_tokens() == ["tok-a", "tok-b"]
    end
  end

  describe "websocket_service_token_valid?/1" do
    setup do
      original = Application.get_env(:pyre, :websocket_service_tokens)
      on_exit(fn ->
        if original, do: Application.put_env(:pyre, :websocket_service_tokens, original),
                     else: Application.delete_env(:pyre, :websocket_service_tokens)
      end)
      Application.put_env(:pyre, :websocket_service_tokens, ["valid-token", "another-token"])
      :ok
    end

    test "returns true for a valid token" do
      assert Config.websocket_service_token_valid?("valid-token")
      assert Config.websocket_service_token_valid?("another-token")
    end

    test "returns false for an invalid token" do
      refute Config.websocket_service_token_valid?("wrong-token")
    end

    test "returns false for nil" do
      refute Config.websocket_service_token_valid?(nil)
    end

    test "returns false for empty string" do
      refute Config.websocket_service_token_valid?("")
    end

    test "returns false when no tokens configured" do
      Application.delete_env(:pyre, :websocket_service_tokens)
      refute Config.websocket_service_token_valid?("any-token")
    end
  end

  describe "authorize/2 fail-closed" do
    defmodule CrashingAuth do
      use Pyre.Config

      @impl true
      def authorize_socket_connect(_params, _connect_info) do
        raise "auth crash"
      end
    end

    test "returns {:error, :auth_error} when callback raises" do
      Application.put_env(:pyre, :config, CrashingAuth)
      assert {:error, :auth_error} = Config.authorize(:authorize_socket_connect, [%{}, %{}])
    end

    test "passes through :ok from callback" do
      Application.delete_env(:pyre, :config)
      assert :ok = Config.authorize(:authorize_socket_connect, [%{}, %{}])
    end

    test "passes through {:error, reason} from callback" do
      defmodule DenyAll do
        use Pyre.Config

        @impl true
        def authorize_socket_connect(_params, _connect_info), do: {:error, :denied}
      end

      Application.put_env(:pyre, :config, DenyAll)
      assert {:error, :denied} = Config.authorize(:authorize_socket_connect, [%{}, %{}])
    end
  end
end
