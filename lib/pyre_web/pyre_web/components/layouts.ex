defmodule PyreWeb.Components.Layouts do
  @moduledoc false
  use PyreWeb.Web, :html

  @themes [
    "light",
    "dark",
    "retro",
    "cyberpunk",
    "valentine",
    "aqua",
    "dracula",
    "nord",
    "synthwave",
    "night",
    "coffee",
    "forest",
    "cupcake",
    "pastel",
    "caramellatte",
    "sunset"
  ]

  attr :current_page, :atom, required: true
  attr :prefix, :string, required: true
  attr :uri, :string, default: ""
  attr :breadcrumbs, :list, default: []
  slot :inner_block, required: true

  def page_layout(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen">
      <div id="pyre-notifications" phx-hook="Notifications"></div>
      <.page_header current_page={@current_page} prefix={@prefix} uri={@uri} />
      <.mobile_menu current_page={@current_page} prefix={@prefix} uri={@uri} />
      <div class="flex flex-1">
        <.sidebar current_page={@current_page} prefix={@prefix} uri={@uri} />
        <div class="flex-1 p-8 overflow-y-auto">
          <.breadcrumbs items={@breadcrumbs} prefix={@prefix} />
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders DaisyUI breadcrumbs. A home icon is always shown as the first crumb.
  Each item is a map with `:label` and an optional `:path`.
  Items with a `:path` render as navigate links; the last item (no path) renders as plain text.
  """
  attr :items, :list, required: true
  attr :prefix, :string, required: true

  def breadcrumbs(assigns) do
    home = if assigns[:prefix] == "", do: "/", else: assigns[:prefix]
    assigns = assign(assigns, :home, home)

    ~H"""
    <div class="breadcrumbs text-sm text-base-content/60 mb-4">
      <ul>
        <li>
          <.link class="flex gap-x-1" navigate={@home}>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="size-4"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25"
              />
            </svg>
            Home
          </.link>
        </li>
        <li :for={item <- @items}>
          <.link :if={item[:path]} navigate={item.path}>{item.label}</.link>
          <span :if={!item[:path]}>{item.label}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :current_page, :atom, required: true
  attr :prefix, :string, required: true
  attr :uri, :string, default: ""

  def page_header(assigns) do
    ~H"""
    <.page_header_container>
      <div class="flex items-center gap-x-2">
        <.mobile_menu_button uri={@uri} />
        <.page_header_logo prefix={@prefix} />
      </div>
      <div class="flex items-center gap-x-1">
        <.link
          patch={toggle_sidebar_path(@uri)}
          class="btn btn-ghost btn-sm btn-square hidden sm:flex"
          aria-label="Toggle sidebar"
          title="Toggle sidebar"
        >
          <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" class="size-5">
            <rect
              x="2.74709"
              y="4.77295"
              width="18.5"
              height="14.5"
              rx="1.25"
              stroke="currentColor"
              stroke-width="1.5"
            />
            <path
              d="M8.49709 5.02295V19.0229"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="square"
            />
            <path
              d="M4.99709 8.52295L5.99709 8.52295"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
            />
            <path
              d="M4.99709 10.5229L5.99709 10.5229"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
            />
            <path
              d="M4.99709 12.5229L5.99709 12.5229"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
            />
          </svg>
        </.link>
        <.notification_bell />
        <.theme_selector />
      </div>
    </.page_header_container>
    """
  end

  attr :prefix, :string, required: true

  def page_header_logo(assigns) do
    ~H"""
    <.link class="w-48 tracking-widest text-2xl font-light uppercase" navigate={@prefix}>
      Pyre
    </.link>
    """
  end

  slot :inner_block, required: true

  def page_header_container(assigns) do
    ~H"""
    <div class="w-full h-16 px-6 items-center flex justify-between shadow-sm relative z-10">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :current_page, :atom, required: true
  attr :prefix, :string, required: true
  attr :uri, :string, required: true

  def sidebar(assigns) do
    ~H"""
    <nav
      :if={!sidebar_collapsed?(@uri)}
      class="hidden md:flex md:flex-col w-56 shrink-0 bg-base-200 border-r border-base-300 py-5 px-3"
      style="min-height: calc(100vh - 4rem);"
    >
      <div class="w-full flex-1">
        <.nav_links current_page={@current_page} prefix={@prefix} />
      </div>
      {PyreWeb.Config.call(:sidebar_footer, [assigns])}
    </nav>
    """
  end

  attr :uri, :string, required: true

  def mobile_menu_button(assigns) do
    ~H"""
    <.link
      patch={toggle_menu_path(@uri)}
      class="btn btn-ghost btn-sm btn-square flex md:hidden"
      aria-label="Open menu"
      title="Open menu"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
        class="size-5"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"
        />
      </svg>
    </.link>
    """
  end

  attr :current_page, :atom, required: true
  attr :prefix, :string, required: true
  attr :uri, :string, required: true

  def mobile_menu(assigns) do
    ~H"""
    <div :if={menu_open?(@uri)} class="fixed inset-0 z-50 bg-base-100 flex flex-col md:hidden">
      <div class="flex items-center gap-x-2 h-16 px-6 shadow-sm">
        <.link
          patch={toggle_menu_path(@uri)}
          class="btn btn-ghost btn-sm btn-square"
          aria-label="Close menu"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="size-5"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
          </svg>
        </.link>
        <.link class="tracking-widest text-2xl font-light uppercase" navigate={@prefix}>
          Pyre
        </.link>
      </div>
      <div class="flex-1 overflow-y-auto py-6 px-3 bg-base-200 flex-1 border-t border-base-300">
        <.nav_links current_page={@current_page} prefix={@prefix} />
        {PyreWeb.Config.call(:sidebar_footer, [assigns])}
      </div>
    </div>
    """
  end

  attr :current_page, :atom, required: true
  attr :prefix, :string, required: true

  def nav_links(assigns) do
    ~H"""
    <ul class="menu w-full gap-y-1">
      <li>
        <.link
          navigate={"#{@prefix}/runs/new"}
          class={[
            "!justify-start mb-1 btn btn-sm btn-secondary h-9",
            @current_page == :new_run && "active"
          ]}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="currentColor"
            class="size-4"
          >
            <path
              fill-rule="evenodd"
              d="M9 4.5a.75.75 0 0 1 .721.544l.813 2.846a3.75 3.75 0 0 0 2.576 2.576l2.846.813a.75.75 0 0 1 0 1.442l-2.846.813a3.75 3.75 0 0 0-2.576 2.576l-.813 2.846a.75.75 0 0 1-1.442 0l-.813-2.846a3.75 3.75 0 0 0-2.576-2.576l-2.846-.813a.75.75 0 0 1 0-1.442l2.846-.813A3.75 3.75 0 0 0 7.466 7.89l.813-2.846A.75.75 0 0 1 9 4.5ZM18 1.5a.75.75 0 0 1 .728.568l.258 1.036c.236.94.97 1.674 1.91 1.91l1.036.258a.75.75 0 0 1 0 1.456l-1.036.258c-.94.236-1.674.97-1.91 1.91l-.258 1.036a.75.75 0 0 1-1.456 0l-.258-1.036a2.625 2.625 0 0 0-1.91-1.91l-1.036-.258a.75.75 0 0 1 0-1.456l1.036-.258a2.625 2.625 0 0 0 1.91-1.91l.258-1.036A.75.75 0 0 1 18 1.5ZM16.5 15a.75.75 0 0 1 .712.513l.394 1.183c.15.447.5.799.948.948l1.183.395a.75.75 0 0 1 0 1.422l-1.183.395c-.447.15-.799.5-.948.948l-.395 1.183a.75.75 0 0 1-1.422 0l-.395-1.183a1.5 1.5 0 0 0-.948-.948l-1.183-.395a.75.75 0 0 1 0-1.422l1.183-.395c.447-.15.799-.5.948-.948l.395-1.183A.75.75 0 0 1 16.5 15Z"
              clip-rule="evenodd"
            />
          </svg>
          New Run
        </.link>
      </li>
      <li>
        <.link
          navigate={if @prefix != "", do: @prefix, else: "/"}
          class={@current_page == :home && "active"}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="size-4"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25"
            />
          </svg>
          Home
        </.link>
      </li>
      <li>
        <.link
          navigate={"#{@prefix}/connected-apps"}
          class={@current_page in [:connected_apps] && "active"}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
            class="size-4"
          >
            <path d="M12.232 4.232a2.5 2.5 0 0 1 3.536 3.536l-1.225 1.224a.75.75 0 0 0 1.061 1.06l1.224-1.224a4 4 0 0 0-5.656-5.656l-3 3a4 4 0 0 0 .225 5.865.75.75 0 0 0 .977-1.138 2.5 2.5 0 0 1-.142-3.667l3-3Z" />
            <path d="M11.603 7.963a.75.75 0 0 0-.977 1.138 2.5 2.5 0 0 1 .142 3.667l-3 3a2.5 2.5 0 0 1-3.536-3.536l1.225-1.224a.75.75 0 0 0-1.061-1.06l-1.224 1.224a4 4 0 0 0 5.656 5.656l3-3a4 4 0 0 0-.225-5.865Z" />
          </svg>
          Connected Apps
        </.link>
      </li>
      <li>
        <.link
          navigate={"#{@prefix}/runs"}
          class={@current_page in [:runs, :run_show] && "active"}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
            class="size-4"
          >
            <path
              fill-rule="evenodd"
              d="M6 4.75A.75.75 0 0 1 6.75 4h10.5a.75.75 0 0 1 0 1.5H6.75A.75.75 0 0 1 6 4.75ZM6 10a.75.75 0 0 1 .75-.75h10.5a.75.75 0 0 1 0 1.5H6.75A.75.75 0 0 1 6 10Zm0 5.25a.75.75 0 0 1 .75-.75h10.5a.75.75 0 0 1 0 1.5H6.75a.75.75 0 0 1-.75-.75ZM1.99 4.75a1 1 0 0 1 1-1H3a1 1 0 0 1 1 1v.01a1 1 0 0 1-1 1h-.01a1 1 0 0 1-1-1v-.01ZM1.99 15.25a1 1 0 0 1 1-1H3a1 1 0 0 1 1 1v.01a1 1 0 0 1-1 1h-.01a1 1 0 0 1-1-1v-.01ZM1.99 10a1 1 0 0 1 1-1H3a1 1 0 0 1 1 1v.01a1 1 0 0 1-1 1h-.01a1 1 0 0 1-1-1V10Z"
              clip-rule="evenodd"
            />
          </svg>
          Runs
        </.link>
      </li>
      <li>
        <.link
          navigate={"#{@prefix}/settings"}
          class={@current_page in [:settings] && "active"}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
            class="size-4"
          >
            <path
              fill-rule="evenodd"
              d="M7.84 1.804A1 1 0 0 1 8.82 1h2.36a1 1 0 0 1 .98.804l.331 1.652a6.993 6.993 0 0 1 1.929 1.115l1.598-.54a1 1 0 0 1 1.186.447l1.18 2.044a1 1 0 0 1-.205 1.251l-1.267 1.113a7.047 7.047 0 0 1 0 2.228l1.267 1.113a1 1 0 0 1 .206 1.25l-1.18 2.045a1 1 0 0 1-1.187.447l-1.598-.54a6.993 6.993 0 0 1-1.929 1.115l-.33 1.652a1 1 0 0 1-.98.804H8.82a1 1 0 0 1-.98-.804l-.331-1.652a6.993 6.993 0 0 1-1.929-1.115l-1.598.54a1 1 0 0 1-1.186-.447l-1.18-2.044a1 1 0 0 1 .205-1.251l1.267-1.114a7.05 7.05 0 0 1 0-2.227L1.821 7.773a1 1 0 0 1-.206-1.25l1.18-2.045a1 1 0 0 1 1.187-.447l1.598.54A6.992 6.992 0 0 1 7.51 3.456l.33-1.652ZM10 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z"
              clip-rule="evenodd"
            />
          </svg>
          Settings
        </.link>
      </li>
      {PyreWeb.Config.call(:additional_nav_links, [assigns])}
    </ul>
    """
  end

  def notification_bell(assigns) do
    ~H"""
    <button
      id="pyre-notification-bell"
      type="button"
      class="btn btn-ghost btn-sm"
      title="Enable desktop notifications"
    >
      <span class="relative">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="size-4"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0"
          />
        </svg>
        <span
          data-notification-indicator
          class="hidden absolute -top-1 -right-1 w-2 h-2 rounded-full bg-success"
        >
        </span>
      </span>
    </button>
    """
  end

  attr :themes, :list, default: @themes

  def theme_selector(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
          class="size-4"
        >
          <path
            fill-rule="evenodd"
            d="M3.5 2A1.5 1.5 0 0 0 2 3.5V5c0 .69.56 1.25 1.25 1.25H5.5c.69 0 1.25-.56 1.25-1.25V3.5c0-.83-.67-1.5-1.5-1.5h-1.75ZM2 9.25c0-.69.56-1.25 1.25-1.25H5.5c.69 0 1.25.56 1.25 1.25V11c0 .83-.67 1.5-1.5 1.5H3.5A1.5 1.5 0 0 1 2 11V9.25ZM9.25 2c-.69 0-1.25.56-1.25 1.25V5.5c0 .69.56 1.25 1.25 1.25H11c.83 0 1.5-.67 1.5-1.5V3.5c0-.83-.67-1.5-1.5-1.5H9.25ZM8 9.25c0-.69.56-1.25 1.25-1.25H11c.83 0 1.5.67 1.5 1.5V11c0 .83-.67 1.5-1.5 1.5H9.25C8.56 12.5 8 11.94 8 11.25V9.25ZM15 2c-.83 0-1.5.67-1.5 1.5V5c0 .69.56 1.25 1.25 1.25H17c.69 0 1.25-.56 1.25-1.25V3.5c0-.83-.67-1.5-1.5-1.5h-1.75ZM13.5 9.25c0-.69.56-1.25 1.25-1.25H17c.69 0 1.25.56 1.25 1.25V11c0 .83-.67 1.5-1.5 1.5h-1.75c-.83 0-1.5-.67-1.5-1.5V9.25ZM3.5 14c-.83 0-1.5.67-1.5 1.5V17c0 .69.56 1.25 1.25 1.25H5.5c.69 0 1.25-.56 1.25-1.25v-1.75c0-.83-.67-1.5-1.5-1.5H3.5ZM8 15.25c0-.69.56-1.25 1.25-1.25H11c.83 0 1.5.67 1.5 1.5V17c0 .69-.56 1.25-1.25 1.25H9.25C8.56 18.25 8 17.69 8 17v-1.75ZM15 14c-.83 0-1.5.67-1.5 1.5V17c0 .69.56 1.25 1.25 1.25H17c.69 0 1.25-.56 1.25-1.25v-1.75c0-.83-.67-1.5-1.5-1.5h-1.75Z"
            clip-rule="evenodd"
          />
        </svg>
        Theme
        <svg
          width="12px"
          height="12px"
          class="inline-block h-2 w-2 fill-current opacity-60"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 2048 2048"
        >
          <path d="M1799 349l242 241-1017 1017L7 590l242-241 775 775 775-775z"></path>
        </svg>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content bg-base-300 rounded-box z-10 w-52 p-2 shadow-2xl max-h-80 overflow-y-auto"
      >
        <li :for={theme <- @themes}>
          <input
            type="radio"
            name="theme-dropdown"
            class="theme-controller w-full btn btn-sm btn-block btn-ghost justify-start"
            aria-label={String.capitalize(theme)}
            value={theme}
          />
        </li>
      </ul>
    </div>
    """
  end

  slot :inner_block, required: true

  def h1(assigns) do
    ~H"""
    <h1 class="text-3xl font-light">
      {render_slot(@inner_block)}
    </h1>
    """
  end

  slot :inner_block, required: true

  def h2(assigns) do
    ~H"""
    <h2 class="text-2xl font-light">
      {render_slot(@inner_block)}
    </h2>
    """
  end

  defp sidebar_collapsed?(uri) when uri in ["", nil], do: false

  defp sidebar_collapsed?(uri) do
    uri
    |> URI.parse()
    |> Map.get(:query)
    |> case do
      nil -> %{}
      q -> URI.decode_query(q)
    end
    |> Map.get("sidebar") == "collapsed"
  end

  defp toggle_sidebar_path(uri) when uri in ["", nil], do: "?sidebar=collapsed"

  defp toggle_sidebar_path(uri) do
    parsed = URI.parse(uri)
    params = URI.decode_query(parsed.query || "")

    new_nav = if params["sidebar"] == "collapsed", do: "open", else: "collapsed"
    new_params = Map.put(params, "sidebar", new_nav)
    new_query = URI.encode_query(new_params)

    %URI{parsed | query: new_query} |> URI.to_string()
  end

  defp menu_open?(uri) when uri in ["", nil], do: false

  defp menu_open?(uri) do
    uri
    |> URI.parse()
    |> Map.get(:query)
    |> case do
      nil -> %{}
      q -> URI.decode_query(q)
    end
    |> Map.get("menu") == "open"
  end

  defp toggle_menu_path(uri) when uri in ["", nil], do: "?menu=open"

  defp toggle_menu_path(uri) do
    parsed = URI.parse(uri)
    params = URI.decode_query(parsed.query || "")

    new_menu = if params["menu"] == "open", do: "hidden", else: "open"
    new_params = Map.put(params, "menu", new_menu)
    new_query = URI.encode_query(new_params)

    %URI{parsed | query: new_query} |> URI.to_string()
  end
end
