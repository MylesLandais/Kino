defmodule Kino.Media.EntityKeyTest do
  use ExUnit.Case, async: true

  alias Kino.Media.EntityKey

  test "uses Maya-compatible recording and set-entry keys" do
    assert EntityKey.recording("https://youtu.be/MEFLPxFq0LY?t=4") == "yt:MEFLPxFq0LY"

    assert EntityKey.recording("https://www.youtube.com/watch?v=MEFLPxFq0LY") ==
             "yt:MEFLPxFq0LY"

    assert EntityKey.recording("https://example.com/live/set") == "url:example.com/live/set"
    assert EntityKey.set_entry("yt:MEFLPxFq0LY", 12) == "yt:MEFLPxFq0LY:12"
  end
end
