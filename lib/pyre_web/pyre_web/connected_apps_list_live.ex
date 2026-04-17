defmodule PyreWeb.ConnectedAppsListLive do
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

    {:ok,
     socket
     |> assign(page_title: "Connected Apps — Pyre", presences: presences)
     |> assign(execution: nil, action_output: [])}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end

  @impl true
  def handle_event(
        "action_execute_commands_clone_repo",
        %{"connection-id" => connection_id},
        socket
      ) do
    execution_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    pubsub = pubsub()

    # Subscribe to output from this execution
    Phoenix.PubSub.subscribe(pubsub, "pyre:action:output:#{execution_id}")

    action = %{
      type: "execute_commands",
      payload: %{
        commands: [
          "mkdir -p ~/code/pyre-runtime",
          "git -C ~/code/pyre-runtime/pyre pull || git clone https://github.com/chrislaskey/pyre ~/code/pyre-runtime/pyre"
        ]
      }
    }

    # Send to the connection's channel via PubSub
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
    presences = update_presences(socket.assigns.presences, diff)
    {:noreply, assign(socket, :presences, presences)}
  end

  def handle_info({:action_output, payload}, socket) do
    line = payload["line"] || ""
    {:noreply, assign(socket, action_output: socket.assigns.action_output ++ [line])}
  end

  def handle_info({:action_complete, payload}, socket) do
    execution = socket.assigns.execution
    exit_codes = payload["exit_codes"] || []
    status = if Enum.all?(exit_codes, &(&1 == 0)), do: :complete, else: :error
    {:noreply, assign(socket, execution: %{execution | status: status})}
  end

  defp pubsub do
    Application.get_env(:pyre, :pubsub, Phoenix.PubSub)
  end

  defp update_presences(presences, %{joins: joins, leaves: leaves}) do
    leave_ids = Map.keys(leaves) |> MapSet.new()

    remaining = Enum.reject(presences, &MapSet.member?(leave_ids, &1.connection_id))

    new =
      Enum.map(joins, fn {connection_id, %{metas: [meta | _]}} ->
        Map.put(meta, :connection_id, connection_id)
      end)

    remaining ++ new
  end
end
