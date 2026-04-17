Application.put_env(:pyre_web, PyreWeb.Test.Endpoint,
  url: [host: "localhost", port: 4000],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "pyre_web_test"],
  check_origin: false,
  pubsub_server: PyreWeb.Test.PubSub
)

Application.put_env(:pyre, :pubsub, PyreWeb.Test.PubSub)

defmodule PyreWeb.Test.Router do
  use Phoenix.Router
  import PyreWeb.Router

  pipeline :browser do
    plug :fetch_session
  end

  scope "/" do
    pipe_through :browser
    pyre_web("/pyre")
  end
end

defmodule PyreWeb.Test.Endpoint do
  use Phoenix.Endpoint, otp_app: :pyre_web

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason,
    body_reader: {PyreWeb.WebhookPlug, :read_body, []}

  plug Plug.Session,
    store: :cookie,
    key: "_pyre_web_key",
    signing_salt: "pyre_web_test"

  plug PyreWeb.Test.Router
end

# Pyre application auto-starts Registry, DynamicSupervisor, and
# Jido starts its TaskSupervisor. We start PubSub, Presence, ReviewQueue,
# and the test endpoint here since pyre_web is a library (no Application).
Supervisor.start_link(
  [
    {Phoenix.PubSub, name: PyreWeb.Test.PubSub},
    PyreWeb.Presence,
    PyreWeb.ReviewQueue,
    PyreWeb.Test.Endpoint
  ],
  strategy: :one_for_one
)

ExUnit.start()
