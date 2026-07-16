defmodule Kino.Repo.Migrations.AddPlayAuditAndObjectStorage do
  use Ecto.Migration

  def up do
    alter table(:media_assets) do
      add :ontology_key, :string
      add :storage_backend, :string
      add :object_key, :text
      add :storage_etag, :string
      add :uploaded_at, :utc_datetime
    end

    execute("""
    CREATE TABLE IF NOT EXISTS music_play_event (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      operator_id uuid,
      entity_type varchar(32) NOT NULL,
      entity_key varchar(255) NOT NULL,
      source varchar(32) NOT NULL DEFAULT 'dashboard',
      played_at timestamptz NOT NULL DEFAULT now(),
      source_url text,
      attrs jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT now()
    )
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS ix_music_play_event_operator_played
    ON music_play_event (operator_id, played_at DESC)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS ix_music_play_event_entity
    ON music_play_event (entity_type, entity_key)
    """)
  end

  def down do
    # The canonical table may be shared with maya-unified and must never be
    # dropped by a Kino rollback.

    alter table(:media_assets) do
      remove :ontology_key
      remove :storage_backend
      remove :object_key
      remove :storage_etag
      remove :uploaded_at
    end
  end
end
