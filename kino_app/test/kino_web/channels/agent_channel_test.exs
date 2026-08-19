defmodule KinoWeb.AgentChannelTest do
  use KinoWeb.ChannelCase, async: false
  use Oban.Testing, repo: Kino.Repo

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
    {:ok, asset} = Kino.Media.request_play("https://www.youtube.com/watch?v=room-state", "tester")
    RoomSession.play(asset, "tester")

    ref = push(socket, "chat_send", %{"text" => "/pause"})
    assert_reply ref, :ok, %{status: "ok"}
    assert RoomSession.current().desired == :paused

    ref = push(socket, "chat_send", %{"text" => "/resume"})
    assert_reply ref, :ok, %{status: "ok"}
    assert RoomSession.current().desired == :playing
  end
end
