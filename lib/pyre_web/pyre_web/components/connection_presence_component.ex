defmodule PyreWeb.ConnectionPresenceComponent do
  use PyreWeb.Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@presences == []} class="text-base-content/50 text-sm">
        No connections
      </div>

      <div :if={@presences != []} class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <div :for={presence <- @presences} class="card card-bordered bg-base-100 shadow-sm">
          <div class="card-body p-4">
            <div class="flex items-center gap-2">
              <span class="inline-block w-2 h-2 rounded-full bg-success"></span>
              <h3 class="card-title text-sm">{meta(presence, :name)}</h3>
            </div>

            <div class="text-xs text-base-content/60 space-y-1 mt-1">
              <.capacity_line
                :if={meta(presence, :max_capacity)}
                available={meta(presence, :available_capacity)}
                max={meta(presence, :max_capacity)}
              />

              <p :if={meta(presence, :backends) != nil and meta(presence, :backends) != []}>
                <span class="font-medium text-base-content/70">Backends:</span>
                {Enum.join(meta(presence, :backends), ", ")}
              </p>

              <p :if={
                meta(presence, :enabled_workflows) != nil and
                  meta(presence, :enabled_workflows) != []
              }>
                <span class="font-medium text-base-content/70">Workflows:</span>
                {Enum.join(meta(presence, :enabled_workflows), ", ")}
              </p>
            </div>

            <div class="mt-2">
              <button
                phx-click="test_connection"
                phx-value-connection-id={presence[:connection_id]}
                class="btn btn-sm btn-outline btn-primary"
              >
                Test Connection
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp capacity_line(assigns) do
    available = assigns.available || 0
    max = assigns.max || 0
    percentage = if max > 0, do: round(available / max * 100), else: 0

    assigns = assign(assigns, available: available, max: max, percentage: percentage)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="font-medium text-base-content/70">Capacity:</span>
      <span>{@available} / {@max} available</span>
      <div class="w-12 h-1.5 bg-base-300 rounded-full overflow-hidden">
        <div
          class={[
            "h-full rounded-full",
            @percentage > 50 && "bg-success",
            (@percentage > 0 and @percentage <= 50) && "bg-warning",
            @percentage == 0 && "bg-error"
          ]}
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp meta(presence, key) when is_atom(key) do
    Map.get(presence, to_string(key)) || Map.get(presence, key)
  end
end
