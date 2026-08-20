defmodule Kino.Repo.Migrations.CreateMayaAdaptationGraph do
  use Ecto.Migration

  def up do
    create table(:experience_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :text, null: false
      add :environment_id, :text
      add :video_uri, :text
      add :hid_log_uri, :text
      add :tool_call_log_uri, :text
      add :outcome, :text
      add :reward, :float
      add :attrs, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:experience_runs, [:domain])

    create table(:trajectories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :text, null: false
      add :bin, :text, null: false
      add :evaluator_score, :float
      add :evaluator_evidence, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create constraint(:trajectories, :trajectories_bin_must_be_known,
             check: "bin IN ('positive', 'negative', 'discard')"
           )

    create index(:trajectories, [:domain, :bin])

    create table(:trajectory_sources, primary_key: false) do
      add :trajectory_id, references(:trajectories, type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :experience_run_id,
          references(:experience_runs, type: :binary_id, on_delete: :restrict),
          primary_key: true,
          null: false
    end

    create index(:trajectory_sources, [:experience_run_id])

    create table(:adapters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :text, null: false
      add :base_model, :text, null: false
      add :provider, :text, null: false
      add :version, :text, null: false
      add :training_config, :map, null: false, default: %{}
      add :metrics, :map, null: false, default: %{}
      add :status, :text, null: false, default: "candidate"
      add :artifact_uri, :text
      timestamps(type: :utc_datetime)
    end

    create constraint(:adapters, :adapters_status_must_be_known,
             check: "status IN ('candidate', 'promoted', 'rejected', 'retired')"
           )

    create unique_index(:adapters, [:domain, :version])
    create index(:adapters, [:domain, :status])

    create table(:adapter_lineage, primary_key: false) do
      add :adapter_id, references(:adapters, type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :parent_adapter_id, references(:adapters, type: :binary_id, on_delete: :restrict),
        primary_key: true,
        null: false
    end

    create index(:adapter_lineage, [:parent_adapter_id])

    create table(:adapter_dataset_sources, primary_key: false) do
      add :adapter_id, references(:adapters, type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :trajectory_id, references(:trajectories, type: :binary_id, on_delete: :restrict),
        primary_key: true,
        null: false
    end

    create index(:adapter_dataset_sources, [:trajectory_id])

    create table(:benchmark_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :adapter_id, references(:adapters, type: :binary_id, on_delete: :delete_all), null: false
      add :suite, :text, null: false
      add :metrics, :map, null: false, default: %{}
      add :passed, :boolean, null: false, default: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:benchmark_results, [:adapter_id, :suite])

    create table(:adaptation_domain_thresholds, primary_key: false) do
      add :domain, :text, primary_key: true, null: false
      add :benchmark_suite, :text, primary_key: true, null: false
      add :metric, :text, primary_key: true, null: false, default: "score"
      add :threshold, :float, null: false
      add :comparison, :text, null: false, default: "gte"
    end

    create constraint(:adaptation_domain_thresholds, :adaptation_thresholds_comparison_known,
             check: "comparison IN ('gte', 'gt', 'lte', 'lt')"
           )

    execute("""
    INSERT INTO adaptation_domain_thresholds (domain, benchmark_suite, metric, threshold, comparison)
    VALUES
      ('computer_use', 'desktop_success', 'score', 0.60, 'gte'),
      ('coding', 'swe_bench', 'score', 0.40, 'gte'),
      ('osrs', 'combat', 'score', 0.70, 'gte')
    """)

    create_property_graph()
  end

  def down do
    drop_property_graph()
    drop table(:adaptation_domain_thresholds)
    drop table(:benchmark_results)
    drop table(:adapter_dataset_sources)
    drop table(:adapter_lineage)
    drop table(:adapters)
    drop table(:trajectory_sources)
    drop table(:trajectories)
    drop table(:experience_runs)
  end

  defp create_property_graph do
    execute("""
    DO $graph$
    BEGIN
      IF current_setting('server_version_num')::int >= 190000 THEN
        EXECUTE $ddl$
          CREATE PROPERTY GRAPH maya_adaptation_graph
            VERTEX TABLES (
              experience_runs KEY (id) LABEL experience_run,
              trajectories KEY (id) LABEL trajectory,
              adapters KEY (id) LABEL adapter,
              benchmark_results KEY (id) LABEL benchmark_result
            )
            EDGE TABLES (
              trajectory_sources
                KEY (trajectory_id, experience_run_id)
                SOURCE KEY (trajectory_id) REFERENCES trajectories (id)
                DESTINATION KEY (experience_run_id) REFERENCES experience_runs (id)
                LABEL trajectory_source,
              adapter_lineage
                KEY (adapter_id, parent_adapter_id)
                SOURCE KEY (adapter_id) REFERENCES adapters (id)
                DESTINATION KEY (parent_adapter_id) REFERENCES adapters (id)
                LABEL adapter_lineage,
              adapter_dataset_sources
                KEY (adapter_id, trajectory_id)
                SOURCE KEY (adapter_id) REFERENCES adapters (id)
                DESTINATION KEY (trajectory_id) REFERENCES trajectories (id)
                LABEL adapter_dataset_source,
              benchmark_results AS adapter_benchmarks
                KEY (id)
                SOURCE KEY (adapter_id) REFERENCES adapters (id)
                DESTINATION KEY (id) REFERENCES benchmark_results (id)
                LABEL benchmark_results
            )
        $ddl$;
      END IF;
    END
    $graph$;
    """)
  end

  defp drop_property_graph do
    execute("""
    DO $graph$
    BEGIN
      IF current_setting('server_version_num')::int >= 190000 THEN
        EXECUTE 'DROP PROPERTY GRAPH IF EXISTS maya_adaptation_graph';
      END IF;
    END
    $graph$;
    """)
  end
end
