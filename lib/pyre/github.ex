defmodule Pyre.GitHub do
  @moduledoc """
  GitHub REST API client using Req.

  ## Configuration

  Configure repositories in your `config/runtime.exs`:

      config :pyre, :github,
        repositories: [
          [
            url: System.get_env("GITHUB_REPO_URL"),
            token: System.get_env("GITHUB_TOKEN"),
            base_branch: "main"
          ]
        ]

  Library consumers (e.g. a Phoenix app using `pyre` as a dependency) set
  this in their own `runtime.exs`.

  ## Example

      {:ok, config} = Pyre.GitHub.resolve_repo_config("owner", "repo")

      Pyre.GitHub.create_pull_request("owner", "repo", %{
        title: "Add products page",
        body: "Implements CRUD for products.",
        head: "feature-products-page",
        base: "main"
      }, config.token)

  """

  @base_url "https://api.github.com"

  @doc """
  Resolves GitHub configuration for a given owner/repo pair.

  When `installation_id` is provided and GitHub App is configured,
  uses App authentication. Otherwise falls back to PAT-based auth.

  Returns `{:ok, %{token: token, base_branch: base_branch}}` or
  `{:error, :token_not_set}`.
  """
  @spec resolve_repo_config(String.t(), String.t(), keyword()) ::
          {:ok, %{token: String.t(), base_branch: String.t()}} | {:error, term()}
  def resolve_repo_config(owner, repo, opts \\ []) do
    installation_id = opts[:installation_id]

    if Pyre.GitHub.App.configured?() and installation_id do
      case Pyre.GitHub.App.installation_token(installation_id) do
        {:ok, token} ->
          base_branch = opts[:base_branch] || "main"
          {:ok, %{token: token, base_branch: base_branch}}

        {:error, _} = error ->
          error
      end
    else
      resolve_pat_config(owner, repo)
    end
  end

  defp resolve_pat_config(owner, repo) do
    github_config = Application.get_env(:pyre, :github, [])
    repos = Keyword.get(github_config, :repositories, [])

    repo_entry =
      Enum.find(repos, fn entry ->
        case parse_remote_url(Keyword.get(entry, :url, "")) do
          {:ok, {entry_owner, entry_repo}} ->
            entry_owner == owner and entry_repo == repo

          _ ->
            false
        end
      end)

    token = if repo_entry, do: Keyword.get(repo_entry, :token)

    case token do
      nil ->
        {:error, :token_not_set}

      "" ->
        {:error, :token_not_set}

      t ->
        base_branch =
          if repo_entry,
            do: Keyword.get(repo_entry, :base_branch, "main"),
            else: "main"

        {:ok, %{token: t, base_branch: base_branch}}
    end
  end

  @doc """
  Creates a pull request on GitHub.

  ## Params

    * `:title` — PR title (required)
    * `:body` — PR description markdown (required)
    * `:head` — Branch name to merge from (required)
    * `:base` — Branch name to merge into (default: `"main"`)

  The `token` argument is a GitHub personal access token with `repo` scope.

  Returns `{:ok, %{url: html_url, number: number}}` on success,
  or `{:error, reason}` on failure.
  """
  @spec create_pull_request(String.t(), String.t(), map(), String.t()) ::
          {:ok, %{url: String.t(), number: integer()}} | {:error, term()}
  def create_pull_request(owner, repo, params, token) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      body = %{
        title: params[:title] || params.title,
        body: params[:body] || params.body,
        head: params[:head] || params.head,
        base: params[:base] || "main",
        draft: Map.get(params, :draft, false)
      }

      case Req.post("#{@base_url}/repos/#{owner}/#{repo}/pulls",
             json: body,
             headers: [
               {"authorization", "Bearer #{token}"},
               {"accept", "application/vnd.github+json"},
               {"x-github-api-version", "2022-11-28"}
             ]
           ) do
        {:ok, %{status: status, body: resp_body}} when status in [201] ->
          {:ok, %{url: resp_body["html_url"], number: resp_body["number"]}}

        {:ok, %{status: 422, body: resp_body}} ->
          message =
            get_in(resp_body, ["errors", Access.at(0), "message"]) || resp_body["message"]

          if String.contains?(message || "", "already exists") do
            find_open_pull_request(owner, repo, body.head, token)
          else
            {:error, {:validation_error, message}}
          end

        {:ok, %{status: status, body: resp_body}} ->
          {:error, {:api_error, status, resp_body["message"]}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @doc """
  Finds an open pull request by head branch.

  Returns `{:ok, %{url: html_url, number: number}}` if found,
  or `{:error, :not_found}` if none exists.
  """
  @spec find_open_pull_request(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, %{url: String.t(), number: integer()}} | {:error, term()}
  def find_open_pull_request(owner, repo, head_branch, token) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      case Req.get(
             "#{@base_url}/repos/#{owner}/#{repo}/pulls?head=#{owner}:#{head_branch}&state=open",
             headers: [
               {"authorization", "Bearer #{token}"},
               {"accept", "application/vnd.github+json"},
               {"x-github-api-version", "2022-11-28"}
             ]
           ) do
        {:ok, %{status: 200, body: [pr | _]}} ->
          {:ok, %{url: pr["html_url"], number: pr["number"]}}

        {:ok, %{status: 200, body: []}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: resp_body}} ->
          {:error, {:api_error, status, resp_body["message"]}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @doc """
  Creates a review on a GitHub pull request.

  ## Params

    * `owner` — Repository owner
    * `repo` — Repository name
    * `pr_number` — Pull request number
    * `body` — Review comment body (markdown)
    * `event` — Review event: `"APPROVE"`, `"REQUEST_CHANGES"`, or `"COMMENT"`
    * `token` — GitHub personal access token

  Returns `{:ok, %{id: review_id}}` on success, or `{:error, reason}` on failure.
  """
  @spec create_review(String.t(), String.t(), integer(), String.t(), String.t(), String.t()) ::
          {:ok, %{id: integer()}} | {:error, term()}
  def create_review(owner, repo, pr_number, body, event, token) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      request_body = %{body: body, event: event}

      case Req.post("#{@base_url}/repos/#{owner}/#{repo}/pulls/#{pr_number}/reviews",
             json: request_body,
             headers: [
               {"authorization", "Bearer #{token}"},
               {"accept", "application/vnd.github+json"},
               {"x-github-api-version", "2022-11-28"}
             ]
           ) do
        {:ok, %{status: 200, body: resp_body}} ->
          {:ok, %{id: resp_body["id"]}}

        {:ok, %{status: 422, body: resp_body}} ->
          message =
            get_in(resp_body, ["errors", Access.at(0), "message"]) || resp_body["message"]

          {:error, {:validation_error, message}}

        {:ok, %{status: status, body: resp_body}} ->
          {:error, {:api_error, status, resp_body["message"]}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @doc """
  Creates a comment on a GitHub pull request (issue comment, not a review).

  Returns `{:ok, %{id: comment_id}}` on success, or `{:error, reason}` on failure.
  """
  @spec create_comment(String.t(), String.t(), integer(), String.t(), String.t()) ::
          {:ok, %{id: integer()}} | {:error, term()}
  def create_comment(owner, repo, pr_number, body, token) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      case Req.post("#{@base_url}/repos/#{owner}/#{repo}/issues/#{pr_number}/comments",
             json: %{body: body},
             headers: [
               {"authorization", "Bearer #{token}"},
               {"accept", "application/vnd.github+json"},
               {"x-github-api-version", "2022-11-28"}
             ]
           ) do
        {:ok, %{status: 201, body: resp_body}} ->
          {:ok, %{id: resp_body["id"]}}

        {:ok, %{status: status, body: resp_body}} ->
          {:error, {:api_error, status, resp_body["message"]}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @doc """
  Marks a draft pull request as ready for review using the GraphQL API.

  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  @spec mark_ready_for_review(String.t(), String.t(), integer(), String.t()) ::
          :ok | {:error, term()}
  def mark_ready_for_review(owner, repo, pr_number, token) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      # First, get the PR's node_id via REST
      case Req.get("#{@base_url}/repos/#{owner}/#{repo}/pulls/#{pr_number}",
             headers: [
               {"authorization", "Bearer #{token}"},
               {"accept", "application/vnd.github+json"},
               {"x-github-api-version", "2022-11-28"}
             ]
           ) do
        {:ok, %{status: 200, body: resp_body}} ->
          node_id = resp_body["node_id"]
          mark_ready_graphql(node_id, token)

        {:ok, %{status: status, body: resp_body}} ->
          {:error, {:api_error, status, resp_body["message"]}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp mark_ready_graphql(pull_request_id, token) do
    query = """
    mutation($id: ID!) {
      markPullRequestReadyForReview(input: {pullRequestId: $id}) {
        pullRequest { number }
      }
    }
    """

    case Req.post("https://api.github.com/graphql",
           json: %{query: query, variables: %{id: pull_request_id}},
           headers: [
             {"authorization", "Bearer #{token}"},
             {"accept", "application/vnd.github+json"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"data" => _}}} ->
        :ok

      {:ok, %{status: 200, body: %{"errors" => errors}}} ->
        message = get_in(errors, [Access.at(0), "message"]) || inspect(errors)
        {:error, {:graphql_error, message}}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body["message"]}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Parses a GitHub remote URL into `{owner, repo}`.

  Supports both SSH and HTTPS formats:

      iex> Pyre.GitHub.parse_remote_url("git@github.com:owner/repo.git")
      {:ok, {"owner", "repo"}}

      iex> Pyre.GitHub.parse_remote_url("https://github.com/owner/repo.git")
      {:ok, {"owner", "repo"}}

  """
  @spec parse_remote_url(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, :invalid_url}
  def parse_remote_url(url) do
    url = String.trim(url)

    cond do
      # SSH: git@github.com:owner/repo.git
      String.match?(url, ~r{^git@github\.com:}) ->
        path = url |> String.replace(~r{^git@github\.com:}, "") |> String.replace(~r{\.git$}, "")
        parse_owner_repo(path)

      # HTTPS: https://github.com/owner/repo.git
      String.match?(url, ~r{^https?://github\.com/}) ->
        path =
          url
          |> String.replace(~r{^https?://github\.com/}, "")
          |> String.replace(~r{\.git$}, "")

        parse_owner_repo(path)

      true ->
        {:error, :invalid_url}
    end
  end

  defp parse_owner_repo(path) do
    case String.split(path, "/", parts: 2) do
      [owner, repo] when owner != "" and repo != "" -> {:ok, {owner, repo}}
      _ -> {:error, :invalid_url}
    end
  end

  @doc """
  Fetches pull request metadata from GitHub.

  Returns `{:ok, pr_map}` with title, body, author, branches, and stats.
  """
  @spec get_pull_request(String.t(), String.t(), integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def get_pull_request(owner, repo, pr_number, token) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      case Req.get("#{@base_url}/repos/#{owner}/#{repo}/pulls/#{pr_number}",
             headers: auth_headers(token)
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok,
           %{
             title: body["title"],
             body: body["body"],
             author: get_in(body, ["user", "login"]),
             head_branch: get_in(body, ["head", "ref"]),
             head_sha: get_in(body, ["head", "sha"]),
             base_branch: get_in(body, ["base", "ref"]),
             clone_url: get_in(body, ["head", "repo", "clone_url"]),
             changed_files: body["changed_files"],
             additions: body["additions"],
             deletions: body["deletions"]
           }}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body["message"]}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @doc """
  Fetches the raw diff for a pull request.
  """
  @spec get_pull_request_diff(String.t(), String.t(), integer(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def get_pull_request_diff(owner, repo, pr_number, token) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      case Req.get("#{@base_url}/repos/#{owner}/#{repo}/pulls/#{pr_number}",
             headers: [
               {"authorization", "Bearer #{token}"},
               {"accept", "application/vnd.github.diff"}
             ]
           ) do
        {:ok, %{status: 200, body: diff}} when is_binary(diff) ->
          {:ok, diff}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @doc """
  Replies to a specific inline review comment on a pull request.
  """
  @spec create_comment_reply(String.t(), String.t(), integer(), integer(), String.t(), String.t()) ::
          {:ok, %{id: integer()}} | {:error, term()}
  def create_comment_reply(owner, repo, pr_number, in_reply_to, body, token) do
    unless Code.ensure_loaded?(Req) do
      {:error, :req_not_available}
    else
      case Req.post("#{@base_url}/repos/#{owner}/#{repo}/pulls/#{pr_number}/comments",
             json: %{body: body, in_reply_to: in_reply_to},
             headers: auth_headers(token)
           ) do
        {:ok, %{status: 201, body: resp}} ->
          {:ok, %{id: resp["id"]}}

        {:ok, %{status: status, body: resp}} ->
          {:error, {:api_error, status, resp["message"]}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp auth_headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]
  end
end
