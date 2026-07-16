defmodule Kino.Media.TrackIdentityTest do
  use ExUnit.Case, async: true

  alias Kino.Media.TrackIdentity

  test "separates labels and preserves remix versions as distinct identities" do
    identity =
      TrackIdentity.from_entry(%{
        "artist" => "Lenzman",
        "title" => "In My Mind feat IAMDDB (Break Remix) • THE NORTH QUARTER"
      })

    assert identity.artist == "Lenzman"
    assert identity.base_title == "In My Mind feat IAMDDB"
    assert identity.remix_name == "Break Remix"
    assert identity.version_type == "remix"
    assert identity.label_name == "THE NORTH QUARTER"
    assert TrackIdentity.fingerprint(identity) =~ "break-remix::remix"
  end

  test "marks rows without artist evidence as unresolved" do
    refute TrackIdentity.from_entry(%{"artist" => nil, "title" => "VISION Radio Intro"}).resolvable?
  end
end
