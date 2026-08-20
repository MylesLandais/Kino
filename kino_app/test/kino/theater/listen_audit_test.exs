defmodule Kino.Theater.ListenAuditTest do
  use Kino.DataCase, async: false

  alias Kino.Media
  alias Kino.Theater.{ListenAudit, RoomSession}

  setup do
    :sys.replace_state(RoomSession, fn _ -> %RoomSession{} end)
    :ok
  end

  test "accumulates progress and records qualified plays" do
    url = "https://www.youtube.com/watch?v=listen-audit-#{System.unique_integer([:positive])}"
    {:ok, asset} = Media.request_play(url, "tester")
    asset = Media.get_asset!(asset.id)
    RoomSession.play(asset, "tester")
    playback = Map.from_struct(RoomSession.current())

    sample = fn audit, position ->
      ListenAudit.advance(
        audit,
        playback,
        %{
          "state" => "playing",
          "position" => position,
          "playback_rate" => 1,
          "listener_id" => "listener-a",
          "discontinuity" => false
        },
        "tester"
      )
    end

    audit =
      ListenAudit.new("listener-a", playback.playback_session_id, 0, "playing")
      |> then(&sample.(&1, 0))
      |> then(&sample.(&1, 10))
      |> then(&sample.(&1, 20))
      |> then(&sample.(&1, 25))

    assert %{1 => 25.0} = audit.accrued
    assert %{1 => 1} = Media.play_counts_for(asset)
  end

  test "seek discontinuities do not qualify skipped track time" do
    url = "https://www.youtube.com/watch?v=listen-skip-#{System.unique_integer([:positive])}"
    {:ok, asset} = Media.request_play(url, "tester")
    asset = Media.get_asset!(asset.id)
    RoomSession.play(asset, "tester")
    playback = Map.from_struct(RoomSession.current())

    base = %{
      "state" => "playing",
      "playback_rate" => 1,
      "listener_id" => "listener-b"
    }

    audit = ListenAudit.new("listener-b", playback.playback_session_id, 0, "playing")

    audit =
      ListenAudit.advance(
        audit,
        playback,
        Map.merge(base, %{"position" => 0, "discontinuity" => false}),
        "tester"
      )

    audit =
      ListenAudit.advance(
        audit,
        playback,
        Map.merge(base, %{"position" => 47, "discontinuity" => true}),
        "tester"
      )

    assert audit.accrued == %{}
    assert Media.play_counts_for(asset) == %{}
  end
end
