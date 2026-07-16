defmodule Kino.Repo.Migrations.CreateMusicPlatformLinks do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS music_platform_link (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      entity_type varchar(32) NOT NULL,
      entity_id uuid NOT NULL,
      platform varchar(32) NOT NULL,
      external_id varchar(255) NOT NULL,
      url text NOT NULL,
      confidence double precision NOT NULL DEFAULT 1.0,
      source varchar(64) NOT NULL DEFAULT 'manual',
      resolved_by varchar(32) NOT NULL DEFAULT 'manual',
      attrs jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    )
    """)

    execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_music_platform_ext ON music_platform_link(platform, external_id)")

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS uq_music_platform_entity
    ON music_platform_link(entity_type, entity_id, platform, external_id)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS ix_music_platform_link_entity
    ON music_platform_link(entity_type, entity_id)
    """)
  end

  def down do
    # This ontology table is shared with Maya and must survive Kino rollbacks.
    :ok
  end
end
