defmodule PyreWeb.Components.WorkflowCapacity do
  @moduledoc """
  Reusable UI components for displaying workflow capacity.

  Used by the default `Pyre.Config.render_workflow_capacities/1`
  and `render_workflow_capacity/1` callback implementations.
  Host apps can also use these components directly.
  """
  use Phoenix.Component

  @doc """
  Renders a grid of workflow capacity cards.

  ## Attributes

    * `capacity_by_type` - map from `Pyre.WorkflowAvailability.capacity_by_type/2`
    * `workflows` - list from `Pyre.Config.list_workflows/0`
  """
  attr :capacity_by_type, :map, required: true
  attr :workflows, :list, required: true

  def capacity_grid(assigns) do
    ~H"""
    <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <.capacity_card
        :for={workflow <- @workflows}
        workflow={workflow}
        info={Map.get(@capacity_by_type, to_string(workflow.name))}
      />
    </div>
    """
  end

  @doc """
  Renders a single workflow capacity card (for use in the grid).
  """
  attr :workflow, :map, required: true
  attr :info, :map, default: nil

  def capacity_card(assigns) do
    info = assigns.info || %{available_capacity: 0, total_max_capacity: 0, connections: []}
    assigns = assign(assigns, :info, info)

    ~H"""
    <div class="border border-base-300 rounded-lg p-3">
      <div class="flex items-center justify-between mb-1">
        <span class="text-sm font-medium">{@workflow.label}</span>
        <.capacity_badge info={@info} />
      </div>
      <.connection_summary info={@info} />
    </div>
    """
  end

  @doc """
  Renders an inline capacity summary for a single workflow type.
  Compact form for the run show page.

  ## Attributes

    * `info` - capacity_info map for this workflow type
    * `workflow_label` - display label (e.g., "Chat", "Feature")
  """
  attr :info, :map, required: true
  attr :workflow_label, :string, default: nil

  def capacity_inline(assigns) do
    ~H"""
    <div class="mb-4 flex items-center gap-2 text-sm text-base-content/60">
      <span :if={@workflow_label} class="text-base-content/60 font-medium">Workflow capacity:</span>
      <.capacity_badge info={@info} />
      <.connection_summary info={@info} />
    </div>
    """
  end

  @doc """
  Renders capacity text with a trailing status dot.

  Displays as:
  - "2/3 capacity (2 workers) ●" — green dot, some available
  - "0/3 capacity (3 workers) ●" — yellow dot, workers connected but busy
  - "0/0 capacity ●" — red dot, no compatible workers
  """
  attr :info, :map, required: true

  def capacity_badge(assigns) do
    worker_count = length(assigns.info.connections)
    assigns = assign(assigns, :worker_count, worker_count)

    ~H"""
    <span class="inline-flex items-center gap-1.5 text-xs">
      <span class={[
        @info.available_capacity == 0 and @worker_count == 0 && "text-base-content/40"
      ]}>
        {@info.available_capacity} of {@info.total_max_capacity} capacity
        <span :if={@worker_count > 0}>
          ({@worker_count} worker{if @worker_count != 1, do: "s"})
        </span>
      </span>
      <span class={[
        "inline-block w-2 h-2 rounded-full",
        @info.available_capacity > 0 && "bg-success",
        @info.available_capacity == 0 and @worker_count > 0 && "bg-warning",
        @info.available_capacity == 0 and @worker_count == 0 && "bg-error"
      ]} />
    </span>
    """
  end

  @doc """
  Renders the connection name list with per-worker capacity.

  Displays as:
  - "No compatible workers" — empty connections list
  - "local (1/2), remote-1 (0/1)" — per-worker detail
  """
  attr :info, :map, required: true

  def connection_summary(assigns) do
    ~H"""
    <div class={[
      "text-xs",
      @info.connections == [] && "text-base-content/30",
      @info.connections != [] && "text-base-content/60"
    ]}>
      <%= if @info.connections == [] do %>
        No compatible workers
      <% else %>
        {Enum.map_join(@info.connections, ", ", fn conn ->
          "#{conn.name} (#{conn.available_capacity}/#{conn.max_capacity})"
        end)}
      <% end %>
    </div>
    """
  end
end
