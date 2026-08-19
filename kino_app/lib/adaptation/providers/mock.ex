defmodule Adaptation.Providers.Mock do
  @moduledoc "Deterministic provider for tests. Never ships weights."

  @behaviour Adaptation.Provider

  @impl true
  def build_dataset(trajectories, config) do
    Adaptation.Providers.LoRA.build_dataset(trajectories, config)
  end

  @impl true
  def train(_dataset_path, _base_model, config) do
    score = config[:train_score] || 0.9

    {:ok,
     %{
       artifact_uri:
         config[:artifact_uri] || "mock://adapter/#{System.unique_integer([:positive])}",
       version: config[:version] || "mock-#{System.unique_integer([:positive])}",
       metrics: %{"train_loss" => 0.01, "score" => score},
       provider: "mock"
     }}
  end

  @impl true
  def evaluate(artifact, suites, config) do
    score = config[:eval_score] || get_in(artifact, [:metrics, "score"]) || 0.9

    metrics =
      Map.new(suites, fn suite ->
        {suite, %{"score" => score, "passed" => score >= 0.5}}
      end)

    {:ok, metrics}
  end
end
