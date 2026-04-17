defmodule PyreWeb.Presence do
  @moduledoc """
  Tracks connected Pyre native app instances via Phoenix.Presence.

  Uses the PubSub server configured via `config :pyre, :pubsub` — no
  additional Presence-specific configuration is needed.

  ## Host App Setup

  Add `PyreWeb.Presence` to your supervision tree:

      # lib/my_app/application.ex
      children = [
        # ... existing children ...
        PyreWeb.Presence
      ]
  """
  use Phoenix.Presence,
    otp_app: :pyre_web,
    pubsub_server: Phoenix.PubSub

  defoverridable child_spec: 1

  @topic "pyre:connections"

  @doc false
  def child_spec(opts) do
    pubsub = Application.get_env(:pyre, :pubsub)

    if pubsub do
      Application.put_env(:pyre_web, __MODULE__, pubsub_server: pubsub)
    end

    super(opts)
  end

  @doc """
  Returns `true` if the Presence tracker has been started.

  When the host app has not added `PyreWeb.Presence` to its supervision
  tree, all presence operations gracefully no-op.
  """
  def running? do
    :ets.whereis(__MODULE__) != :undefined
  end

  @doc """
  Returns simplified presence data for the connections topic.

  Each entry is a map with `"connection_id"` plus whatever metadata the
  client sent on join. Metadata is stored as-is (string keys from JSON).
  Clients can update their metadata at any time via the `"update_metadata"`
  channel message.

  Returns `[]` if Presence is not running.
  """
  def list_connections do
    if running?() do
      @topic
      |> list()
      |> Enum.map(fn {connection_id, %{metas: [meta | _]}} ->
        Map.put(meta, :connection_id, connection_id)
      end)
    else
      []
    end
  end
end
