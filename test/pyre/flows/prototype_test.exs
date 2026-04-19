defmodule Pyre.Flows.PrototypeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pyre.Flows.Prototype

  @moduletag :capture_log

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_proto_test_#{System.unique_integer([:positive])}")

    features_dir = Path.join(tmp_dir, "priv/pyre/features")
    File.mkdir_p!(features_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, agent} = Agent.start_link(fn -> [] end)

    dispatch_fn = fn _conn_id, exec_id, _payload ->
      caller = self()

      spawn(fn ->
        response =
          Agent.get_and_update(agent, fn
            [r | rest] -> {r, rest}
            [] -> {"Mock response (exhausted)", []}
          end)

        send(
          caller,
          {:action_complete,
           %{"execution_id" => exec_id, "status" => "ok", "result_text" => response}}
        )
      end)
    end

    %{tmp_dir: tmp_dir, dispatch_fn: dispatch_fn, response_agent: agent}
  end

  defp with_cwd(dir, fun) do
    original = File.cwd!()
    File.cd!(dir)

    try do
      fun.()
    after
      File.cd!(original)
    end
  end

  defp set_responses(agent, responses) do
    Agent.update(agent, fn _ -> responses end)
  end

  test "runs to completion with single mock response", %{
    tmp_dir: tmp_dir,
    dispatch_fn: dispatch_fn,
    response_agent: agent
  } do
    capture_io(fn ->
      set_responses(agent, [
        "### What Was Built\n- Products listing page prototype"
      ])

      result =
        with_cwd(tmp_dir, fn ->
          Prototype.run("Build a products listing page",
            llm: Pyre.LLM.Mock,
            streaming: false,
            project_dir: tmp_dir,
            connection_id: "test-conn",
            dispatch_fn: dispatch_fn
          )
        end)

      assert {:ok, state} = result
      assert state.phase == :complete
      assert state.prototype_output =~ "What Was Built"
    end)
  end

  test "dry run skips LLM calls", %{tmp_dir: tmp_dir, dispatch_fn: dispatch_fn} do
    capture_io(fn ->
      result =
        with_cwd(tmp_dir, fn ->
          Prototype.run("Build a prototype",
            llm: Pyre.LLM.Mock,
            streaming: false,
            dry_run: true,
            project_dir: tmp_dir,
            connection_id: "test-conn",
            dispatch_fn: dispatch_fn
          )
        end)

      assert {:ok, state} = result
      assert state.phase == :complete
    end)
  end

  test "propagates error from dispatch", %{tmp_dir: tmp_dir} do
    error_dispatch_fn = fn _conn_id, exec_id, _payload ->
      caller = self()

      spawn(fn ->
        send(
          caller,
          {:action_complete,
           %{"execution_id" => exec_id, "status" => "error", "result_text" => "execution failed"}}
        )
      end)
    end

    result =
      with_cwd(tmp_dir, fn ->
        Prototype.run("Build a prototype",
          llm: Pyre.LLM.Mock,
          streaming: false,
          project_dir: tmp_dir,
          log_fn: fn _ -> :ok end,
          connection_id: "test-conn",
          dispatch_fn: error_dispatch_fn
        )
      end)

    assert {:error, _} = result
  end

  test "default_interactive_stages/0 returns [:prototyping]" do
    assert Prototype.default_interactive_stages() == [:prototyping]
  end

  test "log_fn receives stage messages", %{
    tmp_dir: tmp_dir,
    dispatch_fn: dispatch_fn,
    response_agent: agent
  } do
    capture_io(fn ->
      set_responses(agent, [
        "Prototype completed."
      ])

      logs = Agent.start_link(fn -> [] end) |> elem(1)

      with_cwd(tmp_dir, fn ->
        Prototype.run("Build a prototype",
          llm: Pyre.LLM.Mock,
          streaming: false,
          project_dir: tmp_dir,
          log_fn: fn msg -> Agent.update(logs, &(&1 ++ [msg])) end,
          connection_id: "test-conn",
          dispatch_fn: dispatch_fn
        )
      end)

      log_messages = Agent.get(logs, & &1)
      assert Enum.any?(log_messages, &(&1 =~ "Run directory:"))
      assert Enum.any?(log_messages, &(&1 =~ "Stage: prototype_engineer"))

      Agent.stop(logs)
    end)
  end
end
