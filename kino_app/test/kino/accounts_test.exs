defmodule Kino.AccountsTest do
  use Kino.DataCase, async: false

  alias Kino.Accounts

  setup do
    Accounts.ensure_rbac!()

    {:ok, admin} =
      Accounts.bootstrap_admin(%{
        "email" => "admin@kino.test",
        "username" => "admin",
        "display_name" => "Admin",
        "password" => "correct horse battery staple"
      })

    %{admin: admin}
  end

  test "admin and invited operator receive their intended permissions", %{admin: admin} do
    assert Accounts.allowed?(admin, "users:manage")
    assert Accounts.allowed?(admin, "avatar:manage")

    {code, _invite} = Accounts.create_invitation(admin, "operator@kino.test")

    {:ok, operator} =
      Accounts.register_with_invite(
        %{
          "email" => "operator@kino.test",
          "username" => "operator",
          "display_name" => "Operator",
          "password" => "correct horse battery staple"
        },
        code
      )

    assert Accounts.allowed?(operator, "theater:access")
    assert Accounts.allowed?(operator, "avatar:trigger")
    refute Accounts.allowed?(operator, "avatar:manage")
    refute Accounts.allowed?(operator, "users:manage")
  end

  test "an invitation is single-use and email-bound", %{admin: admin} do
    {code, _invite} = Accounts.create_invitation(admin, "first@kino.test")

    assert {:error, :invalid_invitation} =
             Accounts.register_with_invite(
               %{
                 "email" => "other@kino.test",
                 "username" => "other",
                 "display_name" => "Other",
                 "password" => "correct horse battery staple"
               },
               code
             )

    assert {:ok, _user} =
             Accounts.register_with_invite(
               %{
                 "email" => "first@kino.test",
                 "username" => "first",
                 "display_name" => "First",
                 "password" => "correct horse battery staple"
               },
               code
             )

    assert {:error, :invalid_invitation} =
             Accounts.register_with_invite(
               %{
                 "email" => "first@kino.test",
                 "username" => "second",
                 "display_name" => "Second",
                 "password" => "correct horse battery staple"
               },
               code
             )
  end

  test "sessions are opaque, resolvable, and revocable", %{admin: admin} do
    {token, _ttl} = Accounts.create_session(admin)

    assert token != admin.id
    assert Accounts.user_for_session(token).id == admin.id
    assert :ok = Accounts.revoke_session(token)
    assert Accounts.user_for_session(token) == nil
  end
end
