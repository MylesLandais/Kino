defmodule Kino.Media.MusicPlayEvent do
  @moduledoc "Ecto representation of the shared Maya music play-event ontology."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @timestamps_opts [inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec]

  schema "music_play_event" do
    field(:operator_id, Ecto.UUID)
    field(:entity_type, :string)
    field(:entity_key, :string)
    field(:source, :string, default: "dashboard")
    field(:played_at, :utc_datetime_usec)
    field(:source_url, :string)
    field(:attrs, :map, default: %{})

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :operator_id,
      :entity_type,
      :entity_key,
      :source,
      :played_at,
      :source_url,
      :attrs
    ])
    |> validate_required([:id, :entity_type, :entity_key, :source, :played_at])
  end
end
