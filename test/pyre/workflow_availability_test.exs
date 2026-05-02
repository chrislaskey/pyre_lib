defmodule Pyre.WorkflowAvailabilityTest do
  use ExUnit.Case, async: true

  alias Pyre.WorkflowAvailability

  @workflows [
    %{name: :chat, label: "Chat"},
    %{name: :feature, label: "Feature"},
    %{name: :task, label: "Task"}
  ]

  describe "capacity_by_type/2" do
    test "returns all types with zeros when no connections" do
      result = WorkflowAvailability.capacity_by_type([], @workflows)

      assert map_size(result) == 3

      for type <- ["chat", "feature", "task"] do
        assert %{available_capacity: 0, total_max_capacity: 0, connections: []} = result[type]
      end
    end

    test "general-purpose client appears in all workflow types" do
      connections = [
        %{
          connection_id: "abc",
          name: "local",
          status: "active",
          available_capacity: 2,
          max_capacity: 3,
          enabled_workflows: []
        }
      ]

      result = WorkflowAvailability.capacity_by_type(connections, @workflows)

      for type <- ["chat", "feature", "task"] do
        info = result[type]
        assert info.available_capacity == 2
        assert info.total_max_capacity == 3
        assert length(info.connections) == 1
        assert hd(info.connections).connection_id == "abc"
      end
    end

    test "specialist client appears only in declared types" do
      connections = [
        %{
          connection_id: "spec1",
          name: "task-worker",
          status: "active",
          available_capacity: 1,
          max_capacity: 2,
          enabled_workflows: ["task"]
        }
      ]

      result = WorkflowAvailability.capacity_by_type(connections, @workflows)

      assert result["task"].available_capacity == 1
      assert result["task"].total_max_capacity == 2
      assert length(result["task"].connections) == 1

      assert result["chat"].available_capacity == 0
      assert result["chat"].connections == []

      assert result["feature"].available_capacity == 0
      assert result["feature"].connections == []
    end

    test "busy worker (available: 0) still appears in connections list" do
      connections = [
        %{
          connection_id: "busy1",
          name: "busy-worker",
          status: "active",
          available_capacity: 0,
          max_capacity: 2,
          enabled_workflows: []
        }
      ]

      result = WorkflowAvailability.capacity_by_type(connections, @workflows)

      for type <- ["chat", "feature", "task"] do
        info = result[type]
        assert info.available_capacity == 0
        assert info.total_max_capacity == 2
        assert length(info.connections) == 1
        assert hd(info.connections).available_capacity == 0
        assert hd(info.connections).max_capacity == 2
      end
    end

    test "inactive worker is excluded from all types" do
      connections = [
        %{
          connection_id: "inactive1",
          name: "offline",
          status: "inactive",
          available_capacity: 5,
          max_capacity: 5,
          enabled_workflows: []
        }
      ]

      result = WorkflowAvailability.capacity_by_type(connections, @workflows)

      for type <- ["chat", "feature", "task"] do
        assert result[type].available_capacity == 0
        assert result[type].connections == []
      end
    end

    test "mixed general + specialist workers aggregate correctly" do
      connections = [
        %{
          connection_id: "gen1",
          name: "general",
          status: "active",
          available_capacity: 1,
          max_capacity: 2,
          enabled_workflows: []
        },
        %{
          connection_id: "spec1",
          name: "task-only",
          status: "active",
          available_capacity: 3,
          max_capacity: 3,
          enabled_workflows: ["task", "chat"]
        }
      ]

      result = WorkflowAvailability.capacity_by_type(connections, @workflows)

      # task: gen1 (1/2) + spec1 (3/3) = 4/5
      assert result["task"].available_capacity == 4
      assert result["task"].total_max_capacity == 5
      assert length(result["task"].connections) == 2

      # chat: gen1 (1/2) + spec1 (3/3) = 4/5
      assert result["chat"].available_capacity == 4
      assert result["chat"].total_max_capacity == 5
      assert length(result["chat"].connections) == 2

      # feature: only gen1 (1/2)
      assert result["feature"].available_capacity == 1
      assert result["feature"].total_max_capacity == 2
      assert length(result["feature"].connections) == 1
    end

    test "handles string-keyed metadata from presence" do
      connections = [
        %{
          "connection_id" => "str1",
          "name" => "string-keys",
          "status" => "active",
          "available_capacity" => 2,
          "max_capacity" => 3,
          "enabled_workflows" => ["chat"]
        }
      ]

      result = WorkflowAvailability.capacity_by_type(connections, @workflows)

      assert result["chat"].available_capacity == 2
      assert result["chat"].total_max_capacity == 3
      assert length(result["chat"].connections) == 1
      assert result["feature"].connections == []
    end

    test "multiple busy workers show correct totals" do
      connections = [
        %{
          connection_id: "w1",
          name: "worker-1",
          status: "active",
          available_capacity: 0,
          max_capacity: 2,
          enabled_workflows: []
        },
        %{
          connection_id: "w2",
          name: "worker-2",
          status: "active",
          available_capacity: 1,
          max_capacity: 3,
          enabled_workflows: []
        }
      ]

      result = WorkflowAvailability.capacity_by_type(connections, @workflows)

      for type <- ["chat", "feature", "task"] do
        info = result[type]
        assert info.available_capacity == 1
        assert info.total_max_capacity == 5
        assert length(info.connections) == 2
      end
    end
  end
end
