defmodule KinoWeb.TheaterLiveTest do
  use KinoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    :sys.replace_state(Kino.Theater.RoomSession, fn _ -> %Kino.Theater.RoomSession{} end)

    {conn, _user} =
      register_and_log_in_user(conn, %{"username" => "tester", "email" => "tester@example.com"})

    {:ok, conn: conn}
  end

  test "unauthenticated theater access redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end

  test "renders the Tint theater mount point", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#tint-theater.tint-theater-root[phx-hook=TintTheater]")
    refute has_element?(view, "#kino-theater.kino-shell")
    refute has_element?(view, "#tint-agent-chat")
  end
end
