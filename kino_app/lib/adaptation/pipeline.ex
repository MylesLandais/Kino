defmodule Adaptation.Pipeline do
  @moduledoc """
  Offline adaptation flow. Never runs inside `Adaptation.AgentProcess`.

      Experience Run → Filter → Trajectory → build_dataset → train
        → evaluate → threshold → promote | reject
  """

  import Ecto.Query

  alias Adaptation.{Adapter, BenchmarkResult, Filter, Provider, Thresholds, Trajectory}
  alias Experience.Run
  alias Kino.Repo

  @topic "adaptation"

  def topic, do: @topic
  def topic(domain), do: @topic <> ":" <> domain

  def ingest_run(%Run{} = run, evaluation) do
    Filter.ingest(run, evaluation)
  end

  def enqueue_train(domain, opts \\ []) when is_binary(domain) do
    %{
      "domain" => domain,
      "base_model" => Keyword.get(opts, :base_model, "base"),
      "parent_adapter_id" => Keyword.get(opts, :parent_adapter_id)
    }
    |> Adaptation.Pipeline.Worker.new()
    |> Oban.insert()
  end

  def run(domain, opts \\ []) when is_binary(domain) do
    config = Map.new(opts)
    base_model = config[:base_model] || "base"
    trajectories = trainable_trajectories(domain)
    suites = Thresholds.suites(domain)

    with true <- trajectories != [] || {:error, :no_trajectories},
         true <- suites != [] || {:error, {:no_thresholds, domain}},
         {:ok, dataset} <- Provider.build_dataset(trajectories, config),
         {:ok, artifact} <- Provider.train(dataset, base_model, config),
         {:ok, metrics} <- Provider.evaluate(artifact, suites, config),
         {:ok, adapter} <- persist_candidate(domain, base_model, artifact, trajectories, config) do
      persist_benchmarks(adapter, metrics)

      case Thresholds.pass?(domain, metrics) do
        :ok ->
          promote(adapter, config[:parent_adapter_id])

        {:error, reason} ->
          reject(adapter, reason)
      end
    end
  end

  def current_adapter(domain) do
    from(a in Adapter,
      where: a.domain == ^domain and a.status == "promoted",
      order_by: [desc: a.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp trainable_trajectories(domain) do
    from(t in Trajectory,
      where: t.domain == ^domain and t.bin in ["positive", "negative"],
      preload: [:experience_runs]
    )
    |> Repo.all()
  end

  defp persist_candidate(domain, base_model, artifact, trajectories, config) do
    Repo.transaction(fn ->
      {:ok, adapter} =
        %Adapter{}
        |> Adapter.changeset(%{
          domain: domain,
          base_model: base_model,
          provider: artifact[:provider] || Provider.name(),
          version: artifact.version,
          artifact_uri: artifact.artifact_uri,
          training_config: stringify(Map.drop(config, [:parent_adapter_id])),
          metrics: stringify(artifact[:metrics] || %{}),
          status: "candidate"
        })
        |> Repo.insert()

      now_rows =
        Enum.map(trajectories, fn t ->
          %{adapter_id: dump_uuid(adapter.id), trajectory_id: dump_uuid(t.id)}
        end)

      if now_rows != [], do: Repo.insert_all("adapter_dataset_sources", now_rows)

      adapter
    end)
  end

  defp persist_benchmarks(adapter, metrics) do
    Enum.each(metrics, fn {suite, suite_metrics} ->
      suite_metrics = stringify(suite_metrics)
      passed = suite_metrics["passed"] == true or suite_metrics["passed"] == "true"

      %BenchmarkResult{}
      |> BenchmarkResult.changeset(%{
        adapter_id: adapter.id,
        suite: to_string(suite),
        metrics: suite_metrics,
        passed: passed
      })
      |> Repo.insert!()
    end)
  end

  defp promote(adapter, parent_id) do
    Repo.transaction(fn ->
      retire_current(adapter.domain)

      {:ok, adapter} =
        adapter
        |> Adapter.changeset(%{status: "promoted"})
        |> Repo.update()

      if parent_id do
        Repo.insert_all("adapter_lineage", [
          %{adapter_id: dump_uuid(adapter.id), parent_adapter_id: dump_uuid(parent_id)}
        ])
      end

      broadcast(:promoted, adapter)
      adapter
    end)
  end

  defp reject(adapter, reason) do
    {:ok, adapter} =
      adapter
      |> Adapter.changeset(%{
        status: "rejected",
        metrics: Map.put(adapter.metrics, "reject_reason", inspect(reason))
      })
      |> Repo.update()

    broadcast(:rejected, adapter)
    {:error, {:rejected, adapter, reason}}
  end

  defp retire_current(domain) do
    from(a in Adapter, where: a.domain == ^domain and a.status == "promoted")
    |> Repo.update_all(set: [status: "retired", updated_at: DateTime.utc_now(:second)])
  end

  defp broadcast(decision, adapter) do
    payload = %{
      decision: decision,
      domain: adapter.domain,
      adapter_id: adapter.id,
      version: adapter.version,
      artifact_uri: adapter.artifact_uri,
      metrics: adapter.metrics
    }

    Phoenix.PubSub.broadcast(Kino.PubSub, topic(), {:adaptation, payload})
    Phoenix.PubSub.broadcast(Kino.PubSub, topic(adapter.domain), {:adaptation, payload})
    :telemetry.execute([:harness, :adaptation, decision], %{count: 1}, %{domain: adapter.domain})
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(%_{} = struct), do: struct
  defp stringify_value(map) when is_map(map), do: stringify(map)
  defp stringify_value(other), do: other

  defp dump_uuid(id) when is_binary(id) do
    {:ok, dumped} = Ecto.UUID.dump(id)
    dumped
  end
end
