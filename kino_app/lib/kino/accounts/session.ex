defmodule Kino.Accounts.Session do
  use Ecto.Schema
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  schema "kino_sessions" do
    field(:token_hash, :string)
    field(:expires_at, :utc_datetime)
    field(:ip, :string)
    field(:user_agent, :string)
    belongs_to(:user, Kino.Accounts.User)
    timestamps(updated_at: false, type: :utc_datetime)
  end
end
