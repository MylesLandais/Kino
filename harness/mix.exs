defmodule Harness.MixProject do
  use Mix.Project

  def project do
    [
      app: :harness,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Harness.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.3"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      precommit: ["compile --warnings-as-errors", "format", "test"]
    ]
  end
end
