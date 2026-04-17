defmodule PyreWeb.RunShowLive do
  @moduledoc """
  LiveView for streaming output of a Pyre pipeline run.

  On mount, subscribes to PubSub for real-time updates, then fetches
  buffered state from the RunServer to catch up on any events that
  occurred before the subscription.
  """
  use PyreWeb.Web, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      if pubsub = Application.get_env(:pyre, :pubsub) do
        Phoenix.PubSub.subscribe(pubsub, "pyre:runs:#{id}")
      end
    end

    case PyreWeb.Config.call(:get_run, [id]) do
      {:ok, run} ->
        socket =
          socket
          |> assign(
            page_title: "Run #{id} — Pyre",
            run_id: id,
            confirm_stop: false,
            reply_text: ""
          )
          |> assign_from_run(run)
          |> stream(:items, Map.get(run, :log, []))

        {:ok, socket}

      _ ->
        {:ok, redirect(socket, to: pyre_path(socket, "/runs"))}
    end
  end

  defp phases_for_workflow(workflow) do
    case apply(Pyre.Config, :get_workflow, [workflow]) do
      {:ok, entry} ->
        phase_order = Enum.map(entry.stages, fn {stage, _} -> stage end)
        phases = Enum.map(phase_order, fn stage -> {stage, phase_label(stage)} end)
        {phases, phase_order}

      :error ->
        {[], []}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end

  @impl true
  def handle_event("toggle_stage", %{"stage" => stage_str}, socket) do
    stage = String.to_existing_atom(stage_str)
    action = %{type: :toggle_stage, run_id: socket.assigns.run_id, stage: stage}

    with :ok <- authorize_control(action, socket) do
      case apply(Pyre.RunServer, :toggle_stage, [socket.assigns.run_id, stage]) do
        :ok -> {:noreply, socket}
        {:error, _} -> {:noreply, socket}
      end
    end
  end

  def handle_event("toggle_interactive_stage", %{"stage" => stage_str}, socket) do
    stage = String.to_existing_atom(stage_str)
    action = %{type: :toggle_interactive, run_id: socket.assigns.run_id, stage: stage}

    with :ok <- authorize_control(action, socket) do
      case apply(Pyre.RunServer, :toggle_interactive_stage, [socket.assigns.run_id, stage]) do
        :ok -> {:noreply, socket}
        {:error, _} -> {:noreply, socket}
      end
    end
  end

  def handle_event("send_reply", %{"reply" => text}, socket) do
    action = %{type: :send_reply, run_id: socket.assigns.run_id}

    with :ok <- authorize_control(action, socket) do
      apply(Pyre.RunServer, :send_reply, [socket.assigns.run_id, text])
      {:noreply, assign(socket, reply_text: "")}
    end
  end

  def handle_event("continue_stage", _params, socket) do
    action = %{type: :continue, run_id: socket.assigns.run_id}

    with :ok <- authorize_control(action, socket) do
      apply(Pyre.RunServer, :continue_stage, [socket.assigns.run_id])
      {:noreply, socket}
    end
  end

  def handle_event("update_reply", %{"reply" => text}, socket) do
    {:noreply, assign(socket, reply_text: text)}
  end

  def handle_event("request_stop", _params, socket) do
    {:noreply, assign(socket, confirm_stop: true)}
  end

  def handle_event("cancel_stop", _params, socket) do
    {:noreply, assign(socket, confirm_stop: false)}
  end

  def handle_event("confirm_stop", _params, socket) do
    action = %{type: :stop, run_id: socket.assigns.run_id}

    with :ok <- authorize_control(action, socket) do
      PyreWeb.Config.call(:run_stop, [socket.assigns.run_id])
      {:noreply, assign(socket, confirm_stop: false)}
    end
  end

  @impl true
  def handle_info({:pyre_run_event, _id, entry}, socket) do
    {:noreply, stream_insert(socket, :items, entry)}
  end

  def handle_info({:pyre_run_status, _id, status}, socket) do
    # Re-fetch the full run state on every status change. The get_run
    # callback may return fundamentally different data depending on the
    # status (e.g., a host app might switch from DB-only to RunServer
    # data when a queued run starts). Letting get_run be the single
    # source of truth keeps pyre_web agnostic about host-app statuses.
    socket =
      case PyreWeb.Config.call(:get_run, [socket.assigns.run_id]) do
        {:ok, run} ->
          socket
          |> assign_from_run(run)
          |> stream(:items, Map.get(run, :log, []), reset: true)

        _ ->
          assign(socket, status: status)
      end

    socket = maybe_notify_status(socket, socket.assigns.run_id, status)
    {:noreply, socket}
  end

  def handle_info({:pyre_run_phase, _id, phase}, socket) do
    {:noreply,
     socket
     |> assign(phase: phase)
     |> assign(session_ids: resolve_session_ids(socket.assigns.raw_session_ids))}
  end

  def handle_info({:pyre_run_skipped_stages, _id, skipped}, socket) do
    {:noreply, assign(socket, skipped_stages: skipped)}
  end

  def handle_info({:pyre_interactive_stages, _id, stages}, socket) do
    {:noreply, assign(socket, interactive_stages: stages)}
  end

  def handle_info({:pyre_waiting_for_input, _id, phase}, socket) do
    socket =
      socket
      |> assign(waiting_for_input: true, waiting_phase: phase)
      |> push_event("pyre:notify", %{
        title: "Input needed",
        body: "Run #{socket.assigns.run_id} is waiting for your response",
        level: "warning",
        tag: "pyre-run-#{socket.assigns.run_id}"
      })

    {:noreply, socket}
  end

  def handle_info({:pyre_stage_resumed, _id, _phase}, socket) do
    {:noreply, assign(socket, waiting_for_input: false, reply_text: "")}
  end

  defp workflow_panel(assigns) do
    ~H"""
    <div class="mb-6 border border-base-300 rounded-lg overflow-hidden">
      <div class="bg-base-200 px-4 py-2 border-b border-base-300">
        <span class="text-sm font-medium">Workflow</span>
      </div>
      <div class="p-3 flex flex-col gap-y-2">
        <.stage_row
          :for={{phase_key, label} <- @phases}
          phase_key={phase_key}
          label={label}
          current={@current}
          status={@status}
          skipped={@skipped}
          interactive={@interactive}
          waiting_for_input={@waiting_for_input}
          phase_order={@phase_order}
          session_id={Map.get(@session_ids, phase_key)}
        />
      </div>
    </div>
    """
  end

  defp stage_row(assigns) do
    assigns =
      assign(
        assigns,
        :stage_status,
        stage_status(
          assigns.phase_key,
          assigns.current,
          assigns.status,
          assigns.skipped,
          assigns.phase_order
        )
      )

    ~H"""
    <div>
      <div class="flex items-center gap-3">
        <%!-- Skip toggle --%>
        <%= if toggleable?(@phase_key, @current, @status, @phase_order) do %>
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-primary"
            checked={@phase_key not in @skipped}
            phx-click="toggle_stage"
            phx-value-stage={@phase_key}
          />
        <% else %>
          <input
            type="checkbox"
            class="toggle toggle-sm"
            checked={@phase_key not in @skipped}
            disabled
          />
        <% end %>

        <span class={"text-sm flex-1 #{stage_label_class(@stage_status)}"}>
          {@label}
        </span>

        <.stage_badge status={@stage_status} waiting={@waiting_for_input and @phase_key == @current} />

        <%!-- Interactive toggle --%>
        <label class="flex items-center gap-1 cursor-pointer">
          <span class="text-xs text-base-content/40">interactive</span>
          <%= if toggleable?(@phase_key, @current, @status, @phase_order) do %>
            <input
              type="checkbox"
              class="toggle toggle-xs toggle-secondary"
              checked={@phase_key in @interactive}
              phx-click="toggle_interactive_stage"
              phx-value-stage={@phase_key}
            />
          <% else %>
            <input
              type="checkbox"
              class="toggle toggle-xs toggle-secondary pointer-events-none"
              checked={@phase_key in @interactive}
              tabindex="-1"
            />
          <% end %>
        </label>
      </div>
      <div :if={@session_id} class="ml-9 mt-0.5">
        <span class="text-[11px] font-mono text-base-content/30 select-all">{@session_id}</span>
      </div>
    </div>
    """
  end

  defp reply_panel(assigns) do
    ~H"""
    <div class="mt-4 border border-secondary/40 rounded-lg overflow-hidden">
      <div class="bg-secondary/10 px-4 py-2 border-b border-accent/30">
        <span class="text-sm font-medium text-secondary">
          Waiting for your input — {phase_label(@waiting_phase)}
        </span>
      </div>
      <div class="p-4">
        <%= if backend_supports_replies?(@backend) do %>
          <form phx-submit="send_reply" phx-change="update_reply">
            <textarea
              name="reply"
              rows="3"
              class="textarea textarea-bordered w-full font-mono text-sm mb-3"
              placeholder="Type your reply..."
              value={@reply_text}
              autofocus
            ></textarea>
            <div class="flex justify-between items-center">
              <button type="submit" class="btn btn-secondary btn-sm" disabled={@reply_text == ""}>
                Send Reply
              </button>
              <button
                type="button"
                phx-click="continue_stage"
                class="btn btn-ghost btn-sm"
              >
                Mark complete and continue &rarr;
              </button>
            </div>
          </form>
        <% else %>
          <p class="text-sm text-base-content/50 mb-3">
            Interactive replies require a backend that supports resuming sessions. The current backend is not configured for it.
          </p>
          <button phx-click="continue_stage" class="btn btn-ghost btn-sm">
            Mark complete and continue &rarr;
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp stage_status(phase_key, current, run_status, skipped, phase_order) do
    current_idx = Enum.find_index(phase_order, &(&1 == current)) || 0
    phase_idx = Enum.find_index(phase_order, &(&1 == phase_key)) || 0

    cond do
      phase_key in skipped && phase_idx < current_idx -> :skipped
      phase_key in skipped -> :will_skip
      run_status in [:complete, :stopped] -> :done
      run_status == :error && phase_key == current -> :error
      phase_idx < current_idx -> :done
      phase_key == current -> :active
      true -> :pending
    end
  end

  defp stage_label_class(:active), do: "font-medium"
  defp stage_label_class(:done), do: "text-base-content/50"
  defp stage_label_class(:skipped), do: "text-base-content/30 line-through"
  defp stage_label_class(:will_skip), do: "text-base-content/30 line-through"
  defp stage_label_class(:error), do: "text-error font-medium"
  defp stage_label_class(_), do: "text-base-content/70"

  defp stage_badge(%{status: :active, waiting: true} = assigns) do
    ~H"""
    <span class="badge badge-xs badge-secondary">waiting</span>
    """
  end

  defp stage_badge(%{status: :active} = assigns) do
    ~H"""
    <span class="badge badge-xs badge-primary">running</span>
    """
  end

  defp stage_badge(%{status: :done} = assigns) do
    ~H"""
    <span class="badge badge-xs badge-success">done</span>
    """
  end

  defp stage_badge(%{status: :skipped} = assigns) do
    ~H"""
    <span class="badge badge-xs badge-ghost">skipped</span>
    """
  end

  defp stage_badge(%{status: :error} = assigns) do
    ~H"""
    <span class="badge badge-xs badge-error">error</span>
    """
  end

  defp stage_badge(assigns) do
    ~H"""
    """
  end

  defp toggleable?(phase_key, current, status, phase_order) do
    if status != :running do
      false
    else
      current_idx = Enum.find_index(phase_order, &(&1 == current)) || 0
      phase_idx = Enum.find_index(phase_order, &(&1 == phase_key)) || 0
      phase_idx > current_idx
    end
  end

  defp phase_label(:generalist), do: "Generalist"
  defp phase_label(:planning), do: "Planning"
  defp phase_label(:designing), do: "Design"
  defp phase_label(:implementing), do: "Implementation"
  defp phase_label(:testing), do: "Testing"
  defp phase_label(:reviewing), do: "Review"
  defp phase_label(:shipping), do: "Shipping"
  defp phase_label(:architecting), do: "Architecture"
  defp phase_label(:pr_setup), do: "PR Setup"
  defp phase_label(:engineering), do: "Engineering"
  defp phase_label(:prototyping), do: "Prototyping"
  defp phase_label(:tasking), do: "Task"
  defp phase_label(other), do: to_string(other)

  defp status_badge_class(:running), do: "badge-warning"
  defp status_badge_class(:complete), do: "badge-success"
  defp status_badge_class(:stopped), do: "badge-neutral"
  defp status_badge_class(:error), do: "badge-error"
  defp status_badge_class(_), do: "badge-neutral"

  defp status_label(status),
    do: status |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp item_class(:log), do: "block mt-1 text-info"
  defp item_class(:error), do: "block mt-1 text-error"
  defp item_class(:user_reply), do: "block mt-1 text-secondary"
  defp item_class(_), do: ""

  defp maybe_notify_status(socket, run_id, :complete) do
    push_event(socket, "pyre:notify", %{
      title: "Run completed",
      body: "Run #{run_id} finished successfully",
      level: "success",
      tag: "pyre-run-#{run_id}"
    })
  end

  defp maybe_notify_status(socket, run_id, :error) do
    push_event(socket, "pyre:notify", %{
      title: "Run failed",
      body: "Run #{run_id} encountered an error",
      level: "error",
      tag: "pyre-run-#{run_id}"
    })
  end

  defp maybe_notify_status(socket, _run_id, _status), do: socket

  defp assign_from_run(socket, run) do
    {phases, phase_order} =
      case Map.get(run, :workflow) do
        nil -> {[], []}
        workflow -> phases_for_workflow(workflow)
      end

    raw_session_ids = Map.get(run, :session_ids, %{})

    assign(socket,
      run: run,
      status: Map.get(run, :status, :unknown),
      phase: Map.get(run, :phase),
      feature: Map.get(run, :feature),
      feature_description: Map.get(run, :feature_description, ""),
      skipped_stages: Map.get(run, :skipped_stages, MapSet.new()),
      interactive_stages: Map.get(run, :interactive_stages, MapSet.new()),
      waiting_for_input: Map.get(run, :waiting_for_input, false),
      waiting_phase: Map.get(run, :phase),
      backend: Map.get(run, :backend, "other"),
      raw_session_ids: raw_session_ids,
      session_ids: resolve_session_ids(raw_session_ids),
      phases: phases,
      phase_order: phase_order
    )
  end

  defp resolve_session_ids(raw_ids) do
    Map.new(raw_ids, fn {phase, pyre_id} ->
      backend_id = apply(Pyre.Session.Registry, :get, [pyre_id])
      {phase, backend_id || pyre_id}
    end)
  end

  defp backend_supports_replies?(backend_name) when is_binary(backend_name) do
    backends = apply(Pyre.Config, :list_llm_backends, [])

    case apply(Pyre.Config, :find_backend_by_name, [backends, backend_name]) do
      {:ok, %{module: mod}} ->
        Code.ensure_loaded?(mod) and function_exported?(mod, :manages_tool_loop?, 0) and
          mod.manages_tool_loop?()

      :error ->
        false
    end
  end

  defp backend_supports_replies?(_), do: false

  defp authorize_control(action, socket) do
    case PyreWeb.Config.authorize(:authorize_run_control, [action, socket]) do
      :ok -> :ok
      {:error, _} -> {:noreply, socket}
    end
  end
end
