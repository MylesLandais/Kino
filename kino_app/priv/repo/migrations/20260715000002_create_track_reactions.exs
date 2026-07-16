defmodule Kino.Repo.Migrations.CreateTrackReactions do
  use Ecto.Migration

  def change do
    create table(:track_reactions) do
      add :media_asset_id, references(:media_assets, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :username, :string, null: false
      add :reaction, :string, null: false, default: "heart"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:track_reactions, [:media_asset_id, :position, :username, :reaction])
  end
end
