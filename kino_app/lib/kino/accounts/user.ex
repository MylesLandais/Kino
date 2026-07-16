defmodule Kino.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  schema "kino_users" do
    field(:email, :string)
    field(:username, :string)
    field(:display_name, :string)
    field(:password_hash, :string)
    field(:password, :string, virtual: true, redact: true)
    field(:status, :string, default: "active")
    many_to_many(:roles, Kino.Accounts.Role, join_through: "kino_user_roles")
    timestamps(type: :utc_datetime)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :username, :display_name, :password])
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> update_change(:username, &String.downcase(String.trim(&1)))
    |> validate_required([:email, :username, :display_name, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_format(:username, ~r/^[a-z0-9_-]{2,24}$/)
    |> validate_length(:password, min: 5, max: 128)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> put_password_hash()
  end

  def status_changeset(user, attrs),
    do: cast(user, attrs, [:status]) |> validate_inclusion(:status, ~w(active suspended))

  defp put_password_hash(
         %Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset
       ),
       do: put_change(changeset, :password_hash, Kino.Accounts.Password.hash(password))

  defp put_password_hash(changeset), do: changeset
end
