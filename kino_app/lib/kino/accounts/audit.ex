defmodule Kino.Accounts.Audit do
  use Ecto.Schema
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  schema "kino_auth_audit" do
    field(:action, :string)
    field(:detail, :map)
    field(:ip, :string)
    belongs_to(:user, Kino.Accounts.User)
    timestamps(updated_at: false, type: :utc_datetime)
  end
end
