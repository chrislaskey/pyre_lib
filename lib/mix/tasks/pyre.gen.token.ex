defmodule Mix.Tasks.Pyre.Gen.Token do
  @shortdoc "Generates a Pyre WebSocket service token"

  @moduledoc """
  Generates a cryptographically random service token for WebSocket auth.

  ## Usage

      mix pyre.gen.token

  The generated token uses a `pyre_tok_` prefix followed by 32 random bytes
  encoded as URL-safe Base64 (192 bits of entropy).

  Add the token to your environment:

      PYRE_WEBSOCKET_SERVICE_TOKENS_CSV=pyre_tok_...

  For multiple tokens, separate with commas:

      PYRE_WEBSOCKET_SERVICE_TOKENS_CSV=pyre_tok_aaa,pyre_tok_bbb
  """
  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      example: "mix pyre.gen.token"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    token = "pyre_tok_" <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))

    igniter
    |> Igniter.add_notice("""
    Generated service token:

      #{token}

    Add to your environment:

      PYRE_WEBSOCKET_SERVICE_TOKENS_CSV=#{token}

    For multiple tokens, separate with commas:

      PYRE_WEBSOCKET_SERVICE_TOKENS_CSV=#{token},<other-token>

    Client-side, set the single token:

      PYRE_CLIENT_WEBSOCKET_SERVICE_TOKEN=#{token}
    """)
  end
end
