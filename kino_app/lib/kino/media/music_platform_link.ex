defmodule Kino.Media.MusicPlatformLink do
  @moduledoc "Ecto representation of Maya's shared cross-platform music identity spine."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "music_platform_link" do
    field(:entity_type, :string)
    field(:entity_id, Ecto.UUID)
    field(:platform, :string)
    field(:external_id, :string)
    field(:url, :string)
    field(:confidence, :float, default: 1.0)
    field(:source, :string, default: "resolver")
    field(:resolved_by, :string, default: "metadata_similarity")
    field(:attrs, :map, default: %{})

    timestamps(inserted_at: :created_at, type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [
      :entity_type,
      :entity_id,
      :platform,
      :external_id,
      :url,
      :confidence,
      :source,
      :resolved_by,
      :attrs
    ])
    |> validate_required([:entity_type, :entity_id, :platform, :external_id, :url, :confidence])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint([:platform, :external_id], name: :uq_music_platform_ext)
  end
end
