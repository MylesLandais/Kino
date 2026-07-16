defmodule Kino.MediaTest do
  use Kino.DataCase, async: false
  use Oban.Testing, repo: Kino.Repo

  alias Kino.Media
  alias Kino.Media.MediaAsset

  setup do
    Phoenix.PubSub.subscribe(Kino.PubSub, Media.topic())
    :ok
  end

  describe "request_play/2 URL validation" do
    test "rejects non-http(s) schemes" do
      assert {:error, reason} = Media.request_play("file:///etc/passwd", "you")
      assert reason =~ "only http(s)"
      refute_enqueued(worker: Kino.Media.DownloadWorker)
    end

    test "rejects strings without a host" do
      assert {:error, _} = Media.request_play("not a url", "you")
      assert {:error, _} = Media.request_play("https://", "you")
      refute_enqueued(worker: Kino.Media.DownloadWorker)
    end

    test "accepts an https URL and enqueues the worker" do
      assert {:ok, %MediaAsset{status: "pending"}} =
               Media.request_play("https://example.com/v/1", "you")

      assert_enqueued(worker: Kino.Media.DownloadWorker)
    end
  end

  describe "reactions" do
    setup do
      {:ok, asset} =
        %MediaAsset{}
        |> MediaAsset.changeset(%{
          source_url: "https://x.example/v",
          cache_key: "rk1",
          status: "ready"
        })
        |> Kino.Repo.insert()

      %{asset: asset}
    end

    test "toggle_reaction likes then unlikes and broadcasts", %{asset: asset} do
      assert :liked = Media.toggle_reaction(asset.id, 3, "warby")
      assert_received {:reactions_updated, _}
      assert %{3 => ["warby"]} = Media.reactions_for(asset.id)

      assert :unliked = Media.toggle_reaction(asset.id, 3, "warby")
      assert Media.reactions_for(asset.id) == %{}
    end

    test "reactions group multiple users per position", %{asset: asset} do
      Media.toggle_reaction(asset.id, 1, "a")
      Media.toggle_reaction(asset.id, 1, "b")
      Media.toggle_reaction(asset.id, 2, "a")

      reactions = Media.reactions_for(asset.id)
      assert Enum.sort(reactions[1]) == ["a", "b"]
      assert reactions[2] == ["a"]
    end
  end

  describe "request_play/2 duplicate guard" do
    test "does not re-enqueue while the asset is already pending or downloading" do
      url = "https://example.com/v/dup"
      {:ok, asset} = Media.request_play(url, "you")
      assert [_job] = all_enqueued(worker: Kino.Media.DownloadWorker)

      assert {:ok, %MediaAsset{id: id}} = Media.request_play(url, "you")
      assert id == asset.id
      assert [_job] = all_enqueued(worker: Kino.Media.DownloadWorker)
      assert_received {:agent_event, %{state: :working, text: "Already fetching" <> _}}

      {:ok, _} = Media.update_asset(Media.get_asset!(asset.id), %{status: "downloading"})
      assert {:ok, %MediaAsset{status: "downloading"}} = Media.request_play(url, "you")
      assert [_job] = all_enqueued(worker: Kino.Media.DownloadWorker)
    end

    test "a failed asset is retried with a fresh enqueue" do
      url = "https://example.com/v/retry"
      {:ok, asset} = Media.request_play(url, "you")
      {:ok, _} = Media.update_asset(asset, %{status: "failed", error: "boom"})

      assert {:ok, %MediaAsset{status: "pending"}} = Media.request_play(url, "you")
    end
  end
end
