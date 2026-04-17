defmodule PyreWeb.Assets do
  @moduledoc false
  import Plug.Conn

  # Embed Phoenix framework JS files at compile time
  phoenix_js_paths =
    for app <- [:phoenix, :phoenix_html, :phoenix_live_view] do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

  # Embed PyreWeb JS at compile time
  js_path = Path.join(__DIR__, "../../../dist/js/app.js")
  @external_resource js_path

  @js """
  #{for path <- phoenix_js_paths, do: path |> File.read!() |> String.replace("//# sourceMappingURL=", "// ")}
  #{File.read!(js_path)}
  """

  @hash Base.encode16(:crypto.hash(:md5, @js), case: :lower)

  def init(asset) when asset in [:js], do: asset

  def call(conn, :js) do
    conn
    |> put_resp_header("content-type", "text/javascript")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, @js)
    |> halt()
  end

  @doc false
  def current_hash(:js), do: @hash
end
