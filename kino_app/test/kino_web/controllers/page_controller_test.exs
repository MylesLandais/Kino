defmodule KinoWeb.PageControllerTest do
  use KinoWeb.ConnCase

  test "GET / without a session redirects to login", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/login"
  end

  test "GET / with an authenticated account shows the theater", %{conn: conn} do
    {conn, _user} = register_and_log_in_user(conn)
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "kino session started"
  end
end
