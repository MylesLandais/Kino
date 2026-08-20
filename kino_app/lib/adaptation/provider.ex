defmodule Adaptation.Provider do
  @moduledoc """
  Training/evaluation seam. Orchestration depends on this behaviour only.

  Weight adaptation is always out-of-band. There is no callback for live
  mutation of an `Adaptation.AgentProcess`.
  """

  @type trajectory :: Adaptation.Trajectory.t()
  @type config :: map()
  @type artifact :: %{
          required(:artifact_uri) => String.t(),
          required(:version) => String.t(),
          optional(:metrics) => map(),
          optional(:provider) => String.t()
        }
  @type metrics :: %{optional(String.t()) => term()}

  @callback build_dataset([trajectory()], config()) ::
              {:ok, String.t()} | {:error, term()}
  @callback train(String.t(), String.t(), config()) ::
              {:ok, artifact()} | {:error, term()}
  @callback evaluate(artifact(), [String.t()], config()) ::
              {:ok, metrics()} | {:error, term()}

  def build_dataset(trajectories, config \\ %{}) do
    impl().build_dataset(trajectories, config)
  end

  def train(dataset_path, base_model, config \\ %{}) do
    impl().train(dataset_path, base_model, config)
  end

  def evaluate(artifact, suites, config \\ %{}) do
    impl().evaluate(artifact, suites, config)
  end

  def impl do
    Application.get_env(:kino, Adaptation, [])
    |> Keyword.get(:provider, Adaptation.Providers.LoRA)
  end

  def name, do: impl() |> Module.split() |> List.last() |> Macro.underscore()
end
