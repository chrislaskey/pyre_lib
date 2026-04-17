defmodule Pyre.Plugins.Persona do
  @moduledoc """
  Loads persona Markdown files and builds LLM message structures.

  Personas are loaded from the consuming project's `priv/pyre/personas/`
  directory, with fallback to the library's built-in personas.
  """

  @doc """
  Loads a persona Markdown file by name.

  The name should be an atom matching the filename without extension
  (e.g., `:product_manager` loads `product_manager.md`).
  """
  @spec load(atom()) :: {:ok, String.t()} | {:error, term()}
  def load(persona_name) do
    filename = "#{persona_name}.md"
    project_path = Path.join(project_personas_dir(), filename)

    cond do
      File.exists?(project_path) ->
        File.read(project_path)

      File.exists?(library_path = Path.join(library_personas_dir(), filename)) ->
        File.read(library_path)

      true ->
        {:error,
         {:persona_not_found, persona_name,
          "Persona file '#{filename}' not found. " <>
            "Looked in #{project_personas_dir()} and #{library_personas_dir()}. " <>
            "Run `mix pyre.install` to set up Pyre, or check that the :pyre dependency is up to date."}}
    end
  end

  @doc """
  Returns a system message map for the given persona.
  """
  @spec system_message(atom()) :: {:ok, map()} | {:error, term()}
  def system_message(persona_name) do
    case load(persona_name) do
      {:ok, content} -> {:ok, %{role: :system, content: content}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Builds a user message map for an agent stage.

  Assembles the feature description, any prompt attachments, any artifacts
  from prior stages, and output instructions telling the agent where to
  write its artifact.

  When image attachments are present, returns multipart content (a list of
  content parts) instead of a plain string.
  """
  @spec user_message(String.t(), String.t(), String.t(), String.t(), [map()]) :: map()
  def user_message(
        feature_description,
        artifacts_content,
        run_dir,
        artifact_filename,
        attachments \\ []
      ) do
    alias Pyre.Plugins.Artifact

    text_attachments = Enum.filter(attachments, &Artifact.text_attachment?/1)
    image_attachments = Enum.filter(attachments, &Artifact.image_attachment?/1)

    sections = workspace_section()

    sections = sections ++ ["## Feature Request\n\n#{feature_description}"]

    sections =
      if text_attachments != [] do
        attachment_sections =
          Enum.map(text_attachments, fn att ->
            "### #{att.filename}\n\n#{att.content}"
          end)

        sections ++ ["## Prompt Attachments\n\n#{Enum.join(attachment_sections, "\n\n")}"]
      else
        sections
      end

    sections =
      if artifacts_content != "" do
        sections ++ ["## Prior Artifacts\n\n#{artifacts_content}"]
      else
        sections
      end

    output_path = Path.join(run_dir, artifact_filename)

    sections =
      sections ++
        [
          "## Output Instructions\n\nAfter completing your work, write a summary to: `#{output_path}`\n\nThe summary should be a Markdown document following the format specified in your persona instructions."
        ]

    text_body = Enum.join(sections, "\n\n")

    alias ReqLLM.Message.ContentPart

    if image_attachments == [] do
      %{role: :user, content: text_body}
    else
      image_parts =
        Enum.map(image_attachments, fn att ->
          ContentPart.image(att.content, att.media_type)
        end)

      %{role: :user, content: [ContentPart.text(text_body) | image_parts]}
    end
  end

  defp workspace_section do
    with allowed_paths when is_list(allowed_paths) <- Application.get_env(:pyre, :allowed_paths),
         normalized_paths when normalized_paths != [] <-
           normalize_allowed_paths(allowed_paths) do
      allowed_lines =
        normalized_paths
        |> Enum.map(&"  - `#{&1}`")
        |> Enum.join("\n")

      [
        """
        ## Workspace Constraints
        - Allowed directories for file modifications:
        #{allowed_lines}

        ### Rules
        - The prompt will refer to changes to be made in the project directory or one of the allowed directories above.
        - Only create, edit, move, or delete files inside the allowed directories above.
        - Do not modify files outside allowed directories. If a requested change requires that, explain the limitation and stop.
        """
        |> String.trim()
      ]
    else
      _ -> []
    end
  end

  defp normalize_allowed_paths(allowed_paths) do
    allowed_paths
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp project_personas_dir do
    Path.join(File.cwd!(), "priv/pyre/personas")
  end

  defp library_personas_dir do
    Application.app_dir(:pyre, "priv/pyre/personas")
  end
end
