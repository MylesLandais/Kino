defmodule Kino.Repo.Migrations.AddChaptersToMediaAssets do
  use Ecto.Migration

  def change do
    alter table(:media_assets) do
      add :chapters, :jsonb
      add :description, :text
    end
  end
end
