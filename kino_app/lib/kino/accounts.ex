defmodule Kino.Accounts do
  @moduledoc "Kino-owned accounts, server-side sessions, invitations, and permission RBAC."
  import Ecto.Query
  alias Kino.Accounts.{Audit, Invitation, Permission, Role, Session, User}
  alias Kino.Repo

  @permissions [
    {"theater:access", "theater", "access"},
    {"chat:send", "chat", "send"},
    {"avatar:trigger", "avatar", "trigger"},
    {"avatar:manage", "avatar", "manage"},
    {"users:manage", "users", "manage"}
  ]
  @role_permissions %{
    "operator" => ~w(theater:access chat:send avatar:trigger),
    "admin" => Enum.map(@permissions, &elem(&1, 0))
  }

  def bootstrap_required?, do: Repo.aggregate(User, :count) == 0
  def list_users, do: Repo.all(from(u in User, preload: [:roles], order_by: u.username))
  def get_user!(id), do: Repo.get!(User, id) |> Repo.preload(:roles)

  def ensure_rbac! do
    Repo.transaction(fn ->
      permissions =
        Map.new(@permissions, fn {name, resource, action} ->
          permission =
            Repo.get_by(Permission, name: name) ||
              Repo.insert!(%Permission{name: name, resource: resource, action: action})

          {name, permission}
        end)

      Enum.each(@role_permissions, fn {name, names} ->
        role =
          Repo.get_by(Role, name: name) ||
            Repo.insert!(%Role{name: name, description: "Kino #{name}"})

        wanted = Enum.map(names, &permissions[&1])

        role
        |> Repo.preload(:permissions)
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:permissions, wanted)
        |> Repo.update!()
      end)
    end)
  end

  def bootstrap_admin(attrs, metadata \\ %{}) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [1_715_400])
      if Repo.aggregate(User, :count) > 0, do: Repo.rollback(:already_bootstrapped)
      ensure_rbac!()
      user = insert_user!(attrs, "admin")
      audit("bootstrap_admin", user, metadata)
      user
    end)
  end

  def register_with_invite(attrs, code, metadata \\ %{}) do
    Repo.transaction(fn ->
      invitation =
        valid_invitation(code, attrs["email"] || attrs[:email]) ||
          Repo.rollback(:invalid_invitation)

      user = insert_user!(attrs, "operator")

      invitation
      |> Ecto.Changeset.change(status: "redeemed", redeemed_by_id: user.id)
      |> Repo.update!()

      audit("signup", user, Map.put(metadata, :invite, invitation.code_prefix))
      user
    end)
  end

  def authenticate(identifier, password) do
    normalized = identifier |> String.trim() |> String.downcase()

    user =
      Repo.one(
        from(u in User,
          where: u.email == ^normalized or u.username == ^normalized,
          preload: [:roles]
        )
      )

    if user && user.status == "active" &&
         Kino.Accounts.Password.verify(password, user.password_hash),
       do: {:ok, user},
       else: {:error, :invalid_credentials}
  end

  def create_session(%User{} = user, opts \\ []) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    ttl = if Keyword.get(opts, :remember, false), do: 60 * 86_400, else: 7 * 86_400
    expires_at = DateTime.add(DateTime.utc_now(:second), ttl, :second)

    Repo.insert!(%Session{
      user_id: user.id,
      token_hash: token_hash(token),
      expires_at: expires_at,
      ip: opts[:ip],
      user_agent: opts[:user_agent]
    })

    {token, ttl}
  end

  def user_for_session(nil), do: nil

  def user_for_session(token) do
    hash = token_hash(token)
    now = DateTime.utc_now(:second)

    from(s in Session,
      join: u in assoc(s, :user),
      where: s.token_hash == ^hash and s.expires_at > ^now and u.status == "active",
      select: u
    )
    |> Repo.one()
    |> case do
      nil -> nil
      user -> Repo.preload(user, :roles)
    end
  end

  def revoke_session(nil), do: :ok

  def revoke_session(token) do
    Repo.delete_all(from(s in Session, where: s.token_hash == ^token_hash(token)))
    :ok
  end

  def permissions_for(%User{} = user) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT DISTINCT p.name FROM kino_permissions p
        JOIN kino_role_permissions rp ON rp.permission_id = p.id
        JOIN kino_user_roles ur ON ur.role_id = rp.role_id
        WHERE ur.user_id = $1
        """,
        [Ecto.UUID.dump!(user.id)]
      )

    rows |> Enum.map(&hd/1) |> MapSet.new()
  end

  def allowed?(nil, _), do: false
  def allowed?(user, permission), do: MapSet.member?(permissions_for(user), permission)

  def create_invitation(%User{} = issuer, email \\ nil) do
    code = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)

    invitation =
      Repo.insert!(%Invitation{
        code_hash: token_hash(code),
        code_prefix: String.slice(code, 0, 8),
        email: normalize_optional(email),
        expires_at: DateTime.add(DateTime.utc_now(:second), 14, :day),
        issued_by_id: issuer.id
      })

    audit("invite_created", issuer, %{prefix: invitation.code_prefix, email: invitation.email})
    {code, invitation}
  end

  def suspend_user(admin, id, status) when status in ~w(active suspended) do
    user = get_user!(id)

    if admin.id == user.id && status == "suspended",
      do: {:error, :self_suspension},
      else: user |> User.status_changeset(%{status: status}) |> Repo.update()
  end

  def audit(action, user, detail \\ %{}) do
    Repo.insert!(%Audit{user_id: user && user.id, action: action, detail: Map.new(detail)})
    :ok
  end

  defp insert_user!(attrs, role_name) do
    role = Repo.get_by!(Role, name: role_name)

    %User{}
    |> User.registration_changeset(attrs)
    |> Ecto.Changeset.put_assoc(:roles, [role])
    |> Repo.insert!()
    |> Repo.preload(:roles)
  end

  defp valid_invitation(code, email) do
    now = DateTime.utc_now(:second)
    normalized = normalize_optional(email)

    Repo.one(
      from(i in Invitation,
        where:
          i.code_hash == ^token_hash(code || "") and i.status == "active" and i.expires_at > ^now and
            (is_nil(i.email) or i.email == ^normalized),
        lock: "FOR UPDATE"
      )
    )
  end

  defp normalize_optional(nil), do: nil
  defp normalize_optional(value), do: value |> String.trim() |> String.downcase()
  defp token_hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end
