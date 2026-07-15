defmodule KinoWeb.PageControllerTest do
  use KinoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "kino session started"
  end
end
