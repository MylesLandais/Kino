defmodule Adaptation.PipelineTest do
  use Kino.DataCase, async: false
  use Oban.Testing, repo: Kino.Repo

  alias Adaptation.{Adapter, AgentProcess, Graph, Pipeline, Trajectory}

  setup do
    domain = "computer_use-#{System.unique_integer([:positive])}"

    Repo.insert_all("adaptation_domain_thresholds", [
      %{
        domain: domain,
        benchmark_suite: "desktop_success",
        metric: "score",
        threshold: 0.6,
        comparison: "gte"
      }
    ])

    Phoenix.PubSub.subscribe(Kino.PubSub, Pipeline.topic(domain))
    %{domain: domain}
  end

  test "experience runs are append-only and never appear on the agent process", %{domain: domain} do
    {:ok, run} =
      Experience.record_run(%{
        domain: domain,
        video_uri: "s3://exp/video.mp4",
        hid_log_uri: "s3://exp/hid.jsonl",
        tool_call_log_uri: "s3://exp/tools.jsonl",
        outcome: "success",
        reward: 1.0
      })

    refute function_exported?(AgentProcess, :recall_trajectories, 1)
    refute Map.has_key?(run, :retrieved_for_prompt)

    {:ok, _pid} = Adaptation.start_agent(domain: domain, base_model: "base")
    on_exit(fn -> Adaptation.stop_agent(domain) end)

    snapshot = AgentProcess.snapshot(domain)
    assert snapshot.memory_state == %{}
    refute Map.has_key?(snapshot, :trajectories)
    refute Map.has_key?(snapshot, :experience_runs)
  end

  test "filter bins a run into a trajectory Adaptation can train on", %{domain: domain} do
    {:ok, run} = Experience.record_run(%{domain: domain, outcome: "success", reward: 1.0})
    {:ok, %Trajectory{bin: "positive"} = trajectory} = Adaptation.ingest_run(run, %{score: 0.9})
    assert trajectory.domain == domain
    assert hd(trajectory.experience_runs).id == run.id
  end

  test "offline pipeline promotes through the provider seam and agents adopt a URI", %{
    domain: domain
  } do
    {:ok, run} = Experience.record_run(%{domain: domain, outcome: "success", reward: 1.0})
    {:ok, _} = Adaptation.ingest_run(run, %{score: 0.95, evidence: %{gate: "ok"}})

    {:ok, _pid} = Adaptation.start_agent(domain: domain)
    on_exit(fn -> Adaptation.stop_agent(domain) end)

    assert {:ok, %Adapter{status: "promoted", artifact_uri: uri, version: version}} =
             Pipeline.run(domain, eval_score: 0.95, version: "v-promote")

    assert_receive {:adaptation, %{decision: :promoted, version: ^version, artifact_uri: ^uri}}
    _ = :sys.get_state(AgentProcess.via(domain))
    assert %{version: ^version, uri: ^uri} = Adaptation.current_adapter_ref(domain)
    refute String.contains?(uri, "safetensors.bin://weights-inline")
  end

  test "below-threshold candidates are rejected and do not become the live reference", %{
    domain: domain
  } do
    {:ok, run} = Experience.record_run(%{domain: domain, outcome: "success", reward: 1.0})
    {:ok, _} = Adaptation.ingest_run(run, %{score: 0.95})
    {:ok, _pid} = Adaptation.start_agent(domain: domain)
    on_exit(fn -> Adaptation.stop_agent(domain) end)

    assert {:error, {:rejected, %Adapter{status: "rejected"}, {:below_threshold, _}}} =
             Pipeline.run(domain, eval_score: 0.1, version: "v-reject")

    assert_receive {:adaptation, %{decision: :rejected}}
    _ = :sys.get_state(AgentProcess.via(domain))
    assert %{version: nil, uri: nil} = Adaptation.current_adapter_ref(domain)
  end

  test "enqueue_train uses the adaptation Oban queue", %{domain: domain} do
    {:ok, run} = Experience.record_run(%{domain: domain, outcome: "success", reward: 1.0})
    {:ok, _} = Adaptation.ingest_run(run, %{score: 0.9})
    assert {:ok, job} = Adaptation.enqueue_train(domain, base_model: "base")
    assert job.queue == "adaptation"
    assert_enqueued(worker: Adaptation.Pipeline.Worker, args: %{"domain" => domain})
  end

  test "GRAPH_TABLE walks adapter lineage and rejected dataset sources", %{domain: domain} do
    {:ok, run} = Experience.record_run(%{domain: domain, outcome: "success", reward: 1.0})
    {:ok, _} = Adaptation.ingest_run(run, %{score: 0.9})

    assert {:ok, parent} = Pipeline.run(domain, eval_score: 0.95, version: "gen-0")

    assert {:ok, child} =
             Pipeline.run(domain,
               eval_score: 0.95,
               version: "gen-1",
               parent_adapter_id: parent.id
             )

    {:ok, run2} = Experience.record_run(%{domain: domain, outcome: "failure", reward: -1.0})
    {:ok, _} = Adaptation.ingest_run(run2, %{score: 0.9})

    assert {:error, {:rejected, rejected, _}} =
             Pipeline.run(domain,
               eval_score: 0.1,
               version: "gen-bad",
               parent_adapter_id: child.id
             )

    if pg19?() do
      assert {:ok, ancestors} = Graph.lineage_walk(child.id, 5)

      ancestor_ids =
        Enum.map(ancestors, fn row -> uuid(row["ancestor_id"] || row[:ancestor_id]) end)

      assert parent.id in ancestor_ids

      assert {:ok, rows} = Graph.trajectories_for_rejected_adapters(domain)

      assert Enum.any?(rows, fn row ->
               uuid(row["adapter_id"] || row[:adapter_id]) == rejected.id
             end)
    else
      flunk("maya_adaptation_graph requires PostgreSQL 19 SQL/PGQ")
    end
  end

  defp pg19? do
    %{rows: [[version]]} = Repo.query!("SHOW server_version_num")
    String.to_integer(version) >= 190_000
  end

  defp uuid(id) when is_binary(id) and byte_size(id) == 16, do: Ecto.UUID.load!(id)
  defp uuid(id) when is_binary(id), do: id
end
