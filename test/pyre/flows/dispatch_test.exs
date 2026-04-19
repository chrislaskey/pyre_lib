defmodule Pyre.Flows.DispatchTest do
  use ExUnit.Case, async: false

  alias Pyre.Flows.Dispatch

  @moduletag :capture_log

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_dispatch_test_#{System.unique_integer([:positive])}")

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

  defp set_responses(agent, responses) do
    Agent.update(agent, fn _ -> responses end)
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

  defp make_context(dispatch_fn, overrides \\ %{}) do
    Map.merge(
      %{
        llm: Pyre.LLM.Mock,
        streaming: false,
        output_fn: fn _ -> :ok end,
        log_fn: fn _ -> :ok end,
        model_override: nil,
        verbose: false,
        dry_run: false,
        working_dir: ".",
        allowed_paths: [],
        add_dirs: [],
        allowed_commands: nil,
        skip_check_fn: nil,
        interactive_stage_fn: nil,
        await_user_action_fn: nil,
        session_ids: %{},
        connection_id: "test-conn",
        dispatch_fn: dispatch_fn,
        max_turns: 50
      },
      overrides
    )
  end

  defp make_state(run_dir) do
    %{
      phase: :tasking,
      feature_description: "Test feature",
      run_dir: run_dir,
      working_dir: ".",
      attachments: [],
      task_output: nil
    }
  end

  defp stage_config do
    %{
      stage_to_phase: %{generalist: :tasking},
      stage_model_tier: %{generalist: :standard},
      stage_artifact_info: %{generalist: {:task_output, "01_task_output"}},
      fallback_fn: fn :generalist, _state -> %{task_output: "fallback"} end
    }
  end

  describe "run_action/6" do
    test "dispatches and returns result", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn,
      response_agent: agent
    } do
      set_responses(agent, ["Generated output text."])

      context = make_context(dispatch_fn)

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_001")
        File.mkdir_p!(run_dir)

        state = make_state(run_dir)

        result =
          Dispatch.run_action(
            Pyre.Actions.Generalist,
            :generalist,
            state,
            context,
            %{feature_description: "Test", run_dir: run_dir, attachments: []},
            stage_config()
          )

        assert {:ok, %{task_output: output}} = result
        assert output =~ "Generated output text."
      end)
    end

    test "returns fallback when stage is skipped", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn
    } do
      context = make_context(dispatch_fn, %{skip_check_fn: fn _phase -> true end})

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_002")
        File.mkdir_p!(run_dir)

        state = make_state(run_dir)

        result =
          Dispatch.run_action(
            Pyre.Actions.Generalist,
            :generalist,
            state,
            context,
            %{feature_description: "Test", run_dir: run_dir, attachments: []},
            stage_config()
          )

        assert {:ok, %{task_output: "fallback"}} = result
      end)
    end

    test "returns empty map in dry_run mode", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn
    } do
      context = make_context(dispatch_fn, %{dry_run: true})

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_003")
        File.mkdir_p!(run_dir)

        state = make_state(run_dir)

        result =
          Dispatch.run_action(
            Pyre.Actions.Generalist,
            :generalist,
            state,
            context,
            %{feature_description: "Test", run_dir: run_dir, attachments: []},
            stage_config()
          )

        assert {:ok, %{}} = result
      end)
    end

    test "propagates error from dispatch", %{tmp_dir: tmp_dir} do
      error_dispatch_fn = fn _conn_id, exec_id, _payload ->
        caller = self()

        spawn(fn ->
          send(
            caller,
            {:action_complete,
             %{"execution_id" => exec_id, "status" => "error", "result_text" => "worker crashed"}}
          )
        end)
      end

      context = make_context(error_dispatch_fn)

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_004")
        File.mkdir_p!(run_dir)

        state = make_state(run_dir)

        result =
          Dispatch.run_action(
            Pyre.Actions.Generalist,
            :generalist,
            state,
            context,
            %{feature_description: "Test", run_dir: run_dir, attachments: []},
            stage_config()
          )

        assert {:error, _} = result
      end)
    end

    test "calls log_fn with stage start and completion messages", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn,
      response_agent: agent
    } do
      set_responses(agent, ["Output."])

      {:ok, log_agent} = Agent.start_link(fn -> [] end)

      context =
        make_context(dispatch_fn, %{
          log_fn: fn msg -> Agent.update(log_agent, &(&1 ++ [msg])) end
        })

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_005")
        File.mkdir_p!(run_dir)

        state = make_state(run_dir)

        Dispatch.run_action(
          Pyre.Actions.Generalist,
          :generalist,
          state,
          context,
          %{feature_description: "Test", run_dir: run_dir, attachments: []},
          stage_config()
        )

        msgs = Agent.get(log_agent, & &1)
        assert Enum.any?(msgs, &(&1 =~ "Stage: generalist"))
        assert Enum.any?(msgs, &(&1 =~ "Completed: generalist"))
      end)

      Agent.stop(log_agent)
    end

    test "emits verbose logs when verbose is true", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn,
      response_agent: agent
    } do
      set_responses(agent, ["Output."])

      {:ok, log_agent} = Agent.start_link(fn -> [] end)

      context =
        make_context(dispatch_fn, %{
          verbose: true,
          log_fn: fn msg -> Agent.update(log_agent, &(&1 ++ [msg])) end
        })

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_006")
        File.mkdir_p!(run_dir)

        state = make_state(run_dir)

        Dispatch.run_action(
          Pyre.Actions.Generalist,
          :generalist,
          state,
          context,
          %{feature_description: "Test", run_dir: run_dir, attachments: []},
          stage_config()
        )

        msgs = Agent.get(log_agent, & &1)
        assert Enum.any?(msgs, &(&1 =~ "[verbose] action:"))
        assert Enum.any?(msgs, &(&1 =~ "[verbose] run_dir:"))
      end)

      Agent.stop(log_agent)
    end
  end

  describe "post_process_result for verdict actions" do
    test "QAReviewer APPROVE verdict is parsed", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn,
      response_agent: agent
    } do
      set_responses(agent, ["APPROVE\n\nLooks great!"])

      config = %{
        stage_to_phase: %{code_reviewer: :reviewing},
        stage_model_tier: %{code_reviewer: :advanced},
        stage_artifact_info: %{code_reviewer: nil},
        fallback_fn: fn _, _ -> %{verdict: :approve, verdict_text: "Skipped"} end
      }

      context = make_context(dispatch_fn)

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_007")
        File.mkdir_p!(run_dir)

        state = %{
          phase: :reviewing,
          feature_description: "Test",
          run_dir: run_dir,
          working_dir: ".",
          attachments: [],
          requirements: "req",
          design: "design",
          implementation: "impl",
          tests: "tests",
          verdict: nil,
          verdict_text: nil,
          review_cycle: 1
        }

        result =
          Dispatch.run_action(
            Pyre.Actions.QAReviewer,
            :code_reviewer,
            state,
            context,
            %{
              feature_description: "Test",
              requirements: "req",
              design: "design",
              implementation: "impl",
              tests: "tests",
              run_dir: run_dir,
              review_cycle: 1,
              attachments: []
            },
            config
          )

        assert {:ok, result_map} = result
        assert result_map.verdict == :approve
        assert result_map.verdict_text =~ "APPROVE"
      end)
    end

    test "QAReviewer REJECT verdict is parsed", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn,
      response_agent: agent
    } do
      set_responses(agent, ["REJECT\n\nNeeds work."])

      config = %{
        stage_to_phase: %{code_reviewer: :reviewing},
        stage_model_tier: %{code_reviewer: :advanced},
        stage_artifact_info: %{code_reviewer: nil},
        fallback_fn: fn _, _ -> %{verdict: :approve, verdict_text: "Skipped"} end
      }

      context = make_context(dispatch_fn)

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_008")
        File.mkdir_p!(run_dir)

        state = %{
          phase: :reviewing,
          feature_description: "Test",
          run_dir: run_dir,
          working_dir: ".",
          attachments: [],
          requirements: "req",
          design: "design",
          implementation: "impl",
          tests: "tests",
          verdict: nil,
          verdict_text: nil,
          review_cycle: 1
        }

        result =
          Dispatch.run_action(
            Pyre.Actions.QAReviewer,
            :code_reviewer,
            state,
            context,
            %{
              feature_description: "Test",
              requirements: "req",
              design: "design",
              implementation: "impl",
              tests: "tests",
              run_dir: run_dir,
              review_cycle: 1,
              attachments: []
            },
            config
          )

        assert {:ok, result_map} = result
        assert result_map.verdict == :reject
        assert result_map.verdict_text =~ "REJECT"
      end)
    end
  end

  describe "git action post-processing" do
    test "git_pr_setup action returns pr_setup and branch_name", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn,
      response_agent: agent
    } do
      set_responses(agent, ["PR setup complete - created branch feature/test"])

      config = %{
        stage_to_phase: %{pr_setup: :pr_setup},
        stage_model_tier: %{pr_setup: :standard},
        stage_artifact_info: %{pr_setup: {:pr_setup, "04_pr_setup"}},
        fallback_fn: fn _, _ -> %{pr_setup: "fallback"} end
      }

      context =
        make_context(dispatch_fn, %{
          github: %{owner: "test", repo: "repo", token: "t", base_branch: "main"}
        })

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_009")
        File.mkdir_p!(run_dir)

        state = %{
          phase: :pr_setup,
          feature_description: "Test",
          run_dir: run_dir,
          working_dir: ".",
          attachments: [],
          architecture_plan: "plan"
        }

        result =
          Dispatch.run_action(
            Pyre.Actions.PRSetup,
            :pr_setup,
            state,
            context,
            %{
              feature_description: "Test",
              architecture_plan: "plan",
              run_dir: run_dir,
              attachments: []
            },
            config
          )

        assert {:ok, result_map} = result
        assert result_map.pr_setup =~ "PR setup complete"
        assert Map.has_key?(result_map, :branch_name)
      end)
    end

    test "git_ship action returns shipping_summary", %{
      tmp_dir: tmp_dir,
      dispatch_fn: dispatch_fn,
      response_agent: agent
    } do
      set_responses(agent, ["Shipped successfully - PR #42"])

      config = %{
        stage_to_phase: %{shipper: :shipping},
        stage_model_tier: %{shipper: :standard},
        stage_artifact_info: %{shipper: nil},
        fallback_fn: fn _, _ -> %{shipping_summary: "fallback"} end
      }

      context =
        make_context(dispatch_fn, %{
          github: %{owner: "test", repo: "repo", token: "t", base_branch: "main"}
        })

      with_cwd(tmp_dir, fn ->
        run_dir = Path.join(tmp_dir, "priv/pyre/features/test/run_010")
        File.mkdir_p!(run_dir)

        state = %{
          phase: :shipping,
          feature_description: "Test",
          run_dir: run_dir,
          working_dir: ".",
          attachments: [],
          requirements: "req",
          design: "design",
          implementation: "impl",
          tests: "tests",
          verdict_text: "APPROVE"
        }

        result =
          Dispatch.run_action(
            Pyre.Actions.Shipper,
            :shipper,
            state,
            context,
            %{
              feature_description: "Test",
              requirements: "req",
              design: "design",
              implementation: "impl",
              tests: "tests",
              verdict_text: "APPROVE",
              run_dir: run_dir,
              attachments: []
            },
            config
          )

        assert {:ok, result_map} = result
        assert result_map.shipping_summary =~ "Shipped successfully"
      end)
    end
  end
end
