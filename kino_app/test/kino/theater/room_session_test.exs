defmodule Kino.Theater.RoomSessionTest do
  use ExUnit.Case, async: true

  alias Kino.Theater.RoomSession

  test "transport intent changes desired state without revising repeated commands" do
    name = Module.concat(__MODULE__, "Session#{System.unique_integer([:positive])}")
    pid = start_supervised!({RoomSession, name: name})

    asset = %{
      id: 42,
      title: "Test Video",
      provider: "example.test",
      cache_key: "test-key",
      duration_seconds: 60
    }

    RoomSession.play(asset, "tester", name)
    _ = :sys.get_state(pid)
    assert %{desired: :playing, revision: 1} = RoomSession.current(name)

    RoomSession.set_desired(:paused, name)
    _ = :sys.get_state(pid)
    assert %{desired: :paused, revision: 1} = RoomSession.current(name)

    RoomSession.set_desired(:paused, name)
    _ = :sys.get_state(pid)
    assert %{desired: :paused, revision: 1} = RoomSession.current(name)
  end
end
