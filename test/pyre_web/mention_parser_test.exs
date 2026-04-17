defmodule PyreWeb.MentionParserTest do
  use ExUnit.Case, async: true

  alias PyreWeb.MentionParser

  @bot "pyre-review"

  describe "parse/2 — known commands" do
    test "bare mention defaults to :review" do
      assert {:ok, {:review, []}} = MentionParser.parse("@#{@bot}", @bot)
    end

    test "explicit review command" do
      assert {:ok, {:review, []}} = MentionParser.parse("@#{@bot} review", @bot)
    end

    test "review is case-insensitive" do
      assert {:ok, {:review, []}} = MentionParser.parse("@#{@bot} Review", @bot)
      assert {:ok, {:review, []}} = MentionParser.parse("@#{@bot} REVIEW", @bot)
    end

    test "explain command with args" do
      assert {:ok, {:explain, [args: "the auth changes"]}} =
               MentionParser.parse("@#{@bot} explain the auth changes", @bot)
    end

    test "explain command without args" do
      assert {:ok, {:explain, []}} = MentionParser.parse("@#{@bot} explain", @bot)
    end

    test "help command" do
      assert {:ok, {:help, []}} = MentionParser.parse("@#{@bot} help", @bot)
    end
  end

  describe "parse/2 — followup (unrecognized commands)" do
    test "unrecognized text becomes followup" do
      assert {:ok, {:followup, "what about error handling?"}} =
               MentionParser.parse("@#{@bot} what about error handling?", @bot)
    end

    test "followup preserves full text" do
      assert {:ok, {:followup, "can you also check the tests?"}} =
               MentionParser.parse("@#{@bot} can you also check the tests?", @bot)
    end
  end

  describe "parse/2 — ignore cases" do
    test "no mention returns :ignore" do
      assert :ignore = MentionParser.parse("no mention here", @bot)
    end

    test "empty string returns :ignore" do
      assert :ignore = MentionParser.parse("", @bot)
    end

    test "mention inside code block is ignored" do
      body = "```\n@#{@bot} review\n```"
      assert :ignore = MentionParser.parse(body, @bot)
    end

    test "mention inside multi-line code block is ignored" do
      body = "Some text\n```elixir\n@#{@bot} review\nmore code\n```\noutside"
      assert :ignore = MentionParser.parse(body, @bot)
    end

    test "mention inside blockquote is ignored" do
      body = "> @#{@bot} review"
      assert :ignore = MentionParser.parse(body, @bot)
    end
  end

  describe "parse/2 — edge cases" do
    test "mention with surrounding text" do
      body = "Hey @#{@bot} review this please"
      assert {:ok, {:review, [args: "this please"]}} = MentionParser.parse(body, @bot)
    end

    test "mention on second line" do
      body = "First line\n@#{@bot} review"
      assert {:ok, {:review, []}} = MentionParser.parse(body, @bot)
    end

    test "code block filtered but mention outside preserved" do
      body = "```\nsome code\n```\n@#{@bot} review"
      assert {:ok, {:review, []}} = MentionParser.parse(body, @bot)
    end

    test "blockquote filtered but mention outside preserved" do
      body = "> quoted text\n@#{@bot} explain the changes"
      assert {:ok, {:explain, [args: "the changes"]}} = MentionParser.parse(body, @bot)
    end
  end
end
