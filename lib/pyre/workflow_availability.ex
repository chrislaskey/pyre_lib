defmodule Pyre.WorkflowAvailability do
  @moduledoc """
  Computes per-workflow-type capacity from connected client metadata.

  Pure functions — no process state, no PubSub subscriptions.
  Consumers (LiveViews, QueueManager) call these with data they
  already have.
  """

  @type connection_info :: %{
          connection_id: String.t(),
          name: String.t(),
          available_capacity: non_neg_integer(),
          max_capacity: non_neg_integer()
        }

  @type capacity_info :: %{
          available_capacity: non_neg_integer(),
          total_max_capacity: non_neg_integer(),
          connections: [connection_info()]
        }

  @doc """
  Returns a map of `%{workflow_type_string => capacity_info}` for
  every workflow in the registry.

  Each `capacity_info` is:

      %{
        available_capacity: non_neg_integer(),
        total_max_capacity: non_neg_integer(),
        connections: [
          %{
            connection_id: String.t(),
            name: String.t(),
            available_capacity: non_neg_integer(),
            max_capacity: non_neg_integer()
          }
        ]
      }

  `connections` includes ALL active workers that are compatible
  with the workflow type, regardless of whether they currently have
  available capacity. This lets the UI distinguish "no workers
  exist" from "workers exist but are busy."

  General-purpose clients (empty `enabled_workflows`) are
  compatible with all workflow types. Specialist clients are
  compatible only with their declared types.
  """
  @spec capacity_by_type(list(map()), list(map())) :: %{String.t() => capacity_info()}
  def capacity_by_type(connections, workflows) do
    all_types = Enum.map(workflows, &to_string(&1.name))
    active = Enum.filter(connections, &active?/1)

    Map.new(all_types, fn type ->
      compatible =
        active
        |> Enum.filter(&workflow_compatible?(&1, type))
        |> Enum.map(fn meta ->
          %{
            connection_id: meta_val(meta, :connection_id),
            name: meta_val(meta, :name),
            available_capacity: meta_val(meta, :available_capacity) || 0,
            max_capacity: meta_val(meta, :max_capacity) || 0
          }
        end)

      info = %{
        available_capacity: Enum.reduce(compatible, 0, &(&1.available_capacity + &2)),
        total_max_capacity: Enum.reduce(compatible, 0, &(&1.max_capacity + &2)),
        connections: compatible
      }

      {type, info}
    end)
  end

  # A connection is active if it has status "active".
  # We do NOT filter by available_capacity > 0 here — that
  # happens at the consumer level (e.g., RunServer for worker
  # selection). For availability reporting, we want all active
  # connections so the UI can show busy vs absent.
  defp active?(meta) do
    status = meta_val(meta, :status) || "active"
    status == "active"
  end

  defp workflow_compatible?(meta, type) do
    enabled = meta_val(meta, :enabled_workflows) || []
    enabled == [] or type in enabled
  end

  defp meta_val(meta, key) do
    Map.get(meta, to_string(key)) || Map.get(meta, key)
  end
end
