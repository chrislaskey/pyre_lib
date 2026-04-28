defmodule PyreWeb.Socket do
  @moduledoc """
  Phoenix Socket for Pyre native app connections.

  Routes channel topic requests to the appropriate channel modules.

  ## Host App Setup

  This socket must be mounted in the host application's endpoint:

      # lib/my_app_web/endpoint.ex
      socket "/", PyreWeb.Socket,
        websocket: [connect_info: [:peer_data, :x_headers]]

  The mount path should match the path used when mounting `pyre_web` in the
  router. For example, if you mount at a subpath:

      socket "/pyre", PyreWeb.Socket, ...   # endpoint
      pyre_web "/pyre"                      # router

  Clients (pyre_client, pyre_native) must include the same prefix in their
  WebSocket URL — e.g., `ws://localhost:4000/pyre/websocket`.

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

  channel("pyre:*", PyreWeb.Channel)

  @impl true
  def connect(params, socket, connect_info) do
    x_headers = connect_info[:x_headers] || []
    token = :proplists.get_value("x-pyre-token", x_headers)

    with :ok <- validate_service_token(token),
         :ok <- Pyre.Config.authorize(:authorize_socket_connect, [params, connect_info]) do
      connection_id = params["connection_id"]

      socket =
        socket
        |> assign(:params, params)
        |> assign(:connection_id, connection_id)

      {:ok, socket}
    else
      {:error, _reason} -> :error
    end
  end

  defp validate_service_token(token) do
    cond do
      is_binary(token) and Pyre.Config.call(:websocket_service_token_valid?, [token]) ->
        :ok

      true ->
        Logger.warning("[PyreWeb.Socket] Invalid or missing service token on connect")
        {:error, :unauthorized}
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
