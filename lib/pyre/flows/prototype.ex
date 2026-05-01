defmodule Pyre.Flows.Prototype do
  @moduledoc """
  Single-stage prototyping flow.

  Runs a prototype engineer agent that rapidly builds a working
  proof-of-concept:

      prototyping -> complete

  Interactive by default — the agent pauses after its initial response
  for user feedback and iteration.

  ## Usage

      Pyre.Flows.Prototype.run("Build a products listing page")

  ## Options

    * `:llm` -- LLM module (default: `Pyre.LLM`). Use `Pyre.LLM.Mock` for testing.
    * `:fast` -- Override all models to the `:fast` alias. Default `false`.
    * `:dry_run` -- Skip LLM calls, log only. Default `false`.
    * `:streaming` -- Stream LLM output token-by-token. Default `true`.
    * `:verbose` -- Print diagnostic information. Default `false`.
    * `:project_dir` -- Working directory for the agents. Default `"."`.
    * `:allowed_paths` -- Additional directories agents can read/write.
    * `:output_fn` -- Function called with each streaming token. Default `&IO.write/1`.
    * `:log_fn` -- Function called with status/progress messages. Default `&IO.puts/1`.
    * `:connection_id` -- Worker connection ID for dispatch. Required.
    * `:dispatch_fn` -- Function to dispatch actions to workers. Required.
  """

  alias Pyre.Actions.PrototypeEngineer
  alias Pyre.Flows.Dispatch
  alias Pyre.Plugins.Artifact

  @transitions %{
    prototyping: [:complete],
    complete: []
  }

  @stage_to_phase %{
    prototype_engineer: :prototyping
  }

  @stage_artifact_info %{
    prototype_engineer: {:prototype_output, "01_prototype_output"}
  }

  @stage_model_tier %{
    prototype_engineer: :advanced
  }

  @doc """
  Returns the stages that are interactive by default for this flow.

  The Prototype flow is interactive by default — the prototype engineer
  stage pauses for user input after its initial response.
  """
  @spec default_interactive_stages() :: [atom()]
  def default_interactive_stages, do: [:prototyping]

  @doc """
  Runs the prototype pipeline.
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(feature_description, opts \\ []) do
    fast? = Keyword.get(opts, :fast, false)
    streaming? = Keyword.get(opts, :streaming, true)
    verbose? = Keyword.get(opts, :verbose, false)
    project_dir = Keyword.get(opts, :project_dir, ".")
    working_dir = Path.expand(project_dir)
    features_dir = Path.expand("priv/pyre/features", File.cwd!())
    feature = Keyword.get(opts, :feature)

    allowed_paths = Keyword.get(opts, :allowed_paths, [])

    attachments = Keyword.get(opts, :attachments, [])

    with {:ok, run_dir, feature_dir} <- Artifact.create_run_dir(features_dir, feature),
         :ok <- Artifact.write(run_dir, "00_feature", feature_description),
         :ok <- Artifact.store_attachments(run_dir, attachments) do
      allowed_paths = [feature_dir | allowed_paths]

      context = %{
        llm: Keyword.get(opts, :llm),
        streaming: streaming?,
        output_fn: Keyword.get(opts, :output_fn, &IO.write/1),
        log_fn: Keyword.get(opts, :log_fn, &IO.puts/1),
        model_override: if(fast?, do: "anthropic:claude-haiku-4-5"),
        verbose: verbose?,
        dry_run: Keyword.get(opts, :dry_run, false),
        working_dir: working_dir,
        allowed_paths: allowed_paths,
        add_dirs: [feature_dir],
        allowed_commands: Keyword.get(opts, :allowed_commands),
        skip_check_fn: Keyword.get(opts, :skip_check_fn),
        interactive_stage_fn: Keyword.get(opts, :interactive_stage_fn),
        await_user_action_fn: Keyword.get(opts, :await_user_action_fn),
        session_ids: Keyword.get(opts, :session_ids, %{}),
        connection_id: Keyword.fetch!(opts, :connection_id),
        dispatch_fn: Keyword.fetch!(opts, :dispatch_fn),
        max_turns: Keyword.get(opts, :max_turns, 50)
      }

      context.log_fn.("Run directory: #{run_dir}")

      state = %{
        phase: :prototyping,
        feature_description: feature_description,
        run_dir: run_dir,
        working_dir: working_dir,
        attachments: attachments,
        prototype_output: nil
      }

      flow_started_at = System.monotonic_time(:millisecond)

      Pyre.Config.notify(:after_flow_start, %Pyre.Events.FlowStarted{
        flow_module: __MODULE__,
        description: feature_description,
        run_dir: run_dir,
        working_dir: working_dir
      })

      case drive(state, context) do
        {:ok, final_state} ->
          elapsed = System.monotonic_time(:millisecond) - flow_started_at

          Pyre.Config.notify(:after_flow_complete, %Pyre.Events.FlowCompleted{
            flow_module: __MODULE__,
            description: feature_description,
            run_dir: run_dir,
            result: final_state,
            elapsed_ms: elapsed
          })

          {:ok, final_state}

        {:error, reason} = error ->
          elapsed = System.monotonic_time(:millisecond) - flow_started_at

          Pyre.Config.notify(:after_flow_error, %Pyre.Events.FlowError{
            flow_module: __MODULE__,
            description: feature_description,
            run_dir: run_dir,
            error: reason,
            elapsed_ms: elapsed
          })

          error
      end
    end
  end

  defp drive(%{phase: :complete} = state, _context) do
    {:ok, state}
  end

  defp drive(%{phase: :prototyping} = state, context) do
    with {:ok, result} <-
           Dispatch.run_action(
             PrototypeEngineer,
             :prototype_engineer,
             state,
             context,
             %{
               feature_description: state.feature_description,
               run_dir: state.run_dir,
               attachments: state.attachments
             },
             stage_config()
           ) do
      state
      |> Map.merge(result)
      |> advance_phase(:complete)
      |> drive(context)
    end
  end

  # --- Flow configuration ---

  defp stage_config do
    %{
      stage_to_phase: @stage_to_phase,
      stage_model_tier: @stage_model_tier,
      stage_artifact_info: @stage_artifact_info,
      fallback_fn: &build_fallback/2
    }
  end

  defp build_fallback(:prototype_engineer, state) do
    %{prototype_output: state.feature_description}
  end

  defp advance_phase(state, next_phase) do
    current = state.phase
    valid_next = Map.get(@transitions, current, [])

    if next_phase in valid_next do
      %{state | phase: next_phase}
    else
      raise "Invalid phase transition: #{current} -> #{next_phase}"
    end
  end

end
