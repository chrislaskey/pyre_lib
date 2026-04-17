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

  describe "default/0" do
    test "delegates to Pyre.Config.get_llm_backend/1" do
      assert is_atom(Pyre.LLM.default())
    end
  end

  describe "validate_backend!/0" do
    setup do
      original = Application.get_env(:pyre, :config)
      on_exit(fn -> Application.put_env(:pyre, :config, original) end)
      :ok
    end

    test "succeeds with a valid backend" do
      assert :ok = Pyre.LLM.validate_backend!()
    end

    test "raises for a module missing required callbacks" do
      defmodule IncompleteBackend do
        def manages_tool_loop?, do: false
      end

      defmodule BadConfig do
        use Pyre.Config

        @impl true
        def get_llm_backend(_arg), do: IncompleteBackend
      end

      Application.put_env(:pyre, :config, BadConfig)

      assert_raise ArgumentError, ~r/missing: generate\/3, stream\/3, chat\/4/, fn ->
        Pyre.LLM.validate_backend!()
      end
    end
  end
end
