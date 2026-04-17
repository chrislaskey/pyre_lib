defmodule PyreWeb.ReviewQueue do
  @moduledoc """
  Async review job queue with bounded concurrency.

  Webhook handlers enqueue jobs, which are processed by spawned tasks.
  Concurrency is bounded to avoid overwhelming LLM APIs.

  ## Host App Setup

  Add `PyreWeb.ReviewQueue` to your supervision tree to enable
  webhook-triggered PR reviews:

      # lib/my_app/application.ex
      children = [
        # ... existing children ...
        PyreWeb.ReviewQueue
      ]

  When not started, webhook mentions are silently ignored.
  """

  use GenServer

  require Logger

  @max_concurrency 2
  @duplicate_cooldown_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueues a review job. Returns :ok immediately.
  Duplicate jobs (same PR + command within cooldown) are silently dropped.
  """
  def enqueue(job) do
    GenServer.cast(__MODULE__, {:enqueue, job})
  end

  @doc """
  Returns `true` if the ReviewQueue has been started.

  When the host app has not added `PyreWeb.ReviewQueue` to its supervision
  tree, webhook mentions are silently ignored.
  """
  def running? do
    is_pid(Process.whereis(__MODULE__))
  end

  @impl true
  def init(_opts) do
    {:ok, _} = Task.Supervisor.start_link(name: PyreWeb.ReviewTaskSupervisor)
    {:ok, %{queue: :queue.new(), active: 0, recent: %{}}}
  end

  @impl true
  def handle_cast({:enqueue, job}, state) do
    job_key = {job.owner, job.repo, job.pr_number, job.command}
    now = System.monotonic_time(:millisecond)

    if duplicate?(state.recent, job_key, now) do
      Logger.debug("ReviewQueue: dropping duplicate job #{inspect(job_key)}")
      {:noreply, state}
    else
      recent = Map.put(state.recent, job_key, now)
      state = %{state | queue: :queue.in(job, state.queue), recent: recent}
      {:noreply, maybe_process(state)}
    end
  end

  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Task completed successfully - clean up the monitor
    Process.demonitor(ref, [:flush])
    state = %{state | active: state.active - 1}
    {:noreply, maybe_process(state)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    state = %{state | active: state.active - 1}
    {:noreply, maybe_process(state)}
  end

  defp maybe_process(%{active: active} = state) when active >= @max_concurrency, do: state

  defp maybe_process(state) do
    case :queue.out(state.queue) do
      {{:value, job}, queue} ->
        Task.Supervisor.async_nolink(PyreWeb.ReviewTaskSupervisor, fn ->
          apply(Pyre.RemoteReview, :run, [job])
        end)

        %{state | queue: queue, active: state.active + 1}

      {:empty, _queue} ->
        state
    end
  end

  defp duplicate?(recent, key, now) do
    case Map.get(recent, key) do
      nil -> false
      last_time -> now - last_time < @duplicate_cooldown_ms
    end
  end
end
