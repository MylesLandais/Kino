defmodule Adaptation.Filter do
  @moduledoc """
  Offline evaluator gate from experience runs to binned trajectories.

  This is the Adaptation Substrate's read of experience — never a live
  agent's memory lookup.
  """

  alias Adaptation.Trajectory
  alias Experience.Run
  alias Kino.Repo

  @spec ingest(Run.t(), map()) :: {:ok, Trajectory.t()} | {:error, term()}
  def ingest(%Run{} = run, evaluation) when is_map(evaluation) do
    score = Map.get(evaluation, :score) || Map.get(evaluation, "score")
    min_score = Map.get(evaluation, :min_score) || Map.get(evaluation, "min_score") || 0.0
    evidence = Map.get(evaluation, :evidence) || Map.get(evaluation, "evidence") || %{}
    bin = bin(run, score, min_score)

    Repo.transaction(fn ->
      {:ok, trajectory} =
        %Trajectory{}
        |> Trajectory.changeset(%{
          domain: run.domain,
          bin: bin,
          evaluator_score: score,
          evaluator_evidence: stringify_keys(evidence)
        })
        |> Repo.insert()

      Repo.insert_all("trajectory_sources", [
        %{
          trajectory_id: dump_uuid(trajectory.id),
          experience_run_id: dump_uuid(run.id)
        }
      ])

      Repo.preload(trajectory, :experience_runs)
    end)
  end

  defp bin(_run, score, min) when is_number(score) and is_number(min) and score < min,
    do: "discard"

  defp bin(%Run{outcome: outcome, reward: reward}, _score, _min) do
    cond do
      outcome in ["failure", "failed", "negative"] -> "negative"
      is_number(reward) and reward < 0 -> "negative"
      true -> "positive"
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp dump_uuid(id) when is_binary(id) do
    {:ok, dumped} = Ecto.UUID.dump(id)
    dumped
  end
end
