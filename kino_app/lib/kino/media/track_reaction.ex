defmodule Kino.Media.TrackReaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "track_reactions" do
    belongs_to(:media_asset, Kino.Media.MediaAsset)
    field(:position, :integer)
    field(:username, :string)
    field(:reaction, :string, default: "heart")

    timestamps(type: :utc_datetime)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:media_asset_id, :position, :username, :reaction])
    |> validate_required([:media_asset_id, :position, :username, :reaction])
    |> unique_constraint([:media_asset_id, :position, :username, :reaction])
  end
end
