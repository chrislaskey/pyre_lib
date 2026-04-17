defmodule PyreWeb.LayoutView do
  @moduledoc false
  use PyreWeb.Web, :html

  embed_templates "layouts/*"

  def render("root.html", assigns), do: root(assigns)

  defp live_socket_path(conn) do
    [Enum.map(conn.script_name, &["/" | &1]) | conn.private.live_socket_path]
  end

  defp asset_path(conn, :js) do
    hash = PyreWeb.Assets.current_hash(:js)
    prefix = conn.private.phoenix_router.__pyre_web_prefix__()

    Phoenix.VerifiedRoutes.unverified_path(
      conn,
      conn.private.phoenix_router,
      "#{prefix}/js-#{hash}"
    )
  end
end
