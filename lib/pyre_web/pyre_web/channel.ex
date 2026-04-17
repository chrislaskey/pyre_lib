defmodule PyreWeb.Channel do
  @moduledoc """
  Phoenix Channel for Pyre native app communication.

  Handles channel joins and incoming messages from the Pyre native app
  over the `pyre:*` topic namespace.

  ## Topics

  - `pyre:hello` — basic connectivity check, returns a greeting on join
  - `pyre:connections` — presence tracking for connected native apps
  """
  use Phoenix.Channel

  require Logger

  @impl true
  def join("pyre:hello" = topic, _params, socket) do
    case PyreWeb.Config.authorize(:authorize_channel_join, [topic, socket]) do
      :ok -> {:ok, %{message: "hello world"}, socket}
      {:error, reason} -> {:error, %{reason: reason}}
    end
  end

  def join("pyre:connections" = topic, params, socket) do
    case PyreWeb.Config.authorize(:authorize_channel_join, [topic, socket]) do
      {:error, reason} ->
        {:error, %{reason: reason}}

      :ok ->
        join_connections(params, socket)
    end
  end

  def join("pyre:" <> _topic, _params, _socket) do
    {:error, %{reason: "unknown topic"}}
  end

  defp join_connections(params, socket) do
    send(self(), :after_join)

    connection_id =
      socket.assigns[:connection_id] || params["connection_id"] || socket.id || "anonymous"

    metadata = Map.drop(params, ["connection_id"])

    # Subscribe to actions targeted at this specific connection
    if pubsub = Application.get_env(:pyre, :pubsub) do
      Phoenix.PubSub.subscribe(pubsub, "pyre:action:input:#{connection_id}")
    end

    socket =
      socket
      |> assign(:connection_id, connection_id)
      |> assign(:connection_metadata, metadata)

    {:ok, %{message: "connected"}, socket}
  end

  @impl true
  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{message: "pong"}}, socket}
  end

  # Receive streamed output from the client and broadcast to the execution's PubSub topic
  def handle_in("action_output", %{"execution_id" => id} = payload, socket) do
    if pubsub = Application.get_env(:pyre, :pubsub) do
      Phoenix.PubSub.broadcast(pubsub, "pyre:action:output:#{id}", {:action_output, payload})
    end

    {:noreply, socket}
  end

  def handle_in("update_metadata", params, socket) do
    if PyreWeb.Presence.running?() do
      PyreWeb.Presence.update(socket, socket.assigns.connection_id, fn existing_meta ->
        Map.merge(existing_meta, params)
      end)
    end

    {:reply, :ok, socket}
  end

  def handle_in("action_complete", %{"execution_id" => id} = payload, socket) do
    if pubsub = Application.get_env(:pyre, :pubsub) do
      Phoenix.PubSub.broadcast(pubsub, "pyre:action:output:#{id}", {:action_complete, payload})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    if PyreWeb.Presence.running?() do
      connection_id = socket.assigns[:connection_id] || socket.id || "anonymous"
      metadata = socket.assigns[:connection_metadata] || %{}

      {:ok, _} = PyreWeb.Presence.track(socket, connection_id, metadata)
    end

    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"} = msg, socket) do
    push(socket, "presence_diff", msg.payload)
    {:noreply, socket}
  end

  # Forward an action from PubSub (originating from HomeLive) to the connected client
  def handle_info({:action, execution_id, action}, socket) do
    push(socket, "action", Map.put(action, :execution_id, execution_id))
    {:noreply, socket}
  end
end
