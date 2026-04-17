defmodule PyreWeb.WebhookPlug do
  @moduledoc """
  Caches the raw request body for webhook signature verification.

  Must be used as a custom `:body_reader` for `Plug.Parsers` on the
  webhook route. Stores the raw body in `conn.private[:raw_body]`.

  ## Setup

  In the consuming app's endpoint:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Jason,
        body_reader: {PyreWeb.WebhookPlug, :read_body, []}
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = update_raw_body(conn, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = update_raw_body(conn, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_raw_body(conn, chunk) do
    existing = conn.private[:raw_body] || ""
    Plug.Conn.put_private(conn, :raw_body, existing <> chunk)
  end
end
