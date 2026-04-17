defmodule Pyre.Flows.CodeReviewTest do
  use ExUnit.Case, async: false

  alias Pyre.Flows.CodeReview

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "pyre_cr_test_#{System.unique_integer([:positive])}")
    features_dir = Path.join(tmp_dir, "priv/pyre/features")
    File.mkdir_p!(features_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir}
  end

  defp with_cwd(dir, fun) do
    original = File.cwd!()
    File.cd!(dir)

    try do
      fun.()
    after
      File.cd!(original)
    end
  end

  test "runs review to completion with approve verdict", %{tmp_dir: tmp_dir} do
    Process.put(:mock_llm_responses, [
      "APPROVE\n\nGreat work!"
    ])

    result =
      with_cwd(tmp_dir, fn ->
        CodeReview.run("Review the authentication changes",
          llm: Pyre.LLM.Mock,
          streaming: false,
          project_dir: tmp_dir
        )
      end)

    assert {:ok, state} = result
    assert state.phase == :complete
    assert state.verdict == :approve
    assert state.review =~ "APPROVE"
  end

  test "dry run skips LLM calls", %{tmp_dir: tmp_dir} do
    result =
      with_cwd(tmp_dir, fn ->
        CodeReview.run("Review the changes",
          llm: Pyre.LLM.Mock,
          streaming: false,
          dry_run: true,
          project_dir: tmp_dir
        )
      end)

    assert {:ok, state} = result
    assert state.phase == :complete
  end

  test "propagates error from a failing action", %{tmp_dir: tmp_dir} do
    defmodule FailingLLM do
      use Pyre.LLM
      def generate(_, _, _ \\ []), do: {:error, :llm_failure}
      def stream(_, _, _ \\ []), do: {:error, :llm_failure}
      def chat(_, _, _, _ \\ []), do: {:error, :llm_failure}
    end

    result =
      with_cwd(tmp_dir, fn ->
        CodeReview.run("Review changes",
          llm: FailingLLM,
          streaming: false,
          project_dir: tmp_dir,
          log_fn: fn _ -> :ok end
        )
      end)

    assert {:error, :llm_failure} = result
  end
end
