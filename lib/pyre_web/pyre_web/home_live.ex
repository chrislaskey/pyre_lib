defmodule PyreWeb.HomeLive do
  @moduledoc """
  Landing page for the PyreWeb interface.
  """
  use PyreWeb.Web, :live_view

  @presence_topic "pyre:connections"

  @impl true
  def mount(_params, _session, socket) do
    presences =
      if connected?(socket) and PyreWeb.Presence.running?() do
        Phoenix.PubSub.subscribe(pubsub(), @presence_topic)
        PyreWeb.Presence.list_connections()
      else
        []
      end

    workflows = apply(Pyre.Config, :list_workflows, [])
    capacity = Pyre.WorkflowAvailability.capacity_by_type(presences, workflows)

    {:ok,
     socket
     |> assign(
       page_title: "Pyre",
       presences: presences,
       workflows: workflows,
       capacity_by_type: capacity
     )
     |> assign(execution: nil, action_output: [])}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end

  @impl true
  def handle_event("test_connection", %{"connection-id" => connection_id}, socket) do
    execution_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    pubsub = pubsub()

    Phoenix.PubSub.subscribe(pubsub, "pyre:action:output:#{execution_id}")

    action = %{
      "action" => "test_connection",
      "payload" => %{}
    }

    Phoenix.PubSub.broadcast(
      pubsub,
      "pyre:action:input:#{connection_id}",
      {:action, execution_id, action}
    )

    socket =
      socket
      |> assign(
        execution: %{
          id: execution_id,
          connection_id: connection_id,
          status: :running
        }
      )
      |> assign(action_output: [])

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    presences = PyreWeb.Presence.apply_diff(socket.assigns.presences, diff)

    capacity =
      Pyre.WorkflowAvailability.capacity_by_type(presences, socket.assigns.workflows)

    {:noreply, assign(socket, presences: presences, capacity_by_type: capacity)}
  end

  def handle_info({:action_output, payload}, socket) do
    content = payload["content"] || payload["line"] || ""
    {:noreply, assign(socket, action_output: socket.assigns.action_output ++ [content])}
  end

  def handle_info({:action_complete, payload}, socket) do
    execution = socket.assigns.execution

    status =
      case payload do
        %{"status" => "ok"} -> :complete
        %{"status" => "error"} -> :error
        _ -> :complete
      end

    content = payload["result"]["message"] || payload["result_text"]

    socket =
      if content do
        assign(socket, action_output: socket.assigns.action_output ++ [content])
      else
        socket
      end

    {:noreply, assign(socket, execution: %{execution | status: status})}
  end

  defp pyre_version do
    case Application.spec(:pyre, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end

  defp pubsub do
    Application.get_env(:pyre, :pubsub, Phoenix.PubSub)
  end

end
