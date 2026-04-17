defmodule Pyre.EventsTest do
  use ExUnit.Case, async: true

  alias Pyre.Events.{
    FlowStarted,
    FlowCompleted,
    FlowError,
    ActionStarted,
    ActionCompleted,
    ActionError,
    LLMCallCompleted,
    LLMCallError
  }

  describe "FlowStarted" do
    test "can be constructed with all required fields" do
      event = %FlowStarted{
        flow_module: Pyre.Flows.Task,
        description: "test task",
        run_dir: "/tmp/run",
        working_dir: "/tmp"
      }

      assert event.flow_module == Pyre.Flows.Task
      assert event.description == "test task"
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, fn ->
        struct!(FlowStarted, %{flow_module: Pyre.Flows.Task})
      end
    end
  end

  describe "FlowCompleted" do
    test "can be constructed with all required fields" do
      event = %FlowCompleted{
        flow_module: Pyre.Flows.Task,
        description: "test",
        run_dir: "/tmp/run",
        result: %{phase: :complete},
        elapsed_ms: 1000
      }

      assert event.elapsed_ms == 1000
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, fn ->
        struct!(FlowCompleted, %{flow_module: Pyre.Flows.Task})
      end
    end
  end

  describe "FlowError" do
    test "can be constructed with all required fields" do
      event = %FlowError{
        flow_module: Pyre.Flows.Task,
        description: "test",
        run_dir: "/tmp/run",
        error: :timeout,
        elapsed_ms: 500
      }

      assert event.error == :timeout
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, fn ->
        struct!(FlowError, %{flow_module: Pyre.Flows.Task})
      end
    end
  end

  describe "ActionStarted" do
    test "can be constructed with all required fields" do
      event = %ActionStarted{
        action_module: Pyre.Actions.Generalist,
        stage_name: :generalist,
        model: "anthropic:claude-sonnet-4",
        params: %{feature_description: "test"}
      }

      assert event.stage_name == :generalist
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, fn ->
        struct!(ActionStarted, %{action_module: Pyre.Actions.Generalist})
      end
    end
  end

  describe "ActionCompleted" do
    test "can be constructed with all required fields" do
      event = %ActionCompleted{
        action_module: Pyre.Actions.Generalist,
        stage_name: :generalist,
        result: %{task_output: "done"},
        model: "anthropic:claude-sonnet-4",
        elapsed_ms: 2000
      }

      assert event.result == %{task_output: "done"}
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, fn ->
        struct!(ActionCompleted, %{action_module: Pyre.Actions.Generalist})
      end
    end
  end

  describe "ActionError" do
    test "can be constructed with all required fields" do
      event = %ActionError{
        action_module: Pyre.Actions.Generalist,
        stage_name: :generalist,
        error: :api_error,
        model: "anthropic:claude-sonnet-4",
        elapsed_ms: 100
      }

      assert event.error == :api_error
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, fn ->
        struct!(ActionError, %{action_module: Pyre.Actions.Generalist})
      end
    end
  end

  describe "LLMCallCompleted" do
    test "can be constructed with all required fields" do
      event = %LLMCallCompleted{
        backend: Pyre.LLM.ReqLLM,
        model: "anthropic:claude-sonnet-4",
        call_type: :generate,
        elapsed_ms: 300
      }

      assert event.call_type == :generate
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, fn ->
        struct!(LLMCallCompleted, %{backend: Pyre.LLM.ReqLLM})
      end
    end
  end

  describe "LLMCallError" do
    test "can be constructed with all required fields" do
      event = %LLMCallError{
        backend: Pyre.LLM.ReqLLM,
        model: "anthropic:claude-sonnet-4",
        error: :rate_limited,
        call_type: :stream,
        elapsed_ms: 50
      }

      assert event.error == :rate_limited
      assert event.call_type == :stream
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, fn ->
        struct!(LLMCallError, %{backend: Pyre.LLM.ReqLLM})
      end
    end
  end
end
