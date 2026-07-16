defmodule Kino.Repo.Migrations.AddMusicOntologyAndResolutionState do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS ontology_node (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), domain text NOT NULL,
      domain_id text NOT NULL, node_type text NOT NULL, label text NOT NULL,
      slug text, description text, attrs jsonb NOT NULL DEFAULT '{}',
      created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE(domain, domain_id, node_type)
    )
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS ontology_edge (
      source_id uuid NOT NULL, target_id uuid NOT NULL, edge_type text NOT NULL,
      dimension text NOT NULL DEFAULT 'semantic', weight float NOT NULL DEFAULT 1.0,
      confidence float NOT NULL DEFAULT 1.0, evidence jsonb NOT NULL DEFAULT '{}',
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY(source_id, target_id, edge_type, dimension)
    )
    """)

    execute("CREATE INDEX IF NOT EXISTS ix_oe_source ON ontology_edge(source_id, dimension, weight DESC)")
    execute("CREATE INDEX IF NOT EXISTS ix_oe_target ON ontology_edge(target_id, dimension, weight DESC)")

    execute("""
    CREATE INDEX IF NOT EXISTS ix_on_music_canonical_work
    ON ontology_node(domain, node_type, label)
    WHERE domain='music' AND node_type IN ('canonical_work','recording')
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS music_genre (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL, slug varchar(255) NOT NULL,
      parent_id uuid REFERENCES music_genre(id) ON DELETE SET NULL, beatport_id integer,
      source varchar(32) NOT NULL DEFAULT 'beatport', attrs jsonb NOT NULL DEFAULT '{}',
      created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT uq_music_genre_slug UNIQUE(slug), CONSTRAINT uq_music_genre_beatport_id UNIQUE(beatport_id)
    )
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS music_artist (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL, sort_name text,
      artist_type varchar(32) NOT NULL DEFAULT 'artist', country_code varchar(8),
      is_group boolean NOT NULL DEFAULT false, aliases jsonb NOT NULL DEFAULT '[]',
      attrs jsonb NOT NULL DEFAULT '{}', graph_node_id uuid,
      created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
    )
    """)

    execute("CREATE INDEX IF NOT EXISTS ix_music_artist_name_lower ON music_artist(lower(name))")

    execute("""
    CREATE TABLE IF NOT EXISTS music_track (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text NOT NULL, base_title text,
      remix_name text, remix_artist text, version_type varchar(32), duration_seconds integer,
      isrc varchar(32), canonical_fingerprint varchar(255) NOT NULL, cluster_key varchar(64),
      bpm double precision, key_camelot varchar(8),
      primary_artist_id uuid REFERENCES music_artist(id) ON DELETE SET NULL,
      genre_id uuid REFERENCES music_genre(id) ON DELETE SET NULL,
      sub_genre_id uuid REFERENCES music_genre(id) ON DELETE SET NULL,
      canonical_work_key varchar(255), graph_node_id uuid, attrs jsonb NOT NULL DEFAULT '{}',
      enriched_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT uq_music_track_fingerprint UNIQUE(canonical_fingerprint)
    )
    """)

    execute("CREATE INDEX IF NOT EXISTS ix_music_track_work_key ON music_track(canonical_work_key)")

    execute("""
    CREATE TABLE IF NOT EXISTS music_track_artist (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      track_id uuid NOT NULL REFERENCES music_track(id) ON DELETE CASCADE,
      artist_id uuid NOT NULL REFERENCES music_artist(id) ON DELETE CASCADE,
      role varchar(32) NOT NULL DEFAULT 'primary', billing_order integer NOT NULL DEFAULT 0,
      CONSTRAINT uq_music_track_artist UNIQUE(track_id, artist_id, role, billing_order)
    )
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS music_release (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text NOT NULL, release_type varchar(32),
      label text, catalog_number varchar(64), release_date date,
      primary_artist_id uuid REFERENCES music_artist(id) ON DELETE SET NULL,
      attrs jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    )
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS music_release_track (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      release_id uuid NOT NULL REFERENCES music_release(id) ON DELETE CASCADE,
      track_id uuid NOT NULL REFERENCES music_track(id) ON DELETE CASCADE,
      disc_number integer, track_number integer,
      CONSTRAINT uq_music_release_track UNIQUE(release_id, track_id)
    )
    """)

    execute("ALTER TABLE music_platform_link ALTER COLUMN external_id DROP NOT NULL")

    create table(:set_entry_resolutions) do
      add :media_asset_id, references(:media_assets, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :set_key, :string, null: false
      add :entry_key, :string, null: false
      add :raw_label, :text, null: false
      add :artist, :text
      add :title, :text
      add :base_title, :text
      add :remix_name, :text
      add :version_type, :string
      add :label_name, :text
      add :status, :string, null: false, default: "pending"
      add :track_id, :uuid
      add :work_key, :string
      add :confidence, :float
      add :provider_status, :map, null: false, default: %{}
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:set_entry_resolutions, [:media_asset_id, :position])
    create unique_index(:set_entry_resolutions, [:entry_key])
    create index(:set_entry_resolutions, [:track_id])

    create table(:music_platform_lookup, primary_key: false) do
      add :track_id, :uuid, null: false, primary_key: true
      add :platform, :string, null: false, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :candidate_count, :integer, null: false, default: 0
      add :last_attempt_at, :utc_datetime
      add :retry_after, :utc_datetime
      add :error, :text
      add :attrs, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end
  end

  def down do
    drop_if_exists table(:music_platform_lookup)
    drop_if_exists table(:set_entry_resolutions)
    # Shared Maya ontology/relational tables intentionally survive rollback.
  end
end
