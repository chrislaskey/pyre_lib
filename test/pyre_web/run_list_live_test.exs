defmodule PyreWeb.RunListLiveTest do
  use PyreWeb.Test.ConnCase, async: false

  alias PyreWeb.Test.AgentMock

  setup do
    pubsub = PyreWeb.Test.PubSub
    {:ok, agent} = Agent.start_link(fn -> [] end)
    {:ok, worker} = start_mock_worker(pubsub, "test-live", agent)

    on_exit(fn ->
      AgentMock.teardown()
      Process.exit(worker, :normal)
    end)

    %{response_agent: agent}
  end

  test "renders the runs list page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre/runs")
    assert html =~ "Runs"
    assert html =~ "New Run"
  end

  test "shows runs and links to show page", %{conn: conn, response_agent: agent} do
    set_responses(agent, [
      "Req.",
      "Design.",
      "Impl.",
      "Tests.",
      "APPROVE\n\nGood.",
      "## Branch Name\n\nfeature/page\n\n## Commit Message\n\nfeat: add page\n\n## PR Title\n\nAdd page\n\n## PR Body\n\nAdds page."
    ])

    tmp_dir = Path.join(System.tmp_dir!(), "pyre_list_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp_dir, "priv/pyre/features"))

    {:ok, id} =
      Pyre.RunServer.start_run("List test feature",
        workflow: :overnight_feature,
        llm: Pyre.LLM.Mock,
        streaming: false,
        project_dir: tmp_dir,
        connection_id: "test-live"
      )

    wait_for_status(id, :complete)

    {:ok, _view, html} = live(conn, "/pyre/runs")
    assert html =~ id
    assert html =~ "List test feature"
    assert html =~ ~s|href="/pyre/runs/#{id}"|

    File.rm_rf!(tmp_dir)
  end

  test "back link points to home", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre/runs")
    assert html =~ ~s|href="/pyre"|
    assert html =~ "Home"
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
