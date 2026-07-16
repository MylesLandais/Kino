defmodule Kino.Media.MusicPlatformLookup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "music_platform_lookup" do
    field(:track_id, Ecto.UUID, primary_key: true)
    field(:platform, :string, primary_key: true)
    field(:status, :string, default: "pending")
    field(:candidate_count, :integer, default: 0)
    field(:last_attempt_at, :utc_datetime)
    field(:retry_after, :utc_datetime)
    field(:error, :string)
    field(:attrs, :map, default: %{})
    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :track_id,
      :platform,
      :status,
      :candidate_count,
      :last_attempt_at,
      :retry_after,
      :error,
      :attrs
    ])
    |> validate_required([:track_id, :platform, :status])
  end
end
