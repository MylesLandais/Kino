defmodule KinoWeb.AgentChannelTest do
  use KinoWeb.ChannelCase, async: false
  use Oban.Testing, repo: Kino.Repo

  alias Kino.Media
  alias Kino.Theater.RoomSession
  alias KinoWeb.AgentSocket

  setup do
    :sys.replace_state(RoomSession, fn _ -> %RoomSession{} end)
    conn = Phoenix.ConnTest.build_conn()

    {conn, user} =
      register_and_log_in_user(conn, %{"username" => "tester", "email" => "tester@example.com"})

    token = conn.private.plug_session["auth_token"]

    {:ok, socket} =
      connect(AgentSocket, %{}, connect_info: %{session: %{"auth_token" => token}})

    {:ok, _reply, socket} = subscribe_and_join(socket, KinoWeb.AgentChannel, "agent:lobby")
    %{socket: socket, user: user}
  end

  test "join pushes the initial system message" do
    assert_push("chat_message", %{msg: %{type: :system, text: text}})
    assert text =~ "/play <url>"
  end

  test "join includes theater snapshot and avatar profile" do
    assert_push("theater_snapshot", %{snapshot: %{username: "tester", playback: playback}})
    assert is_map(playback)
    assert_push("avatar_profile", _profile)
  end

  test "command_hint returns slash help", %{socket: socket} do
    ref = push(socket, "command_hint", %{"text" => "/play"})
    assert_reply ref, :ok, %{hint: hint}
    assert hint =~ "fetch and cache with yt-dlp"
  end

  test "/play routes through shared command handling and enqueues download", %{socket: socket} do
    ref = push(socket, "chat_send", %{"text" => "/play https://www.youtube.com/watch?v=abc"})
    assert_reply ref, :ok, %{status: "ok"}
    assert_enqueued(worker: Kino.Media.DownloadWorker)
  end

  test "/pause and /resume update room desired state", %{socket: socket} do
    {:ok, asset} = Media.request_play("https://www.youtube.com/watch?v=room-state", "tester")
    RoomSession.play(asset, "tester")

    ref = push(socket, "chat_send", %{"text" => "/pause"})
    assert_reply ref, :ok, %{status: "ok"}
    assert RoomSession.current().desired == :paused

    ref = push(socket, "chat_send", %{"text" => "/resume"})
    assert_reply ref, :ok, %{status: "ok"}
    assert RoomSession.current().desired == :playing
  end

  test "toggle_like updates reactions and broadcasts patch", %{socket: socket} do
    url = "https://www.youtube.com/watch?v=setlist-#{System.unique_integer([:positive])}"
    {:ok, asset} = Media.request_play(url, "tester")
    asset = Media.get_asset!(asset.id)

    if is_nil(RoomSession.current().media_id) do
      RoomSession.play(asset, "tester")
    end

    ref = push(socket, "toggle_like", %{"position" => "1"})
    assert_reply ref, :ok, %{status: "ok"}
    assert %{1 => ["tester"]} = Media.reactions_for(asset.id)
    assert_push("theater_patch", %{reactions: %{1 => ["tester"]}})
  end

  test "observed_playback accepts samples and updates room observed state", %{socket: socket} do
    url = "https://www.youtube.com/watch?v=qualified-#{System.unique_integer([:positive])}"
    {:ok, asset} = Media.request_play(url, "tester")
    asset = Media.get_asset!(asset.id)

    if is_nil(RoomSession.current().media_id) do
      RoomSession.play(asset, "tester")
    end

    ref =
      push(socket, "observed_playback", %{
        "state" => "playing",
        "position" => 25,
        "playback_rate" => 1,
        "listener_id" => "listener-a",
        "discontinuity" => false
      })

    assert_reply ref, :ok, %{status: "ok"}
    assert RoomSession.current().position == 25.0
    assert RoomSession.current().observed == :playing
  end

  test "set_channel_mode and negotiate_capabilities", %{socket: socket} do
    ref = push(socket, "set_channel_mode", %{"mode" => "live-audio"})
    assert_reply ref, :ok, %{mode: "live-audio"}
    assert_push("channel_mode_changed", %{mode: "live-audio"})

    ref = push(socket, "negotiate_capabilities", %{"requested" => ["chat-only", "live-video", "unknown"]})
    assert_reply ref, :ok, %{granted: granted, mode: "live-audio"}
    assert "chat-only" in granted
    assert "live-video" in granted
    refute "unknown" in granted
  end

  test "playback_updated is forwarded to clients", %{socket: _socket} do
    Media.broadcast(
      {:playback_updated,
       %RoomSession{
         media_id: 1,
         title: "Stub Video",
         provider: "youtube.com",
         cache_key: "k1",
         requested_by: "you",
         duration_seconds: 212,
         revision: 1,
         desired: :playing,
         observed: :buffering,
         position: 7.0,
         chapters: []
       }}
    )

    assert_push("playback_updated", %{playback: playback})
    assert playback.title == "Stub Video"
    assert playback.desired == "playing"
  end
end
