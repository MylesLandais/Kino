defmodule Kino.Media do
  @moduledoc "Media ingestion context: /play requests, asset cache, pipeline broadcasts."

  import Ecto.Query

  alias Kino.Media.{AgentRun, EntityKey, MediaAsset, MusicPlayEvent, Storage, TrackReaction}
  alias Kino.Repo

  @topic "room:lobby"

  def topic, do: @topic

  @doc """
  Handle a /play request: reuse a ready cached asset or upsert one and
  enqueue the download worker. Broadcasts the initial pending agent event.
  """
  def request_play(url, requested_by) do
    with :ok <- validate_url(url) do
      do_request_play(url, requested_by)
    end
  end

  defp do_request_play(url, requested_by) do
    cache_key = cache_key(url)

    case get_asset_by_cache_key(cache_key) do
      %MediaAsset{status: "ready"} = asset ->
        if durable_asset?(asset) do
          Kino.Media.SetBroker.enqueue(asset)

          broadcast_agent(:success, "Cache hit — ready to play", %{
            cache_key: asset.cache_key,
            title: asset.title
          })

          Kino.Theater.RoomSession.play(asset, requested_by)
          {:ok, asset}
        else
          enqueue(asset, url, requested_by)
        end

      %MediaAsset{status: status} = asset when status in ["pending", "downloading"] ->
        # A crashed pipeline must not deadlock the URL: retry stale requests.
        if stale_pipeline?(asset) do
          enqueue(asset, url, requested_by)
        else
          broadcast_agent(:working, "Already fetching this source — hang tight", %{
            cache_key: asset.cache_key
          })

          {:ok, asset}
        end

      asset ->
        enqueue(asset, url, requested_by)
    end
  end

  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        :ok

      _ ->
        {:error, "invalid URL — only http(s) sources are supported"}
    end
  end

  defp enqueue(existing, url, requested_by) do
    attrs = %{
      source_url: url,
      cache_key: cache_key(url),
      ontology_key: EntityKey.recording(url),
      provider: provider(url)
    }

    changeset =
      case existing do
        nil -> MediaAsset.changeset(%MediaAsset{}, Map.put(attrs, :status, "pending"))
        asset -> MediaAsset.changeset(asset, %{status: "pending", error: nil})
      end

    with {:ok, asset} <- Repo.insert_or_update(changeset) do
      broadcast_agent(:pending, "Resolving video metadata…", %{url: url})

      case Application.fetch_env!(:kino, :media)[:resolve_mode] do
        :sync ->
          resolve_and_start(asset, requested_by)

        _ ->
          Task.Supervisor.start_child(Kino.TaskSupervisor, fn ->
            resolve_and_start(asset, requested_by)
          end)
      end

      {:ok, asset}
    end
  end

  defp stale_pipeline?(asset) do
    DateTime.diff(DateTime.utc_now(), asset.updated_at, :second) > 180
  end

  # Fast path: one yt-dlp -J probe gets title/duration/chapters plus a direct
  # progressive stream URL, so playback starts before the cache download.
  defp resolve_and_start(asset, requested_by) do
    do_resolve_and_start(asset, requested_by)
  rescue
    e ->
      require Logger
      Logger.error("resolve crashed: #{Exception.format(:error, e, __STACKTRACE__)}")
      fail_asset(asset, "resolve crashed: #{Exception.message(e)}")
  end

  defp do_resolve_and_start(asset, requested_by) do
    started_at = System.monotonic_time(:millisecond)

    case Kino.Media.YtDlp.impl().fetch_stream_info(asset.source_url) do
      {:ok, info} ->
        resolve_ms = System.monotonic_time(:millisecond) - started_at

        {:ok, asset} =
          update_asset(asset, %{
            title: info.title,
            duration_seconds: info.duration,
            chapters: info.chapters,
            description: info.description
          })

        Kino.Media.SetBroker.enqueue(asset)

        if info.stream_url do
          Kino.Theater.RoomSession.play_stream(asset, info.stream_url, requested_by)

          broadcast_agent(:working, "Streaming now — caching full quality in background", %{
            cache_key: asset.cache_key,
            title: asset.title,
            tracks: length(asset.chapters || []),
            resolved_in: "#{resolve_ms}ms"
          })
        else
          broadcast_agent(:working, "No instant stream available — downloading first", %{
            cache_key: asset.cache_key,
            title: asset.title
          })
        end

        enqueue_download(asset, requested_by)

      {:error, reason} ->
        fail_asset(asset, "metadata: #{reason}")
    end
  end

  defp enqueue_download(asset, requested_by) do
    {:ok, job} =
      Oban.insert(
        Kino.Media.DownloadWorker.new(%{
          "media_asset_id" => asset.id,
          "requested_by" => requested_by
        })
      )

    {:ok, _run} =
      %AgentRun{}
      |> AgentRun.changeset(%{media_asset_id: asset.id, oban_job_id: job.id, status: "pending"})
      |> Repo.insert()

    {:ok, asset}
  end

  def get_asset!(id), do: Repo.get!(MediaAsset, id)
  def get_asset(id), do: Repo.get(MediaAsset, id)

  def get_asset_by_cache_key(cache_key), do: Repo.get_by(MediaAsset, cache_key: cache_key)

  def update_asset(%MediaAsset{} = asset, attrs) do
    asset |> MediaAsset.changeset(attrs) |> Repo.update()
  end

  def fail_asset(%MediaAsset{} = asset, reason) do
    {:ok, asset} = update_asset(asset, %{status: "failed", error: reason})
    mark_runs(asset.id, "failed")
    broadcast_agent(:error, "Pipeline failed — #{reason}", %{cache_key: asset.cache_key})
    asset
  end

  def mark_runs(media_asset_id, status) do
    Repo.update_all(from(r in AgentRun, where: r.media_asset_id == ^media_asset_id),
      set: [status: status, updated_at: DateTime.utc_now(:second)]
    )
  end

  @doc "Toggle a heart on a setlist entry. Broadcasts {:reactions_updated, asset_id}."
  def toggle_reaction(media_asset_id, position, username, reaction \\ "heart") do
    query =
      from(r in TrackReaction,
        where:
          r.media_asset_id == ^media_asset_id and r.position == ^position and
            r.username == ^username and r.reaction == ^reaction
      )

    result =
      case Repo.one(query) do
        nil ->
          %TrackReaction{}
          |> TrackReaction.changeset(%{
            media_asset_id: media_asset_id,
            position: position,
            username: username,
            reaction: reaction
          })
          |> Repo.insert()
          |> case do
            {:ok, _} -> :liked
            # Lost a race with a concurrent insert; treat as already liked.
            {:error, _} -> :liked
          end

        existing ->
          Repo.delete(existing)
          :unliked
      end

    broadcast({:reactions_updated, media_asset_id})
    result
  end

  @doc "All reactions for an asset, as %{position => [username]}."
  def reactions_for(media_asset_id) do
    from(r in TrackReaction,
      where: r.media_asset_id == ^media_asset_id,
      order_by: r.inserted_at,
      select: {r.position, r.username}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "Record one idempotent qualified play in the shared music ontology."
  def record_qualified_play(asset, entry, listener_id, username, playback_session_id, seconds) do
    entity_key =
      EntityKey.set_entry(
        asset.ontology_key || EntityKey.recording(asset.source_url),
        entry["position"]
      )

    id = deterministic_uuid([playback_session_id, listener_id, entity_key])
    now = DateTime.utc_now()

    attrs = %{
      id: id,
      entity_type: "set_entry",
      entity_key: entity_key,
      source: "dashboard",
      played_at: now,
      source_url: asset.source_url,
      attrs: %{
        "surface" => "kino",
        "actor_type" => "kino_handle",
        "actor_key" => username,
        "listener_id" => listener_id,
        "playback_session_id" => playback_session_id,
        "set_key" => asset.ontology_key,
        "position" => entry["position"],
        "timestamp_seconds" => entry["start_seconds"],
        "artist" => entry["artist"],
        "title" => entry["title"] || entry["label"],
        "qualified_seconds" => seconds,
        "qualification_rule" => "min(30s,50pct)"
      }
    }

    result =
      %MusicPlayEvent{}
      |> MusicPlayEvent.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :id)

    case result do
      {:ok, %{id: ^id}} ->
        broadcast({:plays_updated, asset.id})
        :inserted

      {:ok, _} ->
        :duplicate

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc "Aggregate qualified play totals for a media asset by chapter position."
  def play_counts_for(%MediaAsset{} = asset) do
    prefix = (asset.ontology_key || EntityKey.recording(asset.source_url)) <> ":"

    keys =
      Enum.map(
        asset.chapters || [],
        &EntityKey.set_entry(String.trim_trailing(prefix, ":"), &1["position"])
      )

    from(event in MusicPlayEvent,
      where: event.entity_type == "set_entry" and event.entity_key in ^keys,
      group_by: event.entity_key,
      select: {event.entity_key, count(event.id)}
    )
    |> Repo.all()
    |> Map.new(fn {key, count} ->
      position = key |> String.replace_prefix(prefix, "") |> String.to_integer()
      {position, count}
    end)
  end

  def broadcast_agent(state, text, payload \\ %{}) do
    broadcast({:agent_event, %{state: state, text: text, payload: payload}})
  end

  def broadcast(message) do
    Phoenix.PubSub.broadcast(Kino.PubSub, @topic, message)
  end

  def cache_dir do
    Application.fetch_env!(:kino, :media)[:cache_dir] ||
      Path.join(:code.priv_dir(:kino), "media_cache")
  end

  def cache_key(url) do
    :crypto.hash(:sha256, String.trim(url))
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 16)
  end

  def object_key(cache_key) do
    prefix = Application.fetch_env!(:kino, :media)[:storage_prefix] || "kino/media"
    "#{String.trim(prefix, "/")}/#{cache_key}.mp4"
  end

  def durable_asset?(asset) do
    (is_binary(asset.file_path) and File.exists?(asset.file_path)) or
      (is_binary(asset.object_key) and Storage.impl().exists?(asset.object_key))
  end

  defp deterministic_uuid(parts) do
    hex =
      parts
      |> Enum.join("\0")
      |> then(&:crypto.hash(:sha256, &1))
      |> binary_part(0, 16)
      |> Base.encode16(case: :lower)

    <<a::binary-size(8), b::binary-size(4), _version::binary-size(4), variant::binary-size(4),
      e::binary>> = hex

    version = "5" <> binary_part(hex, 13, 3)

    variant_value =
      variant
      |> binary_part(0, 1)
      |> String.to_integer(16)
      |> Bitwise.band(0x3)
      |> Bitwise.bor(0x8)

    variant = Integer.to_string(variant_value, 16) <> binary_part(variant, 1, 3)
    "#{a}-#{b}-#{version}-#{variant}-#{e}"
  end

  defp provider(url) do
    case URI.parse(url).host do
      nil -> "unknown"
      host -> host |> String.replace_prefix("www.", "")
    end
  end
end
