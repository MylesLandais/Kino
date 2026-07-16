defmodule Kino.Media.DownloadWorker do
  use Oban.Worker,
    queue: :media,
    max_attempts: 3,
    unique: [
      fields: [:worker, :args],
      keys: [:media_asset_id],
      states: [:available, :scheduled, :executing, :retryable, :suspended]
    ]

  alias Kino.Media
  alias Kino.Media.YtDlp

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"media_asset_id" => id} = args,
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    asset = Media.get_asset!(id)
    requested_by = args["requested_by"]

    case ensure_downloaded(asset) do
      {:ok, asset} ->
        Media.mark_runs(asset.id, "success")
        # Swap playback to the cached file (position preserved for same media).
        Kino.Theater.RoomSession.promote_to_cache(asset, requested_by)
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Media.fail_asset(asset, reason)
        else
          Media.broadcast_agent(:working, "Durable storage failed — retrying", %{
            cache_key: asset.cache_key,
            attempt: attempt
          })
        end

        {:error, reason}
    end
  end

  defp ensure_downloaded(%{status: "ready"} = asset) do
    if Media.durable_asset?(asset) do
      Media.broadcast_agent(:success, "Cache hit — already stored", %{cache_key: asset.cache_key})
      {:ok, asset}
    else
      download(asset)
    end
  end

  defp ensure_downloaded(asset), do: download(asset)

  defp download(asset) do
    dest = Path.join(Media.cache_dir(), "#{asset.cache_key}.mp4")
    {:ok, asset} = Media.update_asset(asset, %{status: "downloading"})

    case YtDlp.impl().download(asset.source_url, dest, progress: progress_fun(asset)) do
      :ok ->
        %{size: size} = File.stat!(dest)

        object_key = Media.object_key(asset.cache_key)

        with {:ok, %{etag: etag}} <- Kino.Media.Storage.impl().put_file(object_key, dest) do
          {:ok, asset} =
            Media.update_asset(asset, %{
              status: "ready",
              file_path: dest,
              byte_size: size,
              storage_backend: storage_backend(),
              object_key: object_key,
              storage_etag: etag,
              uploaded_at: DateTime.utc_now(:second)
            })

          Media.broadcast_agent(:success, "Download complete — stored durably", %{
            cache_key: asset.cache_key,
            bytes: size,
            duration: format_duration(asset.duration_seconds)
          })

          {:ok, asset}
        else
          {:error, reason} -> {:error, "object upload: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "download: #{reason}"}
    end
  end

  # Throttled progress broadcasts: at most one per second or per 5% step.
  defp progress_fun(asset) do
    fn %{percent: percent} = update ->
      now = System.monotonic_time(:millisecond)
      {last_at, last_pct} = Process.get(:kino_progress, {0, -5.0})

      if now - last_at >= 1_000 or percent - last_pct >= 5.0 or percent >= 100.0 do
        Process.put(:kino_progress, {now, percent})
        Media.broadcast({:pipeline_progress, Map.put(update, :cache_key, asset.cache_key)})
      end
    end
  end

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) do
    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp storage_backend do
    Kino.Media.Storage.impl() |> Module.split() |> List.last() |> String.downcase()
  end
end
