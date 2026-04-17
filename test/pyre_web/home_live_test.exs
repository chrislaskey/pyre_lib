defmodule PyreWeb.HomeLiveTest do
  use PyreWeb.Test.ConnCase, async: true

  test "renders the home page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre")
    assert html =~ "Pyre"
    assert html =~ "Multi-agent LLM framework"
  end

  test "links to the new run page with correct prefix", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre")
    assert html =~ ~s|href="/pyre/runs/new"|
    assert html =~ "Start a New Run"
  end

  test "links to the runs list page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre")
    assert html =~ ~s|href="/pyre/runs"|
    assert html =~ "View Runs"
  end

  test "displays pyre version", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre")

    version =
      case Application.spec(:pyre, :vsn) do
        nil -> "unknown"
        vsn -> to_string(vsn)
      end

    assert html =~ version
  end
end
