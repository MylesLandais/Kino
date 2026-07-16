defmodule Kino.Repo.Migrations.CreateAvatarOntology do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS avatar_asset (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), ontology_key varchar(255) NOT NULL UNIQUE,
      kind varchar(16) NOT NULL, label varchar(255) NOT NULL, description text,
      tags text[] NOT NULL DEFAULT '{}', default_loop boolean NOT NULL DEFAULT false,
      format varchar(16) NOT NULL, mime_type varchar(255) NOT NULL,
      sha256 varchar(64) NOT NULL, byte_size bigint NOT NULL,
      storage_backend varchar(32) NOT NULL DEFAULT 's3', object_key text NOT NULL,
      created_by_key varchar(255), inserted_at timestamp(0) NOT NULL DEFAULT now(),
      updated_at timestamp(0) NOT NULL DEFAULT now(),
      CONSTRAINT avatar_asset_kind CHECK (kind IN ('model','animation')),
      CONSTRAINT avatar_asset_content_unique UNIQUE(kind, sha256)
    )
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS avatar_profile (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), profile_key varchar(64) NOT NULL UNIQUE,
      model_asset_id uuid REFERENCES avatar_asset(id) ON DELETE SET NULL,
      idle_asset_id uuid REFERENCES avatar_asset(id) ON DELETE SET NULL,
      enabled boolean NOT NULL DEFAULT true, camera_distance double precision NOT NULL DEFAULT 1.8,
      look_at_camera boolean NOT NULL DEFAULT true, lip_sync_mode varchar(16) NOT NULL DEFAULT 'viseme',
      mouth_gain double precision NOT NULL DEFAULT 6.0, mouth_smoothing double precision NOT NULL DEFAULT 0.5,
      inserted_at timestamp(0) NOT NULL DEFAULT now(), updated_at timestamp(0) NOT NULL DEFAULT now()
    )
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS avatar_profile_idle_variant (
      profile_id uuid REFERENCES avatar_profile(id) ON DELETE CASCADE,
      asset_id uuid REFERENCES avatar_asset(id) ON DELETE CASCADE,
      position integer NOT NULL, PRIMARY KEY(profile_id, asset_id), UNIQUE(profile_id, position)
    )
    """)
  end

  def down, do: :ok
end
