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
              <h3 class="card-title text-sm">{presence.name}</h3>
            </div>

            <div class="text-xs text-base-content/60 space-y-0.5 mt-1">
              <p :if={presence[:cpu_brand] || presence[:cpu_cores]}>
                {presence[:cpu_brand] || "CPU"}{if presence[:cpu_cores],
                  do: " (#{presence[:cpu_cores]} cores)"}
              </p>
              <p :if={presence[:memory_gb]}>
                {presence[:memory_gb]} GB memory
              </p>
              <p :if={presence[:os_version]}>
                {presence[:os_version]}
              </p>
            </div>

            <div class="mt-2">
              <button
                phx-click="action_execute_commands_clone_repo"
                phx-value-connection-id={presence[:connection_id]}
                class="btn btn-sm btn-outline btn-primary"
              >
                Clone Repo
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
