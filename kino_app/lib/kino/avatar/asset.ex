defmodule Kino.Avatar.Asset do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "avatar_asset" do
    field(:ontology_key, :string)
    field(:kind, :string)
    field(:label, :string)
    field(:description, :string)
    field(:tags, {:array, :string}, default: [])
    field(:default_loop, :boolean, default: false)
    field(:format, :string)
    field(:mime_type, :string)
    field(:sha256, :string)
    field(:byte_size, :integer)
    field(:storage_backend, :string, default: "s3")
    field(:object_key, :string)
    field(:created_by_key, :string)
    timestamps(type: :utc_datetime)
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :ontology_key,
      :kind,
      :label,
      :description,
      :tags,
      :default_loop,
      :format,
      :mime_type,
      :sha256,
      :byte_size,
      :storage_backend,
      :object_key,
      :created_by_key
    ])
    |> validate_required([
      :ontology_key,
      :kind,
      :label,
      :format,
      :mime_type,
      :sha256,
      :byte_size,
      :object_key
    ])
    |> validate_inclusion(:kind, ~w(model animation))
    |> unique_constraint([:kind, :sha256])
    |> unique_constraint(:ontology_key)
  end

  def metadata_changeset(asset, attrs),
    do:
      asset
      |> cast(attrs, [:label, :description, :tags, :default_loop])
      |> validate_required([:label])
end
