defmodule KinoWeb.TheaterLiveTest do
  use KinoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "queues and approves a play command", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#message-form", %{"message" => "/play https://example.com/video"})
    |> render_submit()

    assert render(view) =~ "Resolving video metadata"
    assert render(view) =~ "enqueueing yt-dlp worker"

    send(view.pid, {:pipeline_step, :approval, "oban:test", "https://example.com/video"})
    assert render(view) =~ "Download complete"

    view |> element("#approve-request") |> render_click()
    assert render(view) =~ "Now playing: Queued video"
    assert render(view) =~ "state convergence pending"
  end
end
