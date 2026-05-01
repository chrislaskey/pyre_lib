import Config

if config_env() != :test do
  if api_key = System.get_env("ANTHROPIC_API_KEY") do
    config :req_llm, anthropic_api_key: api_key
  end

  if api_key = System.get_env("OPENAI_API_KEY") do
    config :req_llm, openai_api_key: api_key
  end

  if System.get_env("GITHUB_REPO_URL") do
    config :pyre, :github,
      repositories: [
        [
          url: System.get_env("GITHUB_REPO_URL"),
          token: System.get_env("GITHUB_TOKEN"),
          base_branch: System.get_env("GITHUB_BASE_BRANCH", "main")
        ]
      ]
  end

  if System.get_env("PYRE_GITHUB_APP_ID") do
    config :pyre, :github_apps, [
      [
        app_id: System.get_env("PYRE_GITHUB_APP_ID"),
        private_key: System.get_env("PYRE_GITHUB_APP_PRIVATE_KEY"),
        webhook_secret: System.get_env("PYRE_GITHUB_WEBHOOK_SECRET"),
        bot_slug: System.get_env("PYRE_GITHUB_APP_BOT_SLUG")
      ]
    ]
  end

  if tokens = System.get_env("PYRE_WEBSOCKET_SERVICE_TOKENS_CSV") do
    config :pyre, :websocket_service_tokens, tokens
  end
end
