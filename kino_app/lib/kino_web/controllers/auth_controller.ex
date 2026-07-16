defmodule KinoWeb.AuthController do
  use KinoWeb, :controller
  alias Kino.Accounts
  alias KinoWeb.UserAuth

  def login_page(conn, _params), do: render_portal(conn, :login)

  def setup_page(conn, _params) do
    if Accounts.bootstrap_required?(),
      do: render_portal(conn, :setup),
      else: redirect(conn, to: ~p"/login")
  end

  def signup_page(conn, %{"code" => code}), do: render_portal(conn, :signup, code: code)

  def signup_page(conn, _),
    do: conn |> put_flash(:error, "An invitation is required") |> redirect(to: ~p"/login")

  def login(conn, %{"account" => %{"identifier" => identifier, "password" => password} = params}) do
    case Accounts.authenticate(identifier, password) do
      {:ok, user} ->
        Accounts.audit("login", user, %{ip: ip(conn)})
        conn |> UserAuth.log_in(user, params["remember"] == "true") |> redirect(to: ~p"/")

      _ ->
        conn
        |> put_flash(:error, "Invalid username/email or password")
        |> redirect(to: ~p"/login")
    end
  end

  def setup(conn, %{"account" => attrs}) do
    case Accounts.bootstrap_admin(attrs, %{ip: ip(conn)}) do
      {:ok, user} -> conn |> UserAuth.log_in(user, true) |> redirect(to: ~p"/")
      {:error, reason} -> conn |> put_flash(:error, friendly(reason)) |> redirect(to: ~p"/setup")
    end
  end

  def signup(conn, %{"account" => attrs, "code" => code}) do
    case Accounts.register_with_invite(attrs, code, %{ip: ip(conn)}) do
      {:ok, user} ->
        conn |> UserAuth.log_in(user, true) |> redirect(to: ~p"/")

      {:error, reason} ->
        conn |> put_flash(:error, friendly(reason)) |> redirect(to: ~p"/signup?code=#{code}")
    end
  end

  def logout(conn, _params), do: conn |> UserAuth.log_out() |> redirect(to: ~p"/login")

  defp render_portal(conn, mode, extra \\ []) do
    render(
      conn,
      :portal,
      Map.to_list(Map.new(extra) |> Map.put(:mode, mode) |> Map.put(:csrf, get_csrf_token()))
    )
  end

  defp ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
  defp friendly(%Ecto.Changeset{}), do: "Please correct the highlighted account details"
  defp friendly(:invalid_invitation), do: "Invitation is invalid or expired"
  defp friendly(:already_bootstrapped), do: "Kino is already configured"
  defp friendly(_), do: "Account could not be created"
end
