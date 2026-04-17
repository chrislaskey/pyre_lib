defmodule Pyre.RemoteReview do
  @moduledoc """
  Orchestrates remote PR reviews triggered by GitHub webhooks.

  Wraps the existing `Pyre.Flows.CodeReview` flow with remote context:
  clone the repo, compute the diff, run the review, post results to GitHub.
  """

  require Logger

  @type pr_context :: %{
          owner: String.t(),
          repo: String.t(),
          pr_number: integer(),
          installation_id: integer(),
          comment_id: integer() | nil,
          in_reply_to: integer() | nil,
          command: atom()
        }

  @doc """
  Runs a full code review on a remote PR and posts the results to GitHub.
  """
  def run(%{command: :review} = ctx) do
    with {:ok, token} <- get_token(ctx),
         {:ok, pr} <- Pyre.GitHub.get_pull_request(ctx.owner, ctx.repo, ctx.pr_number, token),
         {:ok, diff} <-
           Pyre.GitHub.get_pull_request_diff(ctx.owner, ctx.repo, ctx.pr_number, token),
         {:ok, tmp_dir} <- Pyre.Git.clone_and_checkout(pr.clone_url, pr.head_branch, token) do
      try do
        description = build_review_prompt(pr, diff)

        opts = [
          project_dir: tmp_dir,
          streaming: false,
          output_fn: &noop/1,
          log_fn: &log_remote/1
        ]

        case Pyre.Flows.CodeReview.run(description, opts) do
          {:ok, result} ->
            post_review_result(ctx, result, token)
            {:ok, result}

          {:error, reason} ->
            post_error(ctx, reason, token)
            {:error, reason}
        end
      after
        Pyre.Git.cleanup(tmp_dir)
      end
    else
      {:error, reason} = error ->
        Logger.error(
          "RemoteReview failed for #{ctx.owner}/#{ctx.repo}##{ctx.pr_number}: #{inspect(reason)}"
        )

        error
    end
  end

  def run(%{command: :help} = ctx) do
    with {:ok, token} <- get_token(ctx) do
      bot = Pyre.GitHub.App.bot_slug() || "pyre-review"

      body = """
      **Available commands:**

      | Command | Description |
      |---|---|
      | `@#{bot} review` | Run a full code review on this PR |
      | `@#{bot} explain` | Explain what this PR does |
      | `@#{bot} help` | Show this help message |

      You can also ask follow-up questions by replying with `@#{bot} <your question>`.
      """

      post_comment(ctx, body, token)
    end
  end

  def run(%{command: :explain} = ctx) do
    with {:ok, token} <- get_token(ctx),
         {:ok, pr} <- Pyre.GitHub.get_pull_request(ctx.owner, ctx.repo, ctx.pr_number, token),
         {:ok, diff} <-
           Pyre.GitHub.get_pull_request_diff(ctx.owner, ctx.repo, ctx.pr_number, token) do
      description = build_explain_prompt(pr, diff)

      llm = Pyre.LLM.default()
      model = Pyre.Actions.Helpers.resolve_model(:standard, %{})
      messages = [%{role: :user, content: description}]

      case llm.generate(model, messages, []) do
        {:ok, response} ->
          text = extract_text(response)
          post_comment(ctx, text, token)

        {:error, reason} ->
          post_error(ctx, reason, token)
          {:error, reason}
      end
    end
  end

  def run(%{command: :followup, followup_text: text} = ctx) do
    with {:ok, token} <- get_token(ctx),
         {:ok, pr} <- Pyre.GitHub.get_pull_request(ctx.owner, ctx.repo, ctx.pr_number, token),
         {:ok, diff} <-
           Pyre.GitHub.get_pull_request_diff(ctx.owner, ctx.repo, ctx.pr_number, token) do
      description = build_followup_prompt(pr, diff, text)

      llm = Pyre.LLM.default()
      model = Pyre.Actions.Helpers.resolve_model(:standard, %{})
      messages = [%{role: :user, content: description}]

      case llm.generate(model, messages, []) do
        {:ok, response} ->
          reply_text = extract_text(response)
          post_comment(ctx, reply_text, token)

        {:error, reason} ->
          post_error(ctx, reason, token)
          {:error, reason}
      end
    end
  end

  # --- Private ---

  defp get_token(ctx) do
    Pyre.GitHub.App.installation_token(ctx.installation_id)
  end

  defp build_review_prompt(pr, diff) do
    """
    Review this pull request.

    **PR Title**: #{pr.title}
    **Author**: #{pr.author}
    **Branch**: #{pr.head_branch} -> #{pr.base_branch}
    **Changes**: #{pr.changed_files} files changed (+#{pr.additions}, -#{pr.deletions})

    ## PR Description

    #{pr.body || "(no description)"}

    ## Diff

    ```diff
    #{truncate_diff(diff)}
    ```

    Focus your review on the changes shown in the diff. You have access to the full
    repository via your tools if you need additional context.
    """
  end

  defp build_explain_prompt(pr, diff) do
    """
    Explain what this pull request does. Provide a clear, concise summary
    suitable for a developer who hasn't seen the changes yet.

    **PR Title**: #{pr.title}
    **Author**: #{pr.author}
    **Branch**: #{pr.head_branch} -> #{pr.base_branch}

    ## PR Description

    #{pr.body || "(no description)"}

    ## Diff

    ```diff
    #{truncate_diff(diff)}
    ```
    """
  end

  defp build_followup_prompt(pr, diff, question) do
    """
    A developer is asking a follow-up question about this pull request.
    Answer their question directly and concisely.

    **PR Title**: #{pr.title}
    **Branch**: #{pr.head_branch} -> #{pr.base_branch}

    ## Diff

    ```diff
    #{truncate_diff(diff)}
    ```

    ## Question

    #{question}
    """
  end

  defp truncate_diff(diff) do
    max_chars = 100_000

    if String.length(diff) > max_chars do
      truncated = String.slice(diff, 0, max_chars)

      truncated <>
        "\n\n... (diff truncated, #{String.length(diff) - max_chars} characters omitted)"
    else
      diff
    end
  end

  defp post_review_result(ctx, result, token) do
    review_text = Map.get(result, :review, "Review completed.")
    verdict = Map.get(result, :verdict)
    verdict_label = if verdict == :approve, do: "APPROVED", else: "CHANGES REQUESTED"

    body = "**#{verdict_label}**\n\n#{review_text}"
    post_comment(ctx, body, token)
  end

  defp post_error(ctx, reason, token) do
    body =
      "I encountered an error while reviewing this PR: `#{inspect(reason)}`\n\nPlease try again or check the Pyre server logs."

    post_comment(ctx, body, token)
  end

  defp post_comment(ctx, body, token) do
    case ctx.in_reply_to do
      nil ->
        Pyre.GitHub.create_comment(ctx.owner, ctx.repo, ctx.pr_number, body, token)

      reply_to_id ->
        Pyre.GitHub.create_comment_reply(
          ctx.owner,
          ctx.repo,
          ctx.pr_number,
          reply_to_id,
          body,
          token
        )
    end
  end

  defp extract_text(%{__struct__: ReqLLM.Response} = response) do
    ReqLLM.Response.text(response) || ""
  end

  defp extract_text(text) when is_binary(text), do: text

  defp noop(_), do: :ok

  defp log_remote(msg) do
    Logger.info("[RemoteReview] #{msg}")
  end
end
