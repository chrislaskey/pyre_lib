defmodule PyreWeb.RunListLive do
  @moduledoc """
  LiveView listing all Pyre pipeline runs.
  """
  use PyreWeb.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      if pubsub = Application.get_env(:pyre, :pubsub) do
        Phoenix.PubSub.subscribe(pubsub, "pyre:runs")
      end
    end

    runs = Pyre.Config.call(:list_runs, []) || []

    socket =
      assign(socket,
        page_title: "Runs — Pyre",
        runs: runs
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end

  @impl true
  def handle_info({:pyre_run_status, id, status}, socket) do
    runs = Pyre.Config.call(:list_runs, []) || []

    socket =
      socket
      |> assign(runs: runs)
      |> maybe_notify_status(id, status)

    {:noreply, socket}
  end

  defp maybe_notify_status(socket, run_id, :complete) do
    push_event(socket, "pyre:notify", %{
      title: "Run completed",
      body: "Run #{run_id} finished successfully",
      level: "success",
      tag: "pyre-run-#{run_id}"
    })
  end

  defp maybe_notify_status(socket, run_id, :error) do
    push_event(socket, "pyre:notify", %{
      title: "Run failed",
      body: "Run #{run_id} encountered an error",
      level: "error",
      tag: "pyre-run-#{run_id}"
    })
  end

  defp maybe_notify_status(socket, _run_id, _status), do: socket

  defp status_badge_class(:running), do: "badge-warning"
  defp status_badge_class(:complete), do: "badge-success"
  defp status_badge_class(:stopped), do: "badge-neutral"
  defp status_badge_class(:error), do: "badge-error"
  defp status_badge_class(_), do: "badge-neutral"

  defp status_label(:running), do: "Running"
  defp status_label(:complete), do: "Complete"
  defp status_label(:stopped), do: "Stopped"
  defp status_label(:error), do: "Error"
  defp status_label(_), do: "Unknown"

  defp workflow_label(nil), do: ""

  defp workflow_label(workflow) when is_atom(workflow) do
    workflow
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp workflow_label(_), do: ""

  defp phase_label(:planning), do: "Planning"
  defp phase_label(:designing), do: "Design"
  defp phase_label(:implementing), do: "Implementation"
  defp phase_label(:testing), do: "Testing"
  defp phase_label(:reviewing), do: "Review"
  defp phase_label(:shipping), do: "Shipping"
  defp phase_label(:complete), do: "Complete"
  defp phase_label(_), do: ""

  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."

  defp timestamp(%{dt: nil} = assigns), do: ~H""

  defp timestamp(assigns) do
    ~H"""
    <div>{relative_time(@dt)}</div>
    <div class="text-xs text-base-content/50">{format_utc(@dt)}</div>
    """
  end

  defp relative_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 0 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      diff < 2_592_000 -> "#{div(diff, 604_800)}w ago"
      true -> format_utc(dt)
    end
  end

  defp format_utc(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_duration(%DateTime{} = started, %DateTime{} = completed) do
    seconds = DateTime.diff(completed, started, :second)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end

  defp format_duration(%DateTime{} = started, nil) do
    seconds = DateTime.diff(DateTime.utc_now(), started, :second)

    cond do
      seconds < 60 -> "#{seconds}s..."
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s..."
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m..."
    end
  end

  defp format_duration(_, _), do: ""
end
