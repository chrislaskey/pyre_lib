defmodule PyreWeb do
  @moduledoc """
  Web interface for the Pyre multi-agent LLM framework.

  PyreWeb provides a mountable Phoenix LiveView interface. Add it to your
  router with:

      import PyreWeb.Router

      scope "/" do
        pipe_through :browser
        pyre_web "/pyre"
      end
  """
end
