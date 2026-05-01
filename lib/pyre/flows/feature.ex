defmodule Pyre.Flows.Feature do
  @moduledoc """
  Feature build flow.

  Orchestrates three agent roles through a sequential pipeline:

      architecting -> pr_setup -> engineering -> complete

  The Software Architect breaks the feature into small phases with acceptance
  criteria. PR Setup creates a git branch and GitHub PR. The Software
  Engineer then implements all phases in a single agentic session, committing
  per phase.

  ## Usage

      Pyre.Flows.Feature.run("Build a products listing page")

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
    * `:github` -- GitHub repo config map with `:owner`, `:repo`, `:token`, and
      optional `:base_branch`. Required for PR setup.
    * `:connection_id` -- Worker connection ID for dispatch. Required.
    * `:dispatch_fn` -- Function to dispatch actions to workers. Required.
  """

  alias Pyre.Actions.{PRSetup, SoftwareArchitect, SoftwareEngineer}
  alias Pyre.Flows.Dispatch
  alias Pyre.Plugins.Artifact

  @transitions %{
    architecting: [:pr_setup],
    pr_setup: [:engineering],
    engineering: [:complete],
    complete: []
  }

  @stage_to_phase %{
    software_architect: :architecting,
    pr_setup: :pr_setup,
    software_engineer: :engineering
  }

  @stage_fallback_field %{
    software_architect: :architecture_plan,
    pr_setup: :pr_setup,
    software_engineer: :implementation_summary
  }

  @stage_artifact_info %{
    software_architect: {:architecture_plan, "03_architecture_plan"},
    pr_setup: {:pr_setup, "04_pr_setup"},
    software_engineer: {:implementation_summary, "06_implementation_summary"}
  }

  @stage_model_tier %{
    software_architect: :advanced,
    pr_setup: :standard,
    software_engineer: :standard
  }

  @doc """
  Returns the stages that are interactive by default for this flow.
  """
  @spec default_interactive_stages() :: [atom()]
  def default_interactive_stages, do: [:architecting, :engineering]

  @doc """
  Runs the feature build pipeline.
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
      # Give agents access to the feature dir so they can browse prior runs
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
        github: Keyword.get(opts, :github) || github_from_config(),
        connection_id: Keyword.fetch!(opts, :connection_id),
        dispatch_fn: Keyword.fetch!(opts, :dispatch_fn),
        max_turns: Keyword.get(opts, :max_turns, 50)
      }

      context.log_fn.("Run directory: #{run_dir}")

      state = %{
        phase: :architecting,
        feature_description: feature_description,
        run_dir: run_dir,
        working_dir: working_dir,
        attachments: attachments,
        architecture_plan: nil,
        pr_setup: nil,
        branch_name: nil,
        pr_url: nil,
        pr_number: nil,
        implementation_summary: nil
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

  defp drive(%{phase: :architecting} = state, context) do
    with {:ok, result} <-
           Dispatch.run_action(
             SoftwareArchitect,
             :software_architect,
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
      |> advance_phase(:pr_setup)
      |> drive(context)
    end
  end

  defp drive(%{phase: :pr_setup} = state, context) do
    with {:ok, result} <-
           Dispatch.run_action(
             PRSetup,
             :pr_setup,
             state,
             context,
             %{
               feature_description: state.feature_description,
               architecture_plan: state.architecture_plan,
               run_dir: state.run_dir,
               attachments: state.attachments
             },
             stage_config()
           ) do
      state
      |> Map.merge(result)
      |> advance_phase(:engineering)
      |> drive(context)
    end
  end

  defp drive(%{phase: :engineering} = state, context) do
    with {:ok, result} <-
           Dispatch.run_action(
             SoftwareEngineer,
             :software_engineer,
             state,
             context,
             %{
               feature_description: state.feature_description,
               architecture_plan: state.architecture_plan,
               pr_setup: state.pr_setup,
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

  defp build_fallback(stage_name, _state) do
    text = Pyre.Plugins.BestPractices.fallback_text(stage_name)
    field = Map.fetch!(@stage_fallback_field, stage_name)
    %{field => text}
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

  defp github_from_config do
    case Application.get_env(:pyre, :github) do
      nil ->
        %{}

      config ->
        repos = Keyword.get(config, :repositories, [])

        case repos do
          [first | _] ->
            url = Keyword.get(first, :url, "")

            case Pyre.GitHub.parse_remote_url(url) do
              {:ok, {owner, repo}} ->
                %{
                  owner: owner,
                  repo: repo,
                  token: Keyword.get(first, :token),
                  base_branch: Keyword.get(first, :base_branch, "main")
                }

              {:error, _} ->
                %{}
            end

          [] ->
            %{}
        end
    end
  end
end
