defmodule KinoWeb.TheaterLiveTest do
  use KinoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  use Oban.Testing, repo: Kino.Repo

  alias Kino.Media

  setup %{conn: conn} do
    :sys.replace_state(Kino.Theater.RoomSession, fn _ -> %Kino.Theater.RoomSession{} end)

    {conn, user} =
      register_and_log_in_user(conn, %{"username" => "tester", "email" => "tester@example.com"})

    {:ok, conn: conn, user: user}
  end

  test "unauthenticated theater access redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end

  test "renders the complete idle theater shell", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#kino-theater.kino-shell")
    assert has_element?(view, "#messages[phx-update=stream]")
    assert has_element?(view, "#message-form")
    assert has_element?(view, ".empty-state", "NO SOURCE")
    refute has_element?(view, "#theater-video")
  end

  test "shows a contextual slash-command hint", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#message-form", %{"message" => "/play"})
    |> render_change()

    assert has_element?(view, "#command-hint", "fetch and cache with yt-dlp")
  end

  test "/play enqueues a download job and renders the pending agent message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#message-form", %{"message" => "/play https://www.youtube.com/watch?v=abc"})
    |> render_submit()

    assert_enqueued(worker: Kino.Media.DownloadWorker)
    assert render(view) =~ "Resolving video metadata"
  end

  test "agent events broadcast on the room topic are rendered", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    Media.broadcast_agent(:working, "Resolved: Stub Video — enqueueing yt-dlp download", %{
      cache_key: "k1"
    })

    assert render(view) =~ "enqueueing yt-dlp download"
  end

  test "setlist column renders chapters, seeks, and toggles likes", %{conn: conn} do
    {:ok, asset} = Media.request_play("https://www.youtube.com/watch?v=setlist", "tester")
    {:ok, view, _html} = live(conn, ~p"/")

    # visible by default, first entry is current (position 0), collapsible via topbar
    assert has_element?(view, "#setlist .track.current .eq")
    assert has_element?(view, "#setlist .track-label", "Addict")
    assert has_element?(view, "#setlist .end-cap", "end of set")
    assert has_element?(view, ".theater-body.setlist-overlay")

    view |> element("#setlist-mode-push") |> render_click()
    assert has_element?(view, ".theater-body.setlist-push")
    assert_push_event(view, "setlist_preference", %{mode: "push"})

    # clicking anywhere on a track row, including its time, seeks to the chapter
    view |> element("#setlist-track-2") |> render_click()
    assert_push_event(view, "seek", %{position: "48"})

    # the heart is an isolated action: it toggles the reaction without seeking
    view |> element("#setlist-like-1") |> render_click()
    refute_push_event(view, "seek", %{})
    assert has_element?(view, "#setlist-like-1.liked", "1")
    assert %{1 => ["tester"]} = Media.reactions_for(asset.id)

    view |> element("#setlist-like-1") |> render_click()
    refute has_element?(view, "#setlist-like-1.liked")

    # playback position drives current and played chapter styling
    state = %{Kino.Theater.RoomSession.current() | position: 49.0}
    send(view.pid, {:playback_updated, state})
    assert has_element?(view, "#setlist-track-1.played")
    assert has_element?(view, "#setlist-track-2.current .eq")

    view |> element("#setlist-toggle") |> render_click()
    refute has_element?(view, "#setlist")
  end

  test "qualified playback records one ontology event and renders its count", %{conn: conn} do
    {:ok, asset} = Media.request_play("https://www.youtube.com/watch?v=qualified", "tester")
    {:ok, view, _html} = live(conn, ~p"/")

    sample = fn position ->
      render_hook(view, "observed_playback", %{
        "state" => "playing",
        "position" => position,
        "playback_rate" => 1,
        "listener_id" => "listener-a",
        "discontinuity" => false
      })
    end

    sample.(0)
    sample.(10)
    sample.(20)
    sample.(25)

    assert %{1 => 1} = Media.play_counts_for(Media.get_asset!(asset.id))
    assert has_element?(view, "#setlist-track-1 .track-plays", "▷1")

    sample.(30)
    assert %{1 => 1} = Media.play_counts_for(Media.get_asset!(asset.id))
  end

  test "seek discontinuities do not qualify skipped track time", %{conn: conn} do
    {:ok, asset} = Media.request_play("https://www.youtube.com/watch?v=seek-audit", "tester")
    {:ok, view, _html} = live(conn, ~p"/")

    base = %{
      "state" => "playing",
      "playback_rate" => 1,
      "listener_id" => "listener-b"
    }

    render_hook(
      view,
      "observed_playback",
      Map.merge(base, %{"position" => 0, "discontinuity" => false})
    )

    render_hook(
      view,
      "observed_playback",
      Map.merge(base, %{"position" => 47, "discontinuity" => true})
    )

    assert Media.play_counts_for(Media.get_asset!(asset.id)) == %{}
  end

  test "playback updates swap the idle screen for the video element", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "NO SOURCE"

    Media.broadcast(
      {:playback_updated,
       %Kino.Theater.RoomSession{
         media_id: 1,
         title: "Stub Video",
         provider: "youtube.com",
         cache_key: "k1",
         requested_by: "you",
         duration_seconds: 212,
         revision: 1,
         desired: :playing,
         observed: :buffering,
         position: 7.0
       }}
    )

    html = render(view)
    assert has_element?(view, "#theater-video")
    assert has_element?(view, "#buffering-state", "BUFFERING")
    assert has_element?(view, ".provider", "youtube.com")
    assert has_element?(view, ".playback-meta", "3:32")
    assert has_element?(view, ".playback-meta", "0:07")
    assert html =~ "Stub Video"
    assert html =~ "state convergence pending"
  end
end
