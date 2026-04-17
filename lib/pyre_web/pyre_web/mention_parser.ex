defmodule PyreWeb.MentionParser do
  @moduledoc """
  Parses GitHub comment bodies for @bot-name mentions and commands.
  """

  @type command ::
          {:review, keyword()}
          | {:explain, keyword()}
          | {:help, keyword()}
          | {:followup, String.t()}

  @known_commands ~w(review explain help)

  @doc """
  Parses a comment body for a @bot mention and command.

  Returns `{:ok, command}` if a mention is found with a recognized command,
  or `:ignore` if no mention is present or the mention is inside a code block
  or blockquote.

  ## Examples

      iex> PyreWeb.MentionParser.parse("@pyre-review review", "pyre-review")
      {:ok, {:review, []}}

      iex> PyreWeb.MentionParser.parse("@pyre-review explain the auth changes", "pyre-review")
      {:ok, {:explain, [args: "the auth changes"]}}

      iex> PyreWeb.MentionParser.parse("@pyre-review what about error handling?", "pyre-review")
      {:ok, {:followup, "what about error handling?"}}

      iex> PyreWeb.MentionParser.parse("no mention here", "pyre-review")
      :ignore

      iex> PyreWeb.MentionParser.parse("```\\n@pyre-review review\\n```", "pyre-review")
      :ignore

  """
  @spec parse(String.t(), String.t()) :: {:ok, command()} | :ignore
  def parse(body, bot_slug) do
    stripped = body |> strip_code_blocks() |> strip_blockquotes()
    mention = "@#{bot_slug}"

    case extract_mention(stripped, mention) do
      nil -> :ignore
      text_after_mention -> {:ok, parse_command(String.trim(text_after_mention))}
    end
  end

  defp strip_code_blocks(text) do
    Regex.replace(~r/```[\s\S]*?```/m, text, "")
  end

  defp strip_blockquotes(text) do
    text
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(String.trim_leading(&1), ">"))
    |> Enum.join("\n")
  end

  defp extract_mention(text, mention) do
    case Regex.run(~r/#{Regex.escape(mention)}\s*(.*)/is, text) do
      [_, rest] -> rest
      nil -> nil
    end
  end

  defp parse_command(""), do: {:review, []}

  defp parse_command(text) do
    [first | rest] = String.split(text, ~r/\s+/, parts: 2)
    first_lower = String.downcase(first)

    if first_lower in @known_commands do
      {String.to_existing_atom(first_lower), parse_args(rest)}
    else
      {:followup, text}
    end
  end

  defp parse_args([]), do: []
  defp parse_args([arg_string]), do: [args: String.trim(arg_string)]
end
