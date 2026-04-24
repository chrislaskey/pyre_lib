defmodule Pyre.RunServerTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  setup do
    # Start a local PubSub for testing
    pubsub = Pyre.Test.PubSub

    case GenServer.whereis(pubsub) do
      nil -> start_supervised!({Phoenix.PubSub, name: pubsub})
      _pid -> :ok
    end

    Application.put_env(:pyre, :pubsub, pubsub)

    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_run_server_test_#{System.unique_integer([:positive])}")

    features_dir = Path.join(tmp_dir, "priv/pyre/features")
    File.mkdir_p!(features_dir)

    # Start the mock worker
    {:ok, agent} = Agent.start_link(fn -> [] end)
    {:ok, worker} = start_mock_worker(pubsub, "test-conn", agent)

    on_exit(fn ->
      Application.delete_env(:pyre, :pubsub)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir, pubsub: pubsub, response_agent: agent, worker: worker}
  end

  defp set_responses(agent, responses) do
    Agent.update(agent, fn _ -> responses end)
  end

  defp start_mock_worker(pubsub, connection_id, response_agent) do
    pid =
      spawn_link(fn ->
        Phoenix.PubSub.subscribe(pubsub, "pyre:action:input:#{connection_id}")
        mock_worker_loop(pubsub, response_agent)
      end)

    # Give the subscription time to register
    Process.sleep(10)
    {:ok, pid}
  end

  defp mock_worker_loop(pubsub, response_agent) do
    receive do
      {:action, execution_id, %{"action" => "reserve"}} ->
        # ACK the reservation immediately
        Phoenix.PubSub.broadcast(
          pubsub,
          "pyre:action:output:#{execution_id}",
          {:action_output,
           %{"execution_id" => execution_id, "type" => "ack", "status" => "accepted"}}
        )

        mock_worker_loop(pubsub, response_agent)

      {:action, execution_id, _payload} ->
        response =
          Agent.get_and_update(response_agent, fn
            [r | rest] -> {r, rest}
            [] -> {"Mock response (exhausted)", []}
          end)

        Phoenix.PubSub.broadcast(
          pubsub,
          "pyre:action:output:#{execution_id}",
          {:action_complete,
           %{"execution_id" => execution_id, "status" => "ok", "result_text" => response}}
        )

        mock_worker_loop(pubsub, response_agent)

      {:action_continue, _execution_id, _payload} ->
        # Interactive continue — respond again
        mock_worker_loop(pubsub, response_agent)

      {:action_finish, _execution_id} ->
        # Reservation release or interactive finish — no response needed
        mock_worker_loop(pubsub, response_agent)
    after
      30_000 -> :timeout
    end
  end

  test "start_run/2 returns {:ok, id} where id is 8-char hex", %{
    tmp_dir: tmp_dir,
    response_agent: agent
  } do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    assert is_binary(id)
    assert String.length(id) == 8
    assert Regex.match?(~r/^[0-9a-f]{8}$/, id)

    # Wait for the run to finish
    wait_for_status(id, :complete)
  end

  test "get_state/1 returns state with correct fields", %{tmp_dir: tmp_dir, response_agent: agent} do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.id == id
    assert state.status in [:reserving, :running, :complete]
    assert state.feature_description == "Build a page"
    assert %DateTime{} = state.started_at

    wait_for_status(id, :complete)
  end

  test "get_log/1 returns buffered entries", %{tmp_dir: tmp_dir, response_agent: agent} do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    wait_for_status(id, :complete)

    {:ok, log} = Pyre.RunServer.get_log(id)
    assert is_list(log)
    refute Enum.empty?(log)
    assert Enum.all?(log, &(is_map(&1) and Map.has_key?(&1, :id)))
  end

  test "list_runs/0 includes started run with summary", %{tmp_dir: tmp_dir, response_agent: agent} do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    runs = Pyre.RunServer.list_runs()
    run = Enum.find(runs, &(&1.id == id))

    assert run != nil
    assert run.feature_description == "Build a page"
    assert run.status in [:reserving, :running, :complete]

    wait_for_status(id, :complete)
  end

  test "PubSub events are received by subscribers", %{
    tmp_dir: tmp_dir,
    pubsub: pubsub,
    response_agent: agent
  } do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    Phoenix.PubSub.subscribe(pubsub, "pyre:runs:#{id}")

    wait_for_status(id, :complete)

    # We should have received at least some events
    messages = flush_messages()
    refute Enum.empty?(messages)
  end

  test "completed run has :complete status and 'Pipeline complete.' in log", %{
    tmp_dir: tmp_dir,
    response_agent: agent
  } do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    wait_for_status(id, :complete)

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.status == :complete
    assert %DateTime{} = state.completed_at

    {:ok, log} = Pyre.RunServer.get_log(id)
    contents = Enum.map(log, & &1.content)
    assert Enum.any?(contents, &(&1 == "Pipeline complete."))
  end

  test "skipped stages use best practices fallback", %{tmp_dir: tmp_dir, response_agent: agent} do
    # Only need 4 mock responses: product_manager, programmer, test_writer, shipper
    # designer and code_reviewer are skipped (skipped reviewer gives approve fallback → shipping)
    set_responses(agent, [
      "Req.",
      "Impl.",
      "Tests.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        skipped_stages: [:designing, :reviewing],
        connection_id: "test-conn"
      )

    wait_for_status(id, :complete)

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.status == :complete
    assert MapSet.member?(state.skipped_stages, :designing)
    assert MapSet.member?(state.skipped_stages, :reviewing)

    {:ok, log} = Pyre.RunServer.get_log(id)
    contents = Enum.map(log, & &1.content)
    assert Enum.any?(contents, &String.contains?(&1, "Skipping: designer"))
    assert Enum.any?(contents, &String.contains?(&1, "Skipping: code_reviewer"))
  end

  test "toggle_stage/2 adds and removes stages", %{tmp_dir: tmp_dir, response_agent: agent} do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    # Initially no skipped stages
    {:ok, skipped} = Pyre.RunServer.get_skipped_stages(id)
    assert MapSet.size(skipped) == 0

    # Toggle designing off
    :ok = Pyre.RunServer.toggle_stage(id, :designing)
    {:ok, skipped} = Pyre.RunServer.get_skipped_stages(id)
    assert MapSet.member?(skipped, :designing)

    # Toggle designing back on
    :ok = Pyre.RunServer.toggle_stage(id, :designing)
    {:ok, skipped} = Pyre.RunServer.get_skipped_stages(id)
    refute MapSet.member?(skipped, :designing)

    wait_for_status(id, :complete)
  end

  test "get_state/1 returns {:error, :not_found} for unknown ID" do
    assert {:error, :not_found} = Pyre.RunServer.get_state("deadbeef")
  end

  test "get_log/1 returns {:error, :not_found} for unknown ID" do
    assert {:error, :not_found} = Pyre.RunServer.get_log("deadbeef")
  end

  test "get_state/1 includes interactive_stages and waiting_for_input fields", %{
    tmp_dir: tmp_dir,
    response_agent: agent
  } do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert %MapSet{} = state.interactive_stages
    assert MapSet.size(state.interactive_stages) == 0
    assert state.waiting_for_input == false

    wait_for_status(id, :complete)
  end

  test "toggle_interactive_stage/2 adds and removes stages", %{
    tmp_dir: tmp_dir,
    response_agent: agent
  } do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert MapSet.size(state.interactive_stages) == 0

    # Toggle on
    :ok = Pyre.RunServer.toggle_interactive_stage(id, :designing)
    {:ok, state} = Pyre.RunServer.get_state(id)
    assert MapSet.member?(state.interactive_stages, :designing)

    # Toggle off
    :ok = Pyre.RunServer.toggle_interactive_stage(id, :designing)
    {:ok, state} = Pyre.RunServer.get_state(id)
    refute MapSet.member?(state.interactive_stages, :designing)

    wait_for_status(id, :complete)
  end

  test "send_reply/2 is a no-op when not waiting for input", %{
    tmp_dir: tmp_dir,
    response_agent: agent
  } do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    # Should not crash — guard ignores user_action when waiting_for_input == false
    assert :ok = Pyre.RunServer.send_reply(id, "some reply")
    assert :ok = Pyre.RunServer.continue_stage(id)

    wait_for_status(id, :complete)
  end

  test "interactive flow: send_reply unblocks waiting stage then continue advances", %{
    tmp_dir: tmp_dir,
    pubsub: pubsub,
    response_agent: _agent
  } do
    # For the interactive test, we need a special mock worker that handles
    # action_continue messages (re-dispatches results for resumed sessions)
    {:ok, interactive_agent} = Agent.start_link(fn -> [] end)

    # Stop existing worker and start interactive one
    {:ok, interactive_worker} =
      start_interactive_mock_worker(pubsub, "test-interactive", interactive_agent)

    set_responses(interactive_agent, [
      # architecting (interactive by default) — initial call
      "Architecture plan.",
      # architecting — resume call with user reply
      "Updated architecture plan with error handling.",
      # architecting — finalize call
      "Final architecture plan.",
      # pr_setup (non-interactive)
      "## Branch Name\n\nfeature/page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page.",
      # engineering (interactive by default) — initial call
      "Implementation summary.",
      # engineering — finalize call
      "Final implementation summary."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-interactive"
      )

    # Feature flow defaults to interactive architecting + engineering stages
    Phoenix.PubSub.subscribe(pubsub, "pyre:runs:#{id}")

    # Wait for the flow to reach waiting_for_input (architecting)
    assert wait_for_waiting(id), "Expected run to reach waiting_for_input state"

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.waiting_for_input == true

    # Send a reply — flow should resume and come back to waiting
    :ok = Pyre.RunServer.send_reply(id, "Can you add error states?")
    assert wait_for_waiting(id), "Expected run to re-enter waiting after reply"

    # Continue — flow should finalize and advance past architecting
    :ok = Pyre.RunServer.continue_stage(id)

    # Engineering is also interactive — wait for it
    assert wait_for_waiting(id), "Expected engineering to reach waiting_for_input"

    # Continue past engineering
    :ok = Pyre.RunServer.continue_stage(id)

    wait_for_status(id, :complete)

    {:ok, final_state} = Pyre.RunServer.get_state(id)
    assert final_state.status == :complete
    assert final_state.waiting_for_input == false

    Process.exit(interactive_worker, :normal)
  end

  test "toggle_interactive_stage/2 broadcasts pyre_interactive_stages", %{
    tmp_dir: tmp_dir,
    pubsub: pubsub,
    response_agent: agent
  } do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    Phoenix.PubSub.subscribe(pubsub, "pyre:runs:#{id}")

    :ok = Pyre.RunServer.toggle_interactive_stage(id, :designing)

    assert_receive {:pyre_interactive_stages, ^id, stages}, 1_000
    assert MapSet.member?(stages, :designing)
    # The run may block at designing (now interactive) waiting for user input,
    # so we only assert the broadcast here, not flow completion.
  end

  test "chat workflow uses default interactive stages", %{
    tmp_dir: tmp_dir,
    pubsub: pubsub,
    response_agent: _agent
  } do
    # Chat's interactive mock worker needs to handle continue/finish messages
    {:ok, chat_agent} = Agent.start_link(fn -> [] end)
    {:ok, chat_worker} = start_interactive_mock_worker(pubsub, "test-chat", chat_agent)

    set_responses(chat_agent, [
      "Generalist output."
      # Finalize response (not used since continue with 0 replies sends finish)
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Help me debug this",
        workflow: :chat,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-chat"
      )

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.workflow == :chat
    # Chat flow defaults to interactive generalist stage
    assert MapSet.member?(state.interactive_stages, :generalist)

    # The run will be waiting for input since generalist is interactive by default.
    # Continue to let it finish.
    assert wait_for_waiting(id), "Expected chat run to reach waiting_for_input"
    :ok = Pyre.RunServer.continue_stage(id)

    wait_for_status(id, :complete)

    {:ok, final_state} = Pyre.RunServer.get_state(id)
    assert final_state.status == :complete

    Process.exit(chat_worker, :normal)
  end

  test "prototype workflow uses default interactive stages", %{tmp_dir: tmp_dir, pubsub: pubsub} do
    {:ok, proto_agent} = Agent.start_link(fn -> [] end)
    {:ok, proto_worker} = start_interactive_mock_worker(pubsub, "test-proto", proto_agent)

    set_responses(proto_agent, [
      "Prototype output."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Build a prototype",
        workflow: :prototype,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-proto"
      )

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.workflow == :prototype
    # Prototype flow defaults to interactive prototyping stage
    assert MapSet.member?(state.interactive_stages, :prototyping)

    # The run will be waiting for input since prototyping is interactive by default.
    assert wait_for_waiting(id), "Expected prototype run to reach waiting_for_input"
    :ok = Pyre.RunServer.continue_stage(id)

    wait_for_status(id, :complete)

    {:ok, final_state} = Pyre.RunServer.get_state(id)
    assert final_state.status == :complete

    Process.exit(proto_worker, :normal)
  end

  test "task workflow is not interactive by default", %{tmp_dir: tmp_dir, response_agent: agent} do
    set_responses(agent, [
      "Task output."
    ])

    {:ok, id} =
      Pyre.RunServer.start_run("Add pagination",
        workflow: :task,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.workflow == :task
    # Task flow is NOT interactive by default
    assert MapSet.size(state.interactive_stages) == 0

    wait_for_status(id, :complete)

    {:ok, final_state} = Pyre.RunServer.get_state(id)
    assert final_state.status == :complete
  end

  test "connection_id is stored in run state", %{tmp_dir: tmp_dir, response_agent: agent} do
    set_responses(agent, ["Task output."])

    {:ok, id} =
      Pyre.RunServer.start_run("Add pagination",
        workflow: :task,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
      )

    wait_for_status(id, :complete)

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.connection_id == "test-conn"
  end

  # --- Reservation tests ---

  test "RunServer dispatches reserve and awaits ACK before starting flow", %{
    tmp_dir: tmp_dir,
    response_agent: agent
  } do
    set_responses(agent, ["Task output."])

    {:ok, id} =
      Pyre.RunServer.start_run("Add pagination",
        workflow: :task,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn"
        # No reservation_id — RunServer handles it
      )

    wait_for_status(id, :complete)

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.status == :complete
    # Reservation cleared after completion
    assert state.reservation_id == nil
    assert state.owns_reservation == false
  end

  test "pre-provided reservation_id skips reserve dispatch", %{
    tmp_dir: tmp_dir,
    response_agent: agent
  } do
    set_responses(agent, ["Task output."])

    {:ok, id} =
      Pyre.RunServer.start_run("Add pagination",
        workflow: :task,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-conn",
        reservation_id: "pre-existing-reservation"
      )

    wait_for_status(id, :complete)

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.status == :complete
    # RunServer did not own the reservation — caller is responsible for release
    assert state.owns_reservation == false
  end

  test "reservation timeout transitions to error", %{tmp_dir: tmp_dir} do
    # Use a connection_id with no subscriber — no one will ACK
    {:ok, id} =
      Pyre.RunServer.start_run("Add pagination",
        workflow: :task,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "no-one-listening"
      )

    wait_for_status(id, :error, 15_000)

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.status == :error

    {:ok, log} = Pyre.RunServer.get_log(id)
    contents = Enum.map(log, & &1.content)
    assert Enum.any?(contents, &String.contains?(&1, "timeout"))
  end

  test "stop_run during reservation phase cancels and cleans up", %{tmp_dir: tmp_dir} do
    # Use a connection_id with no subscriber — will stay in :reserving
    {:ok, id} =
      Pyre.RunServer.start_run("Add pagination",
        workflow: :task,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "no-one-listening"
      )

    # Brief sleep to let RunServer reach :reserving status
    Process.sleep(50)

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.status == :reserving

    :ok = Pyre.RunServer.stop_run(id)

    {:ok, state} = Pyre.RunServer.get_state(id)
    assert state.status == :stopped
  end

  # --- Helpers ---

  defp start_interactive_mock_worker(pubsub, connection_id, response_agent) do
    pid =
      spawn_link(fn ->
        Phoenix.PubSub.subscribe(pubsub, "pyre:action:input:#{connection_id}")
        interactive_worker_loop(pubsub, response_agent, nil)
      end)

    Process.sleep(10)
    {:ok, pid}
  end

  defp interactive_worker_loop(pubsub, response_agent, _current_execution_id) do
    receive do
      {:action, execution_id, %{"action" => "reserve"}} ->
        # ACK the reservation immediately
        Phoenix.PubSub.broadcast(
          pubsub,
          "pyre:action:output:#{execution_id}",
          {:action_output,
           %{"execution_id" => execution_id, "type" => "ack", "status" => "accepted"}}
        )

        interactive_worker_loop(pubsub, response_agent, nil)

      {:action, execution_id, _payload} ->
        response =
          Agent.get_and_update(response_agent, fn
            [r | rest] -> {r, rest}
            [] -> {"Mock response (exhausted)", []}
          end)

        Phoenix.PubSub.broadcast(
          pubsub,
          "pyre:action:output:#{execution_id}",
          {:action_complete,
           %{"execution_id" => execution_id, "status" => "ok", "result_text" => response}}
        )

        interactive_worker_loop(pubsub, response_agent, execution_id)

      {:action_continue, execution_id, _payload} ->
        # Respond to the continue with the next mock response
        response =
          Agent.get_and_update(response_agent, fn
            [r | rest] -> {r, rest}
            [] -> {"Mock response (exhausted)", []}
          end)

        Phoenix.PubSub.broadcast(
          pubsub,
          "pyre:action:output:#{execution_id}",
          {:action_complete,
           %{"execution_id" => execution_id, "status" => "ok", "result_text" => response}}
        )

        interactive_worker_loop(pubsub, response_agent, execution_id)

      {:action_finish, _execution_id} ->
        interactive_worker_loop(pubsub, response_agent, nil)
    after
      30_000 -> :timeout
    end
  end

  defp wait_for_status(id, expected_status, timeout \\ 15_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      case Pyre.RunServer.get_state(id) do
        {:ok, %{status: ^expected_status}} ->
          :done

        {:ok, _} ->
          if System.monotonic_time(:millisecond) > deadline do
            flunk("Timed out waiting for status #{expected_status}")
          end

          Process.sleep(50)
          :continue

        {:error, :not_found} ->
          flunk("Run #{id} not found")
      end
    end)
    |> Enum.find(&(&1 == :done))
  end

  defp wait_for_waiting(id, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    result =
      Stream.repeatedly(fn ->
        case Pyre.RunServer.get_state(id) do
          {:ok, %{waiting_for_input: true}} ->
            :done

          {:ok, %{status: status}} when status in [:complete, :stopped, :error] ->
            :not_waiting

          {:ok, _} ->
            if System.monotonic_time(:millisecond) > deadline do
              :timeout
            else
              Process.sleep(50)
              :continue
            end

          _ ->
            Process.sleep(50)
            :continue
        end
      end)
      |> Enum.find(fn r -> r != :continue end)

    result == :done
  end

  defp flush_messages do
    flush_messages([])
  end

  defp flush_messages(acc) do
    receive do
      msg -> flush_messages(acc ++ [msg])
    after
      100 -> acc
    end
  end
end
