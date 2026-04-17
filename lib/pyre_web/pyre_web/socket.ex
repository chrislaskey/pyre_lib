defmodule PyreWeb.Socket do
  @moduledoc """
  Phoenix Socket for Pyre native app connections.

  Routes channel topic requests to the appropriate channel modules.

  ## Host App Setup

  This socket must be mounted in the host application's endpoint:

      # lib/my_app_web/endpoint.ex
      socket "/pyre", PyreWeb.Socket,
        websocket: [connect_info: [:peer_data, :x_headers]]

  The path (`/pyre`) should match the path used when mounting `pyre_web`
  in the router.

  ## Presence

  To enable connection presence tracking (showing connected native apps on the
  homepage), add `PyreWeb.Presence` to the host app's supervision tree:

      children = [
        # ... existing children ...
        PyreWeb.Presence
      ]

  Presence reuses the PubSub server from `config :pyre, :pubsub` — no
  additional configuration is needed.
  """
  use Phoenix.Socket

  require Logger

  channel "pyre:*", PyreWeb.Channel

  @impl true
  def connect(params, socket, connect_info) do
    case PyreWeb.Config.authorize(:authorize_socket_connect, [params, connect_info]) do
      :ok ->
        connection_id = params["connection_id"]

        socket =
          socket
          |> assign(:params, params)
          |> assign(:connection_id, connection_id)

        {:ok, socket}

      {:error, _reason} ->
        :error
    end
  end

  @impl true
  def id(socket) do
    case socket.assigns[:connection_id] do
      nil -> nil
      connection_id -> "pyre_connection:#{connection_id}"
    end
  end
end
