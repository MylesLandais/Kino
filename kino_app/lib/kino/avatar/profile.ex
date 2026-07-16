defmodule Kino.Avatar.Profile do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  schema "avatar_profile" do
    field(:profile_key, :string)
    field(:enabled, :boolean, default: true)
    field(:camera_distance, :float, default: 1.8)
    field(:look_at_camera, :boolean, default: true)
    field(:lip_sync_mode, :string, default: "viseme")
    field(:mouth_gain, :float, default: 6.0)
    field(:mouth_smoothing, :float, default: 0.5)
    belongs_to(:model_asset, Kino.Avatar.Asset)
    belongs_to(:idle_asset, Kino.Avatar.Asset)

    many_to_many(:idle_variants, Kino.Avatar.Asset,
      join_through: "avatar_profile_idle_variant",
      join_keys: [profile_id: :id, asset_id: :id]
    )

    timestamps(type: :utc_datetime)
  end

  def changeset(profile, attrs),
    do:
      profile
      |> cast(attrs, [
        :profile_key,
        :enabled,
        :camera_distance,
        :look_at_camera,
        :lip_sync_mode,
        :mouth_gain,
        :mouth_smoothing,
        :model_asset_id,
        :idle_asset_id
      ])
      |> validate_required([:profile_key])
      |> validate_inclusion(:lip_sync_mode, ~w(viseme amplitude))
      |> validate_number(:camera_distance,
        greater_than_or_equal_to: 0.8,
        less_than_or_equal_to: 4.5
      )
end
