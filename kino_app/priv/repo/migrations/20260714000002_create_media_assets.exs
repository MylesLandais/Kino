defmodule Kino.Repo.Migrations.CreateMediaAssets do
  use Ecto.Migration

  def change do
    create table(:media_assets) do
      add :source_url, :text, null: false
      add :provider, :string
      add :cache_key, :string, null: false
      add :title, :string
      add :duration_seconds, :integer
      add :byte_size, :bigint
      add :file_path, :text
      add :status, :string, null: false, default: "pending"
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:media_assets, [:cache_key])
  end
end
