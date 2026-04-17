defmodule Pyre.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/chrislaskey/pyre_lib"

  def project do
    [
      app: :pyre,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      mod: {Pyre.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Pyre library"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv/pyre/personas .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end

  defp deps do
    [
      {:inflex, "~> 2.1"},
      {:igniter, "~> 0.7"},
      {:jido, "~> 2.2"},
      {:jido_ai, "~> 2.1"},
      {:jose, "~> 1.11"},
      {:req, "~> 0.5"},
      {:phoenix_live_view, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
    ]
  end
end
