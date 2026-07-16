defmodule Kino.Media.SetBrokerTest do
  use Kino.DataCase
  use Oban.Testing, repo: Kino.Repo

  alias Kino.Media.{MediaAsset, MusicPlatformLink, SetBroker, SetEntryResolution}
  alias Kino.Repo

  setup do
    previous = Application.get_env(:kino, :music_link_providers)
    Application.put_env(:kino, :music_link_providers, deezer: Kino.TestMusicLinkProviderStub)
    on_exit(fn -> Application.put_env(:kino, :music_link_providers, previous) end)
  end

  test "projects every row, skips weak rows, and enriches resolvable tracks" do
    asset =
      %MediaAsset{}
      |> MediaAsset.changeset(%{
        source_url: "https://youtu.be/set-broker",
        cache_key: "set-broker",
        ontology_key: "yt:set-broker",
        provider: "youtube.com",
        status: "ready",
        title: "Broker Set",
        chapters: [
          %{
            "position" => 1,
            "start_seconds" => 0,
            "end_seconds" => 30,
            "label" => "Radio Intro",
            "artist" => nil,
            "title" => "Radio Intro"
          },
          %{
            "position" => 2,
            "start_seconds" => 30,
            "end_seconds" => 90,
            "label" => "Current Value - Farside",
            "artist" => "Current Value",
            "title" => "Farside"
          }
        ]
      })
      |> Repo.insert!()

    assert :ok = SetBroker.ingest_asset(asset)

    assert %SetEntryResolution{status: "unresolved", track_id: nil} =
             Repo.get_by!(SetEntryResolution, media_asset_id: asset.id, position: 1)

    assert %SetEntryResolution{status: "resolving", track_id: track_id} =
             Repo.get_by!(SetEntryResolution, media_asset_id: asset.id, position: 2)

    assert_enqueued(
      worker: Kino.Media.PlatformEnrichmentWorker,
      args: %{"track_id" => track_id, "platform" => "deezer"}
    )

    assert :ok = SetBroker.enrich_platform(track_id, "deezer")

    assert %MusicPlatformLink{confidence: 1.0, url: "https://music.example/track/match-1"} =
             Repo.get_by!(MusicPlatformLink, entity_id: track_id, platform: "deezer")

    projected = SetBroker.resolutions_for_asset(asset.id)
    assert length(projected[2].links) == 1

    assert Repo.aggregate(
             from(n in "ontology_node", where: field(n, :node_type) == "set_entry"),
             :count
           ) == 2
  end
end
