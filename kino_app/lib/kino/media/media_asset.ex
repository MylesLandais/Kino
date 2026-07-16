defmodule Kino.Media.MediaAsset do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending downloading ready failed)

  schema "media_assets" do
    field(:source_url, :string)
    field(:provider, :string)
    field(:cache_key, :string)
    field(:title, :string)
    field(:duration_seconds, :integer)
    field(:byte_size, :integer)
    field(:file_path, :string)
    field(:status, :string, default: "pending")
    field(:error, :string)
    field(:chapters, {:array, :map})
    field(:description, :string)
    field(:ontology_key, :string)
    field(:storage_backend, :string)
    field(:object_key, :string)
    field(:storage_etag, :string)
    field(:uploaded_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :source_url,
      :provider,
      :cache_key,
      :title,
      :duration_seconds,
      :byte_size,
      :file_path,
      :status,
      :error,
      :chapters,
      :description,
      :ontology_key,
      :storage_backend,
      :object_key,
      :storage_etag,
      :uploaded_at
    ])
    |> validate_required([:source_url, :cache_key, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:cache_key)
  end
end
