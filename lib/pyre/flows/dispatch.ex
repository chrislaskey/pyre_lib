defmodule Pyre.Flows.Dispatch do
  @moduledoc false
  alias Pyre.Plugins.Artifact

  # 11 minutes — covers CLI 600s timeout + overhead
  @action_timeout 660_000

  @finalize_prompt """
  Based on our conversation, please produce the final version of your output.
  Follow the exact same structure and format as your initial response — keep
  the same sections and headings — but update the content to reflect everything
  we discussed and agreed on.\
  """

  # --- Public API called by flows ---

  @doc false
  def run_action(action_module, stage_name, state, context, params, stage_config) do
    if stage_skipped?(stage_name, context, stage_config) do
      context.log_fn.("\n--- Skipping: #{stage_name} (disabled) ---")
      {:ok, stage_config.fallback_fn.(stage_name, state)}
    else
      if context.dry_run do
        context.log_fn.("[dry-run] Would run #{stage_name}")
        {:ok, %{}}
      else
        execute_action(action_module, stage_name, state, context, params, stage_config)
      end
    end
  end

  @doc false
  def maybe_interactive_loop(stage_name, model_tier, result, state, context, stage_config) do
    phase = Map.get(stage_config.stage_to_phase, stage_name)

    if interactive_stage?(stage_name, context, stage_config) do
      session_id = get_in(context, [:session_ids, phase])

      interactive_loop(
        stage_name,
        phase,
        model_tier,
        session_id,
        result,
        state,
        context,
        0,
        stage_config
      )
    else
      {:ok, result}
    end
  end

  # --- Dispatch and receive ---

  defp execute_action(action_module, stage_name, state, context, params, stage_config) do
    started_at = System.monotonic_time(:second)
    timestamp = Calendar.strftime(NaiveDateTime.local_now(), "%H:%M:%S")
    tier = Map.get(stage_config.stage_model_tier, stage_name, :standard)
    model = Pyre.Actions.Helpers.resolve_model(tier, context)
    model_label = model_short_name(model)
    context.log_fn.("\n--- Stage: #{stage_name} [#{timestamp}] (#{model_label}) ---")

    if context.verbose do
      context.log_fn.("[verbose] action: #{inspect(action_module)}")
      context.log_fn.("[verbose] run_dir: #{params.run_dir}")
    end

    phase = Map.get(stage_config.stage_to_phase, stage_name)
    session_id = get_in(context, [:session_ids, phase])
    interactive? = interactive_stage?(stage_name, context, stage_config)

    action_started_at = System.monotonic_time(:millisecond)

    Pyre.Config.notify(:after_action_start, %Pyre.Events.ActionStarted{
      action_module: action_module,
      stage_name: stage_name,
      model: model,
      params: params
    })

    payload =
      build_action_payload(
        action_module,
        stage_name,
        tier,
        session_id,
        interactive?,
        state,
        context,
        params
      )

    case dispatch_and_wait(stage_name, payload, state, context) do
      {:ok, result_payload} ->
        elapsed = System.monotonic_time(:second) - started_at
        action_elapsed = System.monotonic_time(:millisecond) - action_started_at
        result_text = result_payload["result_text"] || ""

        context.log_fn.(
          "--- Completed: #{stage_name} (#{format_duration(elapsed)}, #{model_label}) ---"
        )

        result = post_process_result(action_module, stage_name, result_text, state, stage_config)

        Pyre.Config.notify(:after_action_complete, %Pyre.Events.ActionCompleted{
          action_module: action_module,
          stage_name: stage_name,
          result: result,
          model: model,
          elapsed_ms: action_elapsed
        })

        maybe_interactive_loop(stage_name, tier, result, state, context, stage_config)

      {:error, reason} ->
        elapsed = System.monotonic_time(:second) - started_at
        action_elapsed = System.monotonic_time(:millisecond) - action_started_at

        context.log_fn.(
          "--- Failed: #{stage_name} (#{format_duration(elapsed)}, #{model_label}) ---"
        )

        Pyre.Config.notify(:after_action_error, %Pyre.Events.ActionError{
          action_module: action_module,
          stage_name: stage_name,
          error: reason,
          model: model,
          elapsed_ms: action_elapsed
        })

        {:error, reason}
    end
  end

  defp dispatch_and_wait(_stage_name, payload, _state, context) do
    execution_id = generate_execution_id()
    connection_id = context.connection_id

    # Store execution_id in state for interactive_loop/finalize_artifact
    # We use the process dictionary since state is immutable here
    Process.put(:current_execution_id, execution_id)

    # Subscribe BEFORE dispatching (prevents race condition)
    if pubsub = Application.get_env(:pyre, :pubsub) do
      Phoenix.PubSub.subscribe(pubsub, "pyre:action:output:#{execution_id}")
    end

    # Dispatch to the worker
    context.dispatch_fn.(connection_id, execution_id, payload)

    # Block waiting for the result
    receive_action_result(execution_id, context)
  end

  defp receive_action_result(execution_id, context) do
    receive do
      {:action_output, %{"execution_id" => ^execution_id} = payload} ->
        content = payload["content"] || payload["line"] || ""
        context.output_fn.(content)
        receive_action_result(execution_id, context)

      {:action_result, %{"execution_id" => ^execution_id} = payload} ->
        {:ok, payload}

      {:action_complete, %{"execution_id" => ^execution_id} = payload} ->
        case payload["status"] do
          "ok" -> {:ok, payload}
          "error" -> {:error, payload["result_text"] || "execution failed"}
          _ -> {:ok, payload}
        end
    after
      @action_timeout ->
        {:error, :action_timeout}
    end
  end

  # --- Interactive loop (PubSub-based) ---

  defp interactive_loop(
         stage_name,
         phase,
         model_tier,
         session_id,
         result,
         state,
         context,
         reply_count,
         stage_config
       ) do
    case context.await_user_action_fn.(phase) do
      :continue when reply_count == 0 ->
        # User clicked continue without any replies — send finish and return
        send_finish(context)
        {:ok, result}

      :continue ->
        context.log_fn.(
          "\n--- Continuing to next stage. Finalizing artifact for current stage first: #{stage_name} ---"
        )

        finalize_artifact(
          stage_name,
          model_tier,
          session_id,
          result,
          state,
          context,
          stage_config
        )

      {:reply, user_text} ->
        # Send the reply to the blocked worker process
        send_continue(context, user_text)

        # Wait for the worker to resume and send back the result
        execution_id = Process.get(:current_execution_id)

        case receive_action_result(execution_id, context) do
          {:ok, payload} ->
            text = payload["result_text"] || ""
            context.log_fn.("[Interactive] received reply (#{String.length(text)} chars)")

            result_field = Map.get(stage_config.stage_artifact_info, stage_name)

            updated_result =
              case result_field do
                {field, _artifact_base} -> Map.put(result, field, text)
                nil -> result
              end

            interactive_loop(
              stage_name,
              phase,
              model_tier,
              session_id,
              updated_result,
              state,
              context,
              reply_count + 1,
              stage_config
            )

          {:error, reason} ->
            context.log_fn.("[Interactive] error: #{inspect(reason)}")
            send_finish(context)
            {:ok, result}
        end
    end
  end

  defp finalize_artifact(
         stage_name,
         _model_tier,
         _session_id,
         result,
         state,
         context,
         stage_config
       ) do
    # Send the finalize prompt as a continuation
    send_continue(context, @finalize_prompt)

    execution_id = Process.get(:current_execution_id)

    case receive_action_result(execution_id, context) do
      {:ok, payload} ->
        finalized_text = payload["result_text"] || ""

        # Send finish to release the worker's execution process
        send_finish(context)

        case Map.get(stage_config.stage_artifact_info, stage_name) do
          nil ->
            {:ok, result}

          {field, nil} ->
            {:ok, Map.put(result, field, finalized_text)}

          {field, artifact_base} ->
            {:ok, content} = Artifact.read_or_write(state.run_dir, artifact_base, finalized_text)
            {:ok, Map.put(result, field, content)}
        end

      {:error, _reason} ->
        send_finish(context)
        {:ok, result}
    end
  end

  # --- Payload building ---

  defp build_action_payload(
         action_module,
         _stage_name,
         model_tier,
         session_id,
         interactive?,
         state,
         context,
         params
       ) do
    messages = action_module.build_messages(params, state)

    json_messages =
      Enum.map(messages, fn msg ->
        content =
          case msg.content do
            parts when is_list(parts) ->
              # Multipart content (text + images) — serialize as list
              Enum.map(parts, fn
                %{type: "text"} = part -> part
                %{type: "image"} = part -> part
                other -> %{"type" => "text", "text" => to_string(other)}
              end)

            text when is_binary(text) ->
              text
          end

        %{"role" => to_string(msg.role), "content" => content}
      end)

    payload = %{
      "action" => action_module.action_type(),
      "payload" => %{
        "model_tier" => to_string(model_tier),
        "interactive" => interactive?,
        "messages" => json_messages,
        "role" => action_module.role(),
        "working_dir" => context.working_dir,
        "allowed_commands" => Map.get(context, :allowed_commands) || [],
        "opts" => %{
          "streaming" => context.streaming,
          "session_id" => session_id,
          "max_turns" => Map.get(context, :max_turns, 50),
          "add_dirs" => Map.get(context, :add_dirs, [])
        }
      }
    }

    # Git actions add GitHub credentials
    if action_module.action_type() in ["git_pr_setup", "git_ship", "git_review"] do
      github = Map.get(context, :github, %{})

      github_config = %{
        "owner" => github[:owner],
        "repo" => github[:repo],
        "token" => github[:token],
        "base_branch" => github[:base_branch] || "main"
      }

      put_in(payload, ["payload", "github"], github_config)
    else
      payload
    end
  end

  # --- Result post-processing ---

  defp post_process_result(action_module, stage_name, result_text, state, stage_config) do
    case action_module.action_type() do
      "prompt" ->
        # Template actions: write artifact and build result map
        base_result =
          case Map.get(stage_config.stage_artifact_info, stage_name) do
            nil ->
              %{}

            {field, nil} ->
              %{field => result_text}

            {field, artifact_base} ->
              {:ok, content} = Artifact.read_or_write(state.run_dir, artifact_base, result_text)
              %{field => content}
          end

        # QAReviewer/PRReviewer: parse verdict server-side
        if function_exported?(action_module, :parse_verdict, 1) do
          verdict = action_module.parse_verdict(result_text)
          Map.merge(base_result, %{verdict: verdict, verdict_text: result_text})
        else
          base_result
        end

      "git_pr_setup" ->
        # PRSetup: client returns structured result in the text
        # The client handles all git operations; we just parse what we need
        %{pr_setup: result_text, branch_name: extract_field(result_text, "branch_name")}

      "git_ship" ->
        %{shipping_summary: result_text}

      "git_review" ->
        verdict =
          if function_exported?(action_module, :parse_verdict, 1) do
            action_module.parse_verdict(result_text)
          else
            Pyre.Actions.QAReviewer.parse_verdict(result_text)
          end

        %{review: result_text, verdict: verdict}
    end
  end

  defp extract_field(_text, _field), do: nil

  # --- PubSub helpers ---

  defp send_continue(context, message) do
    execution_id = Process.get(:current_execution_id)
    connection_id = context.connection_id

    if pubsub = Application.get_env(:pyre, :pubsub) do
      Phoenix.PubSub.broadcast(
        pubsub,
        "pyre:action:input:#{connection_id}",
        {:action_continue, execution_id,
         %{"message" => message, "working_dir" => context.working_dir}}
      )
    end
  end

  defp send_finish(context) do
    execution_id = Process.get(:current_execution_id)
    connection_id = context.connection_id

    if pubsub = Application.get_env(:pyre, :pubsub) do
      Phoenix.PubSub.broadcast(
        pubsub,
        "pyre:action:input:#{connection_id}",
        {:action_finish, execution_id}
      )
    end
  end

  # --- Shared helpers ---

  defp generate_execution_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp stage_skipped?(stage_name, context, stage_config) do
    phase = Map.get(stage_config.stage_to_phase, stage_name)

    case Map.get(context, :skip_check_fn) do
      nil -> false
      check_fn when is_function(check_fn) -> check_fn.(phase)
    end
  end

  defp interactive_stage?(stage_name, context, stage_config) do
    phase = Map.get(stage_config.stage_to_phase, stage_name)

    case Map.get(context, :interactive_stage_fn) do
      nil -> false
      check_fn when is_function(check_fn) -> check_fn.(phase)
    end
  end

  defp model_short_name(model) when is_binary(model) do
    model
    |> String.replace(~r/^[^:]+:/, "")
    |> String.replace(~r/-\d{8}$/, "")
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    remaining = rem(seconds, 60)
    "#{minutes}m #{remaining}s"
  end
end
