defmodule Kino.Accounts.Permission do
  use Ecto.Schema
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "kino_permissions" do
    field(:name, :string)
    field(:resource, :string)
    field(:action, :string)
    timestamps(type: :utc_datetime)
  end
end
