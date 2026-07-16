defmodule Kino.Accounts.Invitation do
  use Ecto.Schema
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  schema "kino_invitations" do
    field(:code_hash, :string)
    field(:code_prefix, :string)
    field(:email, :string)
    field(:status, :string, default: "active")
    field(:expires_at, :utc_datetime)
    belongs_to(:issued_by, Kino.Accounts.User)
    belongs_to(:redeemed_by, Kino.Accounts.User)
    timestamps(type: :utc_datetime)
  end
end
