defmodule Kino.Repo.Migrations.CreateAgentRuns do
  use Ecto.Migration

  def change do
    create table(:agent_runs) do
      add :media_asset_id, references(:media_assets, on_delete: :delete_all), null: false
      add :oban_job_id, :bigint
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:agent_runs, [:media_asset_id])
  end
end
