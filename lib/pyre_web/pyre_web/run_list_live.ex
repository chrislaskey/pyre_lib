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

    runs = PyreWeb.Config.call(:list_runs, []) || []

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
    runs = PyreWeb.Config.call(:list_runs, []) || []

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

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_time(_), do: ""
end
