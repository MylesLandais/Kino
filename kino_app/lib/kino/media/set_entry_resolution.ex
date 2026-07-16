defmodule Kino.Media.SetEntryResolution do
  use Ecto.Schema
  import Ecto.Changeset

  schema "set_entry_resolutions" do
    field(:position, :integer)
    field(:set_key, :string)
    field(:entry_key, :string)
    field(:raw_label, :string)
    field(:artist, :string)
    field(:title, :string)
    field(:base_title, :string)
    field(:remix_name, :string)
    field(:version_type, :string)
    field(:label_name, :string)
    field(:status, :string, default: "pending")
    field(:track_id, Ecto.UUID)
    field(:work_key, :string)
    field(:confidence, :float)
    field(:provider_status, :map, default: %{})
    field(:error, :string)
    belongs_to(:media_asset, Kino.Media.MediaAsset)
    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :media_asset_id,
      :position,
      :set_key,
      :entry_key,
      :raw_label,
      :artist,
      :title,
      :base_title,
      :remix_name,
      :version_type,
      :label_name,
      :status,
      :track_id,
      :work_key,
      :confidence,
      :provider_status,
      :error
    ])
    |> validate_required([:media_asset_id, :position, :set_key, :entry_key, :raw_label, :status])
    |> unique_constraint([:media_asset_id, :position])
    |> unique_constraint(:entry_key)
  end
end
