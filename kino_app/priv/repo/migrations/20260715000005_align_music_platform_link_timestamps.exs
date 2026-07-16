defmodule Kino.Repo.Migrations.AlignMusicPlatformLinkTimestamps do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'music_platform_link' AND column_name = 'inserted_at'
      ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'music_platform_link' AND column_name = 'created_at'
      ) THEN
        ALTER TABLE music_platform_link RENAME COLUMN inserted_at TO created_at;
      END IF;
    END
    $$
    """)

    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'music_platform_link' AND column_name = 'created_at'
          AND data_type = 'timestamp without time zone'
      ) THEN
        ALTER TABLE music_platform_link
          ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'music_platform_link' AND column_name = 'updated_at'
          AND data_type = 'timestamp without time zone'
      ) THEN
        ALTER TABLE music_platform_link
          ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
      END IF;
    END
    $$
    """)
  end

  def down, do: :ok
end
