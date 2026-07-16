defmodule Kino.Repo.Migrations.CreateKinoAuth do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", "SELECT 1"
    create table(:kino_users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :citext, null: false
      add :username, :citext, null: false
      add :display_name, :string, null: false
      add :password_hash, :string, null: false
      add :status, :string, null: false, default: "active"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kino_users, [:email])
    create unique_index(:kino_users, [:username])

    create table(:kino_roles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :description, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kino_roles, [:name])

    create table(:kino_permissions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :resource, :string, null: false
      add :action, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kino_permissions, [:name])

    create table(:kino_user_roles, primary_key: false) do
      add :user_id, references(:kino_users, type: :uuid, on_delete: :delete_all), primary_key: true
      add :role_id, references(:kino_roles, type: :uuid, on_delete: :delete_all), primary_key: true
    end

    create table(:kino_role_permissions, primary_key: false) do
      add :role_id, references(:kino_roles, type: :uuid, on_delete: :delete_all), primary_key: true
      add :permission_id, references(:kino_permissions, type: :uuid, on_delete: :delete_all), primary_key: true
    end

    create table(:kino_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:kino_users, type: :uuid, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :ip, :string
      add :user_agent, :text
      timestamps(updated_at: false, type: :utc_datetime)
    end

    create unique_index(:kino_sessions, [:token_hash])
    create index(:kino_sessions, [:user_id, :expires_at])

    create table(:kino_invitations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :code_hash, :string, null: false
      add :code_prefix, :string, null: false
      add :email, :citext
      add :status, :string, null: false, default: "active"
      add :expires_at, :utc_datetime, null: false
      add :issued_by_id, references(:kino_users, type: :uuid, on_delete: :nilify_all)
      add :redeemed_by_id, references(:kino_users, type: :uuid, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kino_invitations, [:code_hash])

    create table(:kino_auth_audit, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:kino_users, type: :uuid, on_delete: :nilify_all)
      add :action, :string, null: false
      add :detail, :map
      add :ip, :string
      timestamps(updated_at: false, type: :utc_datetime)
    end

    create index(:kino_auth_audit, [:user_id, :inserted_at])
  end
end
