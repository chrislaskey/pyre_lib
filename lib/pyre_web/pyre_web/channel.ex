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
  def join("pyre:hello" = topic, params, socket) do
    token = params["token"]

    with :ok <- validate_service_token(token),
         :ok <- Pyre.Config.authorize(:authorize_channel_join, [topic, params, socket]) do
      {:ok, %{message: "hello world"}, socket}
    else
      {:error, reason} -> {:error, %{reason: reason}}
    end
  end

  def join("pyre:connections" = topic, params, socket) do
    token = params["token"]

    with :ok <- validate_service_token(token),
         :ok <- Pyre.Config.authorize(:authorize_channel_join, [topic, params, socket]) do
      join_connections(params, socket)
    else
      {:error, reason} -> {:error, %{reason: reason}}
    end
  end

  def join("pyre:" <> _topic, _params, _socket) do
    {:error, %{reason: "unknown topic"}}
  end

  defp join_connections(params, socket) do
    send(self(), :after_join)

    connection_id =
      socket.assigns[:connection_id] || params["connection_id"] || socket.id || "anonymous"

    metadata = Map.drop(params, ["connection_id", "token"])

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

  defp validate_service_token(token) do
    cond do
      is_binary(token) and Pyre.Config.call(:websocket_service_token_valid?, [token]) ->
        :ok

      true ->
        Logger.warning("[PyreWeb.Channel] Invalid or missing service token on join")
        {:error, "unauthorized"}
    end
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

  def handle_in("action_result", %{"execution_id" => id} = payload, socket) do
    if pubsub = Application.get_env(:pyre, :pubsub) do
      Phoenix.PubSub.broadcast(pubsub, "pyre:action:output:#{id}", {:action_result, payload})
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

  # Forward continuation message from flow Task process to the connected client
  def handle_info({:action_continue, execution_id, payload}, socket) do
    push(socket, "action_continue", Map.put(payload, "execution_id", execution_id))
    {:noreply, socket}
  end

  # Forward finish signal from flow Task process to the connected client
  def handle_info({:action_finish, execution_id}, socket) do
    push(socket, "action_finish", %{"execution_id" => execution_id})
    {:noreply, socket}
  end
end
