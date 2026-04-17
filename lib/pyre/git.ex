defmodule Pyre.Git do
  @moduledoc """
  Git operations for remote PR review: clone, diff, cleanup.
  """

  require Logger

  @doc """
  Clones a repo and checks out the given branch into a temp directory.

  Uses `--depth 50` for a shallow clone. Authenticates by injecting the
  token into the HTTPS clone URL.

  Returns `{:ok, tmp_dir}` or `{:error, reason}`.
  """
  def clone_and_checkout(clone_url, branch, token) do
    tmp_dir = Path.join(System.tmp_dir!(), "pyre-review-#{random_hex(8)}")
    auth_url = inject_token(clone_url, token)

    case System.cmd("git", ["clone", "--depth", "50", "--branch", branch, auth_url, tmp_dir],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        {:ok, tmp_dir}

      {output, code} ->
        {:error, {:clone_failed, code, sanitize_output(output, token)}}
    end
  end

  @doc """
  Computes the diff between the current HEAD and the merge-base with the
  given base branch (e.g., "main").
  """
  def diff(repo_dir, base_branch) do
    case System.cmd("git", ["fetch", "origin", base_branch, "--depth=50"],
           cd: repo_dir,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        case System.cmd("git", ["diff", "origin/#{base_branch}...HEAD"],
               cd: repo_dir,
               stderr_to_stdout: true
             ) do
          {diff_output, 0} -> {:ok, diff_output}
          {output, code} -> {:error, {:diff_failed, code, output}}
        end

      {output, code} ->
        {:error, {:fetch_failed, code, output}}
    end
  end

  @doc """
  Removes a temporary clone directory.
  """
  def cleanup(tmp_dir) do
    if String.starts_with?(tmp_dir, System.tmp_dir!()) do
      File.rm_rf(tmp_dir)
      :ok
    else
      Logger.warning("Pyre.Git.cleanup refused to delete #{tmp_dir} (not in tmp dir)")
      {:error, :unsafe_path}
    end
  end

  # --- Private ---

  defp inject_token(url, token) do
    String.replace(url, "https://", "https://x-access-token:#{token}@")
  end

  defp sanitize_output(output, token) do
    String.replace(output, token, "[REDACTED]")
  end

  defp random_hex(bytes) do
    :crypto.strong_rand_bytes(bytes) |> Base.encode16(case: :lower)
  end
end
