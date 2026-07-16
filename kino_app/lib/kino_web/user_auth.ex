defmodule KinoWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller
  alias Kino.Accounts

  @cookie "_kino_session_token"

  def init(action), do: action
  def call(conn, :fetch_current_user), do: fetch_current_user(conn, [])
  def call(conn, :require_authenticated), do: require_authenticated(conn, [])

  def fetch_current_user(conn, _opts) do
    conn = fetch_cookies(conn, signed: [@cookie])
    token = get_session(conn, :auth_token) || conn.cookies[@cookie] || conn.req_cookies[@cookie]
    assign(conn, :current_user, Accounts.user_for_session(token))
  end

  def require_authenticated(conn, _opts) do
    if conn.assigns.current_user,
      do: conn,
      else: conn |> put_flash(:error, "Sign in to enter Kino") |> redirect(to: "/login") |> halt()
  end

  def require_permission(conn, permission) do
    if Accounts.allowed?(conn.assigns.current_user, permission),
      do: conn,
      else: conn |> send_resp(403, "forbidden") |> halt()
  end

  def log_in(conn, user, remember?) do
    {token, ttl} =
      Accounts.create_session(user,
        remember: remember?,
        ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
        user_agent: get_req_header(conn, "user-agent") |> List.first()
      )

    conn
    |> put_session(:auth_token, token)
    |> put_resp_cookie(@cookie, token,
      http_only: true,
      secure: conn.scheme == :https,
      same_site: "Lax",
      max_age: ttl,
      sign: true
    )
  end

  def log_out(conn) do
    conn = fetch_cookies(conn, signed: [@cookie])
    Accounts.revoke_session(conn.cookies[@cookie])
    conn |> delete_session(:auth_token) |> delete_resp_cookie(@cookie)
  end

  def on_mount(:authenticated, _params, session, socket) do
    user = Accounts.user_for_session(session["auth_token"])

    if user,
      do: {:cont, Phoenix.Component.assign(socket, current_scope: %{user: user})},
      else: {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
  end

  def cookie_name, do: @cookie
end
