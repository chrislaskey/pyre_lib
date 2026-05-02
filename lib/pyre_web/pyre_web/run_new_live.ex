defmodule PyreWeb.RunNewLive do
  @moduledoc """
  LiveView for submitting a new Pyre pipeline run.
  """
  use PyreWeb.Web, :live_view

  @presence_topic "pyre:connections"

  @impl true
  def mount(_params, _session, socket) do
    workflows = apply(Pyre.Config, :list_workflows, [])
    default_entry = Enum.find(workflows, fn w -> w.name == :chat end) || hd(workflows)

    presences =
      if connected?(socket) and PyreWeb.Presence.running?() do
        Phoenix.PubSub.subscribe(pubsub(), @presence_topic)
        PyreWeb.Presence.list_connections()
      else
        []
      end

    capacity = Pyre.WorkflowAvailability.capacity_by_type(presences, workflows)

    socket =
      socket
      |> assign(
        page_title: "New Run — Pyre",
        form: to_form(%{"feature_description" => "", "feature_name" => ""}, as: :run),
        feature_name: "",
        feature_suggestions: [],
        workflows: workflows,
        workflow: default_entry.name,
        toggleable_stages: default_entry.stages,
        skipped_stages: MapSet.new(),
        interactive_stages: default_interactive_for(default_entry),
        presences: presences,
        capacity_by_type: capacity
      )
      |> allow_upload(:attachments,
        accept: ~w(.txt .md .csv .json .html .css .js .png .jpg .jpeg .gif .webp),
        max_entries: 10,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end

  @impl true
  def handle_event("validate", %{"run" => params}, socket) do
    feature_name = Map.get(params, "feature_name", "")

    suggestions =
      if String.length(String.trim(feature_name)) > 0 do
        features_dir = Path.expand("priv/pyre/features", File.cwd!())

        apply(Pyre.Plugins.Artifact, :list_features, [features_dir])
        |> Enum.filter(&String.contains?(&1, String.downcase(String.trim(feature_name))))
      else
        features_dir = Path.expand("priv/pyre/features", File.cwd!())
        apply(Pyre.Plugins.Artifact, :list_features, [features_dir])
      end

    {:noreply,
     assign(socket,
       form: to_form(params, as: :run),
       feature_name: feature_name,
       feature_suggestions: suggestions
     )}
  end

  def handle_event("select_workflow", %{"workflow" => workflow_str}, socket) do
    workflow_name = String.to_existing_atom(workflow_str)
    entry = Enum.find(socket.assigns.workflows, fn w -> w.name == workflow_name end)

    socket =
      assign(socket,
        workflow: entry.name,
        toggleable_stages: entry.stages,
        skipped_stages: MapSet.new(),
        interactive_stages: default_interactive_for(entry)
      )

    {:noreply, socket}
  end

  def handle_event("toggle_stage", %{"stage" => stage_str}, socket) do
    stage = String.to_existing_atom(stage_str)

    skipped =
      if MapSet.member?(socket.assigns.skipped_stages, stage) do
        MapSet.delete(socket.assigns.skipped_stages, stage)
      else
        MapSet.put(socket.assigns.skipped_stages, stage)
      end

    {:noreply, assign(socket, skipped_stages: skipped)}
  end

  def handle_event("toggle_interactive_stage", %{"stage" => stage_str}, socket) do
    stage = String.to_existing_atom(stage_str)

    interactive =
      if MapSet.member?(socket.assigns.interactive_stages, stage) do
        MapSet.delete(socket.assigns.interactive_stages, stage)
      else
        MapSet.put(socket.assigns.interactive_stages, stage)
      end

    {:noreply, assign(socket, interactive_stages: interactive)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("submit", %{"run" => params}, socket) do
    desc = String.trim(Map.get(params, "feature_description", ""))
    feature_name = String.trim(Map.get(params, "feature_name", ""))

    if desc == "" do
      {:noreply, put_flash(socket, :error, "Feature description cannot be empty.")}
    else
      feature = if feature_name != "", do: feature_name

      run_params = %{
        description: desc,
        workflow: socket.assigns.workflow,
        feature: feature
      }

      case Pyre.Config.authorize(:authorize_run_create, [run_params, socket]) do
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Not authorized: #{inspect(reason)}")}

        :ok ->
          start_run(socket, desc, feature)
      end
    end
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff},
        socket
      ) do
    presences = PyreWeb.Presence.apply_diff(socket.assigns.presences, diff)

    capacity =
      Pyre.WorkflowAvailability.capacity_by_type(presences, socket.assigns.workflows)

    {:noreply, assign(socket, presences: presences, capacity_by_type: capacity)}
  end

  defp start_run(socket, desc, feature) do
    attachments =
      consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
        content = File.read!(path)

        media_type =
          apply(Pyre.Plugins.Artifact, :media_type_from_filename, [entry.client_name])

        {:ok,
         %{
           filename: entry.client_name,
           content: content,
           media_type: media_type
         }}
      end)

    skipped = MapSet.to_list(socket.assigns.skipped_stages)
    interactive = MapSet.to_list(socket.assigns.interactive_stages)

    opts = [
      workflow: socket.assigns.workflow,
      skipped_stages: skipped,
      interactive_stages: interactive,
      attachments: attachments,
      feature: feature
    ]

    case Pyre.Config.call(:run_submit, [desc, opts]) do
      {:ok, result} ->
        if redirect_to = Keyword.get(result, :redirect_to) do
          {:noreply, push_navigate(socket, to: pyre_path(socket, redirect_to))}
        else
          {:noreply, put_flash(socket, :info, "Workflow submitted successfully")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit workflow: #{inspect(reason)}")}

      nil ->
        # Config.call/2 returns nil on exception
        {:noreply, put_flash(socket, :error, "Failed to submit workflow")}
    end
  end

  defp pubsub do
    Application.get_env(:pyre, :pubsub, Phoenix.PubSub)
  end

  defp workflow_card(assigns) do
    info =
      assigns[:capacity_info] ||
        %{available_capacity: 0, total_max_capacity: 0, connections: []}

    assigns = assign(assigns, :capacity_info, info)

    ~H"""
    <div
      phx-click="select_workflow"
      phx-value-workflow={@value}
      class={[
        "cursor-pointer rounded-lg border-2 px-4 py-3 transition-colors",
        if(@selected,
          do: "border-primary",
          else: "border-base-300 hover:border-primary/50"
        )
      ]}
    >
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm font-medium">{@label}</span>
        <PyreWeb.Components.WorkflowCapacity.capacity_badge info={@capacity_info} />
      </div>
      <div class="text-xs text-base-content/50 mt-0.5">{@description}</div>
      <div class="mt-1.5">
        <span class={[
          "badge badge-xs uppercase",
          if(@badge == "Interactive", do: "badge-soft badge-primary", else: "badge-ghost")
        ]}>
          {@badge}
        </span>
      </div>
    </div>
    """
  end

  defp flash_group(assigns) do
    ~H"""
    <div :if={msg = Phoenix.Flash.get(@flash, :error)} class="alert alert-error mb-4">
      <span>{msg}</span>
    </div>
    <div :if={msg = Phoenix.Flash.get(@flash, :info)} class="alert alert-info mb-4">
      <span>{msg}</span>
    </div>
    """
  end

  defp default_interactive_for(workflow_entry) do
    mod = workflow_entry.module

    if Code.ensure_loaded?(mod) and function_exported?(mod, :default_interactive_stages, 0) do
      MapSet.new(apply(mod, :default_interactive_stages, []))
    else
      MapSet.new()
    end
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 10 MB)"
  defp upload_error_to_string(:not_accepted), do: "Invalid file type"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 10)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
