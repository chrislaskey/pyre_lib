import Config

config :jido_ai,
  model_aliases: %{
    fast: "anthropic:claude-haiku-4-5",
    standard: "anthropic:claude-sonnet-4-20250514",
    advanced: "anthropic:claude-opus-4-20250514"
  }

config :phoenix, :json_library, Jason

if config_env() == :test do
  config :logger, level: :warning
end

import_config "#{config_env()}.exs"
