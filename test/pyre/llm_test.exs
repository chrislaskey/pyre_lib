defmodule Pyre.LLMTest do
  use ExUnit.Case, async: false

  describe "use Pyre.LLM" do
    defmodule MinimalBackend do
      use Pyre.LLM

      @impl true
      def generate(_, _, _ \\ []), do: {:ok, "generated"}
      @impl true
      def stream(_, _, _ \\ []), do: {:ok, "streamed"}
      @impl true
      def chat(_, _, _, _ \\ []), do: {:ok, "chatted"}
    end

    defmodule ToolLoopBackend do
      use Pyre.LLM

      @impl true
      def manages_tool_loop?, do: true

      @impl true
      def generate(_, _, _ \\ []), do: {:ok, "generated"}
      @impl true
      def stream(_, _, _ \\ []), do: {:ok, "streamed"}
      @impl true
      def chat(_, _, _, _ \\ []), do: {:ok, "chatted"}
    end

    test "provides default manages_tool_loop? returning false" do
      assert MinimalBackend.manages_tool_loop?() == false
    end

    test "allows overriding manages_tool_loop?" do
      assert ToolLoopBackend.manages_tool_loop?() == true
    end

    test "sets up @behaviour Pyre.LLM" do
      assert function_exported?(MinimalBackend, :generate, 3)
      assert function_exported?(MinimalBackend, :stream, 3)
      assert function_exported?(MinimalBackend, :chat, 4)
      assert function_exported?(MinimalBackend, :manages_tool_loop?, 0)
    end
  end
end
