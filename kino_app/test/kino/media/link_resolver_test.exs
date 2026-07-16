defmodule Kino.Media.LinkResolverTest do
  use Kino.DataCase, async: true

  alias Kino.Media.{LinkResolver, MusicPlatformLink}
  alias Kino.Repo

  test "requires an artist and track title" do
    assert {:ok, %{artist: "Current Value", title: "Farside"}} =
             LinkResolver.parse_query("Current Value — Farside")

    assert {:error, _} = LinkResolver.parse_query("Farside")
  end

  test "scores normalized artist and title metadata" do
    wanted = %{artist: "Current Value", title: "FARSIDE"}

    assert LinkResolver.confidence(wanted, %{artist: "Current Value", title: "Farside"}) ==
             1.0

    assert LinkResolver.confidence(wanted, %{
             artist: "Someone Else",
             title: "Entirely Different"
           }) < 0.4
  end

  test "returns and persists only links meeting the 80 percent threshold" do
    providers = [
      deezer: Kino.TestMusicLinkProviderStub,
      spotify: {Kino.TestMusicLinkProviderStub, :low}
    ]

    assert {:ok, result} =
             LinkResolver.resolve("Current Value — Farside", providers: providers)

    assert [%{platform: :deezer, confidence: 1.0}] = result.matches
    assert result.unavailable.spotify == "no match at or above 80%"

    assert %MusicPlatformLink{
             entity_type: "track",
             platform: "deezer",
             external_id: "match-1",
             confidence: 1.0
           } = Repo.get_by(MusicPlatformLink, platform: "deezer", external_id: "match-1")

    refute Repo.get_by(MusicPlatformLink, platform: "spotify")
  end
end
