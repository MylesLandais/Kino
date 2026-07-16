defmodule Kino.Accounts.Role do
  use Ecto.Schema
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "kino_roles" do
    field(:name, :string)
    field(:description, :string)
    many_to_many(:permissions, Kino.Accounts.Permission, join_through: "kino_role_permissions")
    timestamps(type: :utc_datetime)
  end
end
