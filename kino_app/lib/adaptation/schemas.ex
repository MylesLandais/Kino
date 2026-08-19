defmodule Adaptation.Trajectory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @bins ~w(positive negative discard)

  schema "trajectories" do
    field(:domain, :string)
    field(:bin, :string)
    field(:evaluator_score, :float)
    field(:evaluator_evidence, :map, default: %{})

    many_to_many(:experience_runs, Experience.Run,
      join_through: "trajectory_sources",
      join_keys: [trajectory_id: :id, experience_run_id: :id]
    )

    timestamps(type: :utc_datetime)
  end

  def changeset(trajectory, attrs) do
    trajectory
    |> cast(attrs, [:domain, :bin, :evaluator_score, :evaluator_evidence])
    |> validate_required([:domain, :bin])
    |> validate_inclusion(:bin, @bins)
  end
end

defmodule Adaptation.Adapter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses ~w(candidate promoted rejected retired)

  schema "adapters" do
    field(:domain, :string)
    field(:base_model, :string)
    field(:provider, :string)
    field(:version, :string)
    field(:training_config, :map, default: %{})
    field(:metrics, :map, default: %{})
    field(:status, :string, default: "candidate")
    field(:artifact_uri, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(adapter, attrs) do
    adapter
    |> cast(attrs, [
      :domain,
      :base_model,
      :provider,
      :version,
      :training_config,
      :metrics,
      :status,
      :artifact_uri
    ])
    |> validate_required([:domain, :base_model, :provider, :version])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:domain, :version])
  end
end

defmodule Adaptation.BenchmarkResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "benchmark_results" do
    field(:suite, :string)
    field(:metrics, :map, default: %{})
    field(:passed, :boolean, default: false)
    belongs_to(:adapter, Adaptation.Adapter)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [:adapter_id, :suite, :metrics, :passed])
    |> validate_required([:adapter_id, :suite, :passed])
    |> foreign_key_constraint(:adapter_id)
  end
end

defmodule Adaptation.DomainThreshold do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "adaptation_domain_thresholds" do
    field(:domain, :string, primary_key: true)
    field(:benchmark_suite, :string, primary_key: true)
    field(:metric, :string, primary_key: true, default: "score")
    field(:threshold, :float)
    field(:comparison, :string, default: "gte")
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:domain, :benchmark_suite, :metric, :threshold, :comparison])
    |> validate_required([:domain, :benchmark_suite, :metric, :threshold, :comparison])
    |> validate_inclusion(:comparison, ~w(gte gt lte lt))
  end
end
