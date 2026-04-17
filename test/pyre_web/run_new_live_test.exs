defmodule PyreWeb.RunNewLiveTest do
  use PyreWeb.Test.ConnCase, async: true

  test "renders the new run form", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre/runs/new")
    assert html =~ "New Run"
    assert html =~ "Prompt"
    assert html =~ "Start run"
  end

  test "back link points to prefixed home path", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre/runs/new")
    assert html =~ ~s|href="/pyre"|
    assert html =~ "Home"
  end

  test "empty submit shows error flash", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pyre/runs/new")

    html =
      view
      |> element("form")
      |> render_submit(%{"run" => %{"feature_description" => ""}})

    assert html =~ "cannot be empty"
  end

  test "renders workflow selector with Chat default", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre/runs/new")
    assert html =~ "Chat"
    assert html =~ "Feature"
    assert html =~ "Code Review"
    assert html =~ "Overnight Feature"
    assert html =~ "Generalist"
  end

  test "switching to overnight feature changes stages", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pyre/runs/new")

    html = render_click(view, "select_workflow", %{"workflow" => "overnight_feature"})

    assert html =~ "Programmer"
    assert html =~ "Test Writer"
    refute html =~ "Software Architect"
    refute html =~ "Software Engineer"
    refute html =~ "Generalist"
  end

  test "switching to chat workflow shows generalist stage", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pyre/runs/new")

    # Switch away first
    render_click(view, "select_workflow", %{"workflow" => "overnight_feature"})
    html = render_click(view, "select_workflow", %{"workflow" => "chat"})

    assert html =~ "Generalist"
    refute html =~ "Product Manager"
    refute html =~ "Programmer"
  end

  test "renders LLM backend selector with API default", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre/runs/new")
    assert html =~ "LLM Backend"
    assert html =~ "API (ReqLLM)"
    assert html =~ "Claude CLI"
  end

  test "switching to Claude CLI backend", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pyre/runs/new")

    html = render_click(view, "select_backend", %{"backend" => "claude_cli"})

    assert html =~ "Claude CLI"
    assert html =~ "claude_cli"
  end

  test "switching to feature workflow shows feature stages", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pyre/runs/new")

    html = render_click(view, "select_workflow", %{"workflow" => "feature"})

    assert html =~ "Software Architect"
    assert html =~ "Software Engineer"
    assert html =~ "PR Setup"
    refute html =~ "Programmer"
    refute html =~ "Test Writer"
    refute html =~ "Generalist"
  end

  test "switching to code review workflow shows reviewer stage", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pyre/runs/new")

    html = render_click(view, "select_workflow", %{"workflow" => "code_review"})

    assert html =~ "PR Reviewer"
    refute html =~ "Software Architect"
    refute html =~ "Generalist"
  end

  test "switching to prototype workflow shows prototype engineer stage", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pyre/runs/new")

    html = render_click(view, "select_workflow", %{"workflow" => "prototype"})

    assert html =~ "Prototype Engineer"
    refute html =~ "Software Architect"
    refute html =~ "Generalist"
  end

  test "switching to task workflow shows generalist stage", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pyre/runs/new")

    html = render_click(view, "select_workflow", %{"workflow" => "task"})

    assert html =~ "Generalist"
    refute html =~ "Software Architect"
    refute html =~ "Prototype Engineer"
  end

  test "renders prototype and task in workflow selector", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/pyre/runs/new")
    assert html =~ "Prototype"
    assert html =~ "Task"
  end
end
