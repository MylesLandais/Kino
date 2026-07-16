defmodule Kino.Media.MusicTrack do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "music_track" do
    field(:title, :string)
    field(:base_title, :string)
    field(:remix_name, :string)
    field(:remix_artist, :string)
    field(:version_type, :string)
    field(:duration_seconds, :integer)
    field(:isrc, :string)
    field(:canonical_fingerprint, :string)
    field(:canonical_work_key, :string)
    field(:primary_artist_id, Ecto.UUID)
    field(:graph_node_id, Ecto.UUID)
    field(:attrs, :map, default: %{})
    field(:enriched_at, :utc_datetime)
    timestamps(inserted_at: :created_at, type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :title,
      :base_title,
      :remix_name,
      :remix_artist,
      :version_type,
      :duration_seconds,
      :isrc,
      :canonical_fingerprint,
      :canonical_work_key,
      :primary_artist_id,
      :graph_node_id,
      :attrs,
      :enriched_at
    ])
    |> validate_required([:title, :canonical_fingerprint])
    |> unique_constraint(:canonical_fingerprint, name: :uq_music_track_fingerprint)
  end
end
