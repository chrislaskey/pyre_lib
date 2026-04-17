defmodule PyreWeb.Test.AgentMock do
  @moduledoc false
  use Pyre.LLM

  @agent_name __MODULE__.Responses

  def setup(responses) do
    case GenServer.whereis(@agent_name) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end

    {:ok, _pid} = Agent.start_link(fn -> responses end, name: @agent_name)
    :ok
  end

  def teardown do
    case GenServer.whereis(@agent_name) do
      nil ->
        :ok

      pid ->
        try do
          Agent.stop(pid)
        catch
          :exit, _ -> :ok
        end
    end
  end

  defp next do
    Agent.get_and_update(@agent_name, fn
      [r | rest] -> {r, rest}
      [] -> {"Mock response (exhausted)", []}
    end)
  end

  @impl true
  def generate(_model, _messages, _opts \\ []), do: {:ok, next()}

  @impl true
  def stream(_model, _messages, _opts \\ []), do: {:ok, next()}

  @impl true
  def chat(_model, _messages, _tools, _opts \\ []) do
    text = next()

    response = %ReqLLM.Response{
      id: "mock_#{System.unique_integer([:positive])}",
      model: "mock",
      context: ReqLLM.Context.new(),
      finish_reason: :stop,
      message: %ReqLLM.Message{
        role: :assistant,
        content: [%ReqLLM.Message.ContentPart{type: :text, text: text}]
      }
    }

    {:ok, response}
  end
end
