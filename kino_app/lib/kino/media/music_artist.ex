defmodule Kino.Media.MusicArtist do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "music_artist" do
    field(:name, :string)
    field(:sort_name, :string)
    field(:attrs, :map, default: %{})
    field(:graph_node_id, Ecto.UUID)
    timestamps(inserted_at: :created_at, type: :utc_datetime)
  end

  def changeset(row, attrs),
    do:
      row
      |> cast(attrs, [:name, :sort_name, :attrs, :graph_node_id])
      |> validate_required([:name])
end
