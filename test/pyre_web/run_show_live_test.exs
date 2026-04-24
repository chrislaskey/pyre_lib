defmodule PyreWeb.RunShowLiveTest do
  use PyreWeb.Test.ConnCase, async: false

  alias PyreWeb.Test.AgentMock

  setup do
    pubsub = PyreWeb.Test.PubSub
    {:ok, agent} = Agent.start_link(fn -> [] end)
    {:ok, worker} = start_mock_worker(pubsub, "test-show", agent)

    on_exit(fn ->
      AgentMock.teardown()
      Process.exit(worker, :normal)
    end)

    %{response_agent: agent}
  end

  test "shows run output page with buffered entries", %{conn: conn, response_agent: agent} do
    set_responses(agent, ["Req.", "Design.", "Impl.", "Tests.", "APPROVE\n\nGood."])

    tmp_dir = Path.join(System.tmp_dir!(), "pyre_show_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("Build a test page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-show"
      )

    wait_for_status(id, :complete)

    {:ok, _view, html} = live(conn, "/pyre/runs/#{id}")
    assert html =~ id
    assert html =~ "output-stream"
    assert html =~ "Complete"

    File.rm_rf!(tmp_dir)
  end

  test "redirects to /runs for unknown run ID", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/pyre/runs"}}} =
             live(conn, "/pyre/runs/deadbeef")
  end

  test "handles PubSub events for stream updates", %{conn: conn, response_agent: agent} do
    set_responses(agent, ["Req.", "Design.", "Impl.", "Tests.", "APPROVE\n\nGood."])

    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_show_pubsub_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("Build a test page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-show"
      )

    {:ok, view, _html} = live(conn, "/pyre/runs/#{id}")

    # Send a status update — the LiveView refetches state, which updates the
    # status badge in the assigns (not in a stream)
    send(view.pid, {:pyre_run_status, id, :complete})
    html = render(view)
    assert html =~ "Complete"

    wait_for_status(id, :complete)
    File.rm_rf!(tmp_dir)
  end

  test "shows feature description", %{conn: conn, response_agent: agent} do
    set_responses(agent, ["Req.", "Design.", "Impl.", "Tests.", "APPROVE\n\nGood."])

    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_show_desc_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("Build a products listing page",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-show"
      )

    {:ok, _view, html} = live(conn, "/pyre/runs/#{id}")
    assert html =~ "Build a products listing page"

    wait_for_status(id, :complete)
    File.rm_rf!(tmp_dir)
  end

  test "back link points to runs list", %{conn: conn, response_agent: agent} do
    set_responses(agent, ["Req.", "Design.", "Impl.", "Tests.", "APPROVE\n\nGood."])

    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_show_back_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("Test",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-show"
      )

    {:ok, _view, html} = live(conn, "/pyre/runs/#{id}")
    assert html =~ ~s|href="/pyre/runs"|
    assert html =~ "Runs"

    wait_for_status(id, :complete)
    File.rm_rf!(tmp_dir)
  end

  test "renders feature phases for feature workflow", %{conn: conn, response_agent: agent} do
    set_responses(agent, [
      "Architecture plan.",
      "## Branch Name\n\nfeature/change\n\n## PR Title\n\nChange\n\n## PR Body\n\nChange.",
      "Implementation done."
    ])

    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_show_feat_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("Build a test page",
        workflow: :feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        interactive_stages: [],
        connection_id: "test-show"
      )

    wait_for_status(id, :complete)

    {:ok, _view, html} = live(conn, "/pyre/runs/#{id}")
    # Feature phases are present in the workflow panel
    assert html =~ "Architecture"
    assert html =~ "PR Setup"
    assert html =~ "Engineering"
    # Overnight run phases should NOT appear
    refute html =~ "Shipping"

    File.rm_rf!(tmp_dir)
  end

  test "renders chat workflow phase display", %{conn: conn, response_agent: agent} do
    set_responses(agent, ["Generalist output."])

    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_show_chat_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("Help me debug this",
        workflow: :chat,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        interactive_stages: [],
        connection_id: "test-show"
      )

    wait_for_status(id, :complete)

    {:ok, _view, html} = live(conn, "/pyre/runs/#{id}")
    assert html =~ "Generalist"
    refute html =~ "Architecture"
    refute html =~ "Shipping"

    File.rm_rf!(tmp_dir)
  end

  test "renders prototype workflow phase display", %{conn: conn, response_agent: agent} do
    set_responses(agent, ["Prototype output."])

    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_show_proto_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("Build a prototype",
        workflow: :prototype,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        interactive_stages: [],
        connection_id: "test-show"
      )

    wait_for_status(id, :complete)

    {:ok, _view, html} = live(conn, "/pyre/runs/#{id}")
    assert html =~ "Prototyping"
    refute html =~ "Architecture"
    refute html =~ "Generalist"

    File.rm_rf!(tmp_dir)
  end

  test "renders task workflow phase display", %{conn: conn, response_agent: agent} do
    set_responses(agent, ["Task output."])

    tmp_dir =
      Path.join(System.tmp_dir!(), "pyre_show_task_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("Run a task",
        workflow: :task,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-show"
      )

    wait_for_status(id, :complete)

    {:ok, _view, html} = live(conn, "/pyre/runs/#{id}")
    assert html =~ "Task"
    refute html =~ "Architecture"
    refute html =~ "Shipping"

    File.rm_rf!(tmp_dir)
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

    Process.sleep(10)
    {:ok, pid}
  end

  defp mock_worker_loop(pubsub, response_agent) do
    receive do
      {:action, execution_id, %{"action" => "reserve"}} ->
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

      {:action_continue, _exec_id, _payload} ->
        mock_worker_loop(pubsub, response_agent)

      {:action_finish, _exec_id} ->
        mock_worker_loop(pubsub, response_agent)
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
end
