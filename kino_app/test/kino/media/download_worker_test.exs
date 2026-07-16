defmodule Kino.Media.DownloadWorkerTest do
  use Kino.DataCase, async: false
  use Oban.Testing, repo: Kino.Repo

  alias Kino.Media
  alias Kino.Media.{DownloadWorker, MediaAsset}

  setup do
    Process.register(self(), :yt_dlp_stub_listener)
    Phoenix.PubSub.subscribe(Kino.PubSub, Media.topic())

    url = "https://www.youtube.com/watch?v=stub123"

    {:ok, asset} =
      %MediaAsset{}
      |> MediaAsset.changeset(%{
        source_url: url,
        cache_key: Media.cache_key(url),
        status: "pending"
      })
      |> Repo.insert()

    on_exit(fn ->
      File.rm(Path.join(Media.cache_dir(), "#{asset.cache_key}.mp4"))
      File.rm(Path.join(Media.cache_dir(), Media.object_key(asset.cache_key)))
    end)

    %{asset: asset}
  end

  test "downloads, marks asset ready, and broadcasts pipeline events", %{asset: asset} do
    assert :ok = perform_job(DownloadWorker, %{"media_asset_id" => asset.id})

    assert_received {:yt_dlp_stub, :download}

    asset = Media.get_asset!(asset.id)
    assert asset.status == "ready"
    assert File.exists?(asset.file_path)
    assert asset.byte_size > 0
    assert asset.storage_backend == "local"
    assert asset.object_key == "kino/media/#{asset.cache_key}.mp4"
    assert is_binary(asset.storage_etag)
    assert asset.uploaded_at

    assert_received {:pipeline_progress, %{percent: 100.0}}
    assert_received {:agent_event, %{state: :success}}

    assert_receive {:playback_updated,
                    %{cache_key: cache_key, desired: :playing, source: :cache, src: src}}

    assert cache_key == asset.cache_key
    assert src == "/media/#{asset.cache_key}"
  end

  test "cache promotion preserves the playback session created by the instant stream", %{
    asset: asset
  } do
    Kino.Theater.RoomSession.play_stream(asset, "https://stream.example/fast.mp4", "tester")
    streamed = Kino.Theater.RoomSession.current()

    assert :ok = perform_job(DownloadWorker, %{"media_asset_id" => asset.id})
    promoted = Kino.Theater.RoomSession.current()

    assert promoted.playback_session_id == streamed.playback_session_id
    assert promoted.source == :cache
  end

  test "second run is a cache hit and skips download", %{asset: asset} do
    assert :ok = perform_job(DownloadWorker, %{"media_asset_id" => asset.id})
    assert_received {:yt_dlp_stub, :download}

    assert :ok = perform_job(DownloadWorker, %{"media_asset_id" => asset.id})
    refute_received {:yt_dlp_stub, :download}
  end

  test "durable upload failures remain retryable before the final attempt", %{asset: asset} do
    media = Application.fetch_env!(:kino, :media)
    Application.put_env(:kino, :media, Keyword.put(media, :storage, Kino.Media.StorageFail))
    on_exit(fn -> Application.put_env(:kino, :media, media) end)

    assert {:error, _reason} = perform_job(DownloadWorker, %{"media_asset_id" => asset.id})
    assert Media.get_asset!(asset.id).status == "downloading"
    assert_received {:agent_event, %{state: :working, text: "Durable storage failed" <> _}}
  end

  test "metadata failure during resolve marks asset failed and broadcasts error" do
    {:ok, asset} = Media.request_play("https://fail.example/video", "tester")

    asset = Media.get_asset!(asset.id)
    assert asset.status == "failed"
    assert asset.error =~ "unsupported url"
    assert_received {:agent_event, %{state: :error}}
    refute_received {:yt_dlp_stub, :download}
  end

  test "resolve starts an instant stream and enqueues the cache download" do
    {:ok, asset} = Media.request_play("https://www.youtube.com/watch?v=instant", "tester")

    assert_received {:yt_dlp_stub, :fetch_stream_info}

    assert_receive {:playback_updated,
                    %{
                      source: :stream,
                      src: "https://stream.example/stub720.mp4",
                      desired: :playing
                    } =
                      state}

    assert length(state.chapters) == 2
    assert_enqueued(worker: DownloadWorker, args: %{"media_asset_id" => asset.id})

    asset = Media.get_asset!(asset.id)
    assert asset.title == "Stub Video"
    assert asset.duration_seconds == 212
  end

  test "resolve without a progressive stream still enqueues the download" do
    {:ok, _asset} = Media.request_play("https://nostream.example/video", "tester")

    assert_received {:agent_event, %{state: :working, text: "No instant stream" <> _}}
    refute_received {:playback_updated, %{source: :stream}}
    assert_enqueued(worker: DownloadWorker)
  end
end
