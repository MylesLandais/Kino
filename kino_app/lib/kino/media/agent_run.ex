defmodule Kino.Media.AgentRun do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_runs" do
    field(:oban_job_id, :integer)
    field(:status, :string, default: "pending")
    belongs_to(:media_asset, Kino.Media.MediaAsset)

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:media_asset_id, :oban_job_id, :status])
    |> validate_required([:media_asset_id, :status])
    |> foreign_key_constraint(:media_asset_id)
  end
end
