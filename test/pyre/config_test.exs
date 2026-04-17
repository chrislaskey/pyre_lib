defmodule Pyre.ConfigTest do
  use ExUnit.Case, async: false

  alias Pyre.Config
  alias Pyre.Events.FlowStarted

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

    test "provides default list_llm_backends and get_llm_backend" do
      assert function_exported?(TrackingConfig, :list_llm_backends, 0)
      assert function_exported?(TrackingConfig, :get_llm_backend, 1)
    end

    test "provides default list_workflows" do
      assert function_exported?(TrackingConfig, :list_workflows, 0)
    end

    test "default list_llm_backends delegates to included_llm_backends" do
      assert TrackingConfig.list_llm_backends() == Config.included_llm_backends()
    end

    test "default list_workflows delegates to included_workflows" do
      assert TrackingConfig.list_workflows() == Config.included_workflows()
    end
  end

  describe "included_llm_backends/0" do
    test "returns list of backend entries with required fields" do
      backends = Config.included_llm_backends()
      assert is_list(backends)
      assert length(backends) > 0

      for entry <- backends do
        assert is_atom(entry.module)
        assert is_binary(entry.name)
        assert is_binary(entry.label)
        assert is_binary(entry.description)
      end
    end

    test "includes the built-in backends" do
      names = Config.included_llm_backends() |> Enum.map(& &1.name)
      assert "req_llm" in names
      assert "claude_cli" in names
      assert "cursor_cli" in names
      assert "codex_cli" in names
    end
  end

  describe "list_llm_backends/0" do
    test "returns included backends when no custom config is set" do
      Application.delete_env(:pyre, :config)
      assert Config.list_llm_backends() == Config.included_llm_backends()
    end

    test "delegates to custom config module when set" do
      Application.put_env(:pyre, :config, TrackingConfig)
      assert Config.list_llm_backends() == Config.included_llm_backends()
    end
  end

  describe "get_llm_backend/1" do
    test "returns first backend when no env var is set" do
      Application.delete_env(:pyre, :config)
      original_env = System.get_env("PYRE_LLM_BACKEND")
      System.delete_env("PYRE_LLM_BACKEND")
      on_exit(fn -> if original_env, do: System.put_env("PYRE_LLM_BACKEND", original_env) end)

      assert Config.get_llm_backend() == Pyre.LLM.ReqLLM
    end

    test "matches PYRE_LLM_BACKEND env var against backend names" do
      Application.delete_env(:pyre, :config)
      original_env = System.get_env("PYRE_LLM_BACKEND")
      System.put_env("PYRE_LLM_BACKEND", "claude_cli")

      on_exit(fn ->
        if original_env,
          do: System.put_env("PYRE_LLM_BACKEND", original_env),
          else: System.delete_env("PYRE_LLM_BACKEND")
      end)

      assert Config.get_llm_backend() == Pyre.LLM.ClaudeCLI
    end

    test "falls back to first backend for unknown env var value" do
      Application.delete_env(:pyre, :config)
      original_env = System.get_env("PYRE_LLM_BACKEND")
      System.put_env("PYRE_LLM_BACKEND", "nonexistent_backend")

      on_exit(fn ->
        if original_env,
          do: System.put_env("PYRE_LLM_BACKEND", original_env),
          else: System.delete_env("PYRE_LLM_BACKEND")
      end)

      assert Config.get_llm_backend() == Pyre.LLM.ReqLLM
    end

    test "looks up backend by name when given a string" do
      Application.delete_env(:pyre, :config)
      assert Config.get_llm_backend("claude_cli") == Pyre.LLM.ClaudeCLI
      assert Config.get_llm_backend("codex_cli") == Pyre.LLM.CodexCLI
      assert Config.get_llm_backend("req_llm") == Pyre.LLM.ReqLLM
    end

    test "falls back to default for unknown name string" do
      Application.delete_env(:pyre, :config)
      original_env = System.get_env("PYRE_LLM_BACKEND")
      System.delete_env("PYRE_LLM_BACKEND")
      on_exit(fn -> if original_env, do: System.put_env("PYRE_LLM_BACKEND", original_env) end)

      assert Config.get_llm_backend("nonexistent") == Pyre.LLM.ReqLLM
    end
  end

  describe "find_backend_by_name/2" do
    test "finds backend by name" do
      backends = Config.included_llm_backends()

      assert {:ok, %{module: Pyre.LLM.ClaudeCLI}} =
               Config.find_backend_by_name(backends, "claude_cli")
    end

    test "returns :error for unknown name" do
      backends = Config.included_llm_backends()
      assert :error = Config.find_backend_by_name(backends, "nonexistent")
    end
  end

  describe "backend_name_for_module/1" do
    test "returns name for known module" do
      assert Config.backend_name_for_module(Pyre.LLM.ClaudeCLI) == "claude_cli"
      assert Config.backend_name_for_module(Pyre.LLM.ReqLLM) == "req_llm"
    end

    test "returns 'other' for unknown module" do
      assert Config.backend_name_for_module(SomeUnknownModule) == "other"
    end
  end

  describe "included_workflows/0" do
    test "returns list of workflow entries with required fields" do
      workflows = Config.included_workflows()
      assert is_list(workflows)
      assert length(workflows) > 0

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

  describe "resolve_llm_backend/1" do
    test "returns first backend module when no env var is set" do
      original_env = System.get_env("PYRE_LLM_BACKEND")
      System.delete_env("PYRE_LLM_BACKEND")
      on_exit(fn -> if original_env, do: System.put_env("PYRE_LLM_BACKEND", original_env) end)

      backends = [
        %{module: MyModule, name: "my_mod", label: "My", description: "Test"}
      ]

      assert Config.resolve_llm_backend(backends) == MyModule
    end

    test "matches env var against backend name" do
      original_env = System.get_env("PYRE_LLM_BACKEND")
      System.put_env("PYRE_LLM_BACKEND", "second")

      on_exit(fn ->
        if original_env,
          do: System.put_env("PYRE_LLM_BACKEND", original_env),
          else: System.delete_env("PYRE_LLM_BACKEND")
      end)

      backends = [
        %{module: First, name: "first", label: "First", description: "Test"},
        %{module: Second, name: "second", label: "Second", description: "Test"}
      ]

      assert Config.resolve_llm_backend(backends) == Second
    end

    test "falls back to first when env var doesn't match" do
      original_env = System.get_env("PYRE_LLM_BACKEND")
      System.put_env("PYRE_LLM_BACKEND", "unknown")

      on_exit(fn ->
        if original_env,
          do: System.put_env("PYRE_LLM_BACKEND", original_env),
          else: System.delete_env("PYRE_LLM_BACKEND")
      end)

      backends = [
        %{module: First, name: "first", label: "First", description: "Test"}
      ]

      assert Config.resolve_llm_backend(backends) == First
    end

    test "falls back to ReqLLM for empty list" do
      assert Config.resolve_llm_backend([]) == Pyre.LLM.ReqLLM
    end
  end
end
