defmodule PyreWeb.SettingsLive do
  @moduledoc """
  Settings index page with links to configuration pages.
  """
  use PyreWeb.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings")}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end
end
