defmodule PyreWeb.RunListLiveTest do
  use PyreWeb.Test.ConnCase, async: false

  alias PyreWeb.Test.AgentMock

  setup do
    on_exit(fn -> AgentMock.teardown() end)
    :ok
  end

  test "renders the runs list page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre/runs")
    assert html =~ "Runs"
    assert html =~ "New Run"
  end

  test "shows runs and links to show page", %{conn: conn} do
    AgentMock.setup([
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
        llm: AgentMock,
        streaming: false,
        project_dir: tmp_dir
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
