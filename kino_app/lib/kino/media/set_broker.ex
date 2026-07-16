defmodule Kino.Media.SetBroker do
  @moduledoc "Ontology-first coordinator for setlist identity and provider enrichment."

  import Ecto.Query

  alias Kino.Media.{
    CatalogEnrichmentWorker,
    EntityKey,
    LinkResolver,
    MediaAsset,
    MusicPlatformLink,
    MusicPlatformLookup,
    MusicTrack,
    PlatformEnrichmentWorker,
    SetEntryResolution,
    TrackIdentity
  }

  alias Kino.Repo

  @retry_seconds 86_400

  def enqueue(%MediaAsset{id: id}) do
    Oban.insert(Kino.Media.SetEnrichmentWorker.new(%{"media_asset_id" => id}))
  end

  def resolve_query(query) do
    with {:ok, recording} <- LinkResolver.parse_query(query) do
      identity = %{
        artist: recording.artist,
        title: recording.title,
        base_title: recording.title,
        remix_name: nil,
        version_type: nil,
        label_name: nil,
        resolvable?: true
      }

      track = upsert_track(identity)

      LinkResolver.providers()
      |> Task.async_stream(
        fn {platform, _provider} -> enrich_platform(track.id, to_string(platform)) end,
        ordered: false,
        timeout: 20_000,
        on_timeout: :kill_task
      )
      |> Stream.run()

      links =
        from(l in MusicPlatformLink,
          where:
            l.entity_type == "track" and l.entity_id == ^track.id and l.confidence >= 0.8 and
              l.source != "set_ingest",
          order_by: l.platform
        )
        |> Repo.all()

      {:ok, %{recording: recording, track: track, matches: links}}
    end
  end

  def ingest_asset(%MediaAsset{} = asset) do
    set_key = asset.ontology_key || EntityKey.recording(asset.source_url)

    set_node =
      upsert_node(set_key, "dj_set", asset.title || set_key, asset.source_url, %{
        entry_count: length(asset.chapters || [])
      })

    Enum.each(asset.chapters || [], fn entry ->
      ingest_entry(asset, set_key, set_node, entry)
    end)

    Kino.Media.broadcast({:set_enrichment_updated, asset.id})
    :ok
  end

  def enrich_platform(track_id, platform_name) do
    with %MusicTrack{} = track <- Repo.get(MusicTrack, track_id),
         {platform, provider} <- provider_for(platform_name),
         :ok <- eligible_lookup?(track.id, platform_name) do
      recording = %{artist: track_artist(track), title: track.title}

      case LinkResolver.search_provider(platform, provider, recording) do
        {:ok, match} ->
          case persist_platform_match(track, match) do
            {:ok, _} ->
              update_lookup(track.id, platform_name, "matched", 1, nil)
              enqueue_catalog(track.id, platform_name)
              refresh_track_status(track.id)
              broadcast_track(track.id)
              :ok

            {:error, changeset} ->
              update_lookup(track.id, platform_name, "error", 1, inspect(changeset.errors))
              refresh_track_status(track.id)
              {:error, changeset}
          end

        {:unavailable, _platform, reason} ->
          update_lookup(track.id, platform_name, "missing", 0, reason)
          refresh_track_status(track.id)
          broadcast_track(track.id)
          :ok
      end
    else
      nil -> {:discard, "track not found"}
      :cached -> :ok
      :unknown_provider -> {:discard, "unknown provider"}
    end
  end

  def enrich_catalog(track_id, platform_name) do
    with %MusicTrack{} = track <- Repo.get(MusicTrack, track_id),
         %MusicPlatformLink{} = link <-
           Repo.get_by(MusicPlatformLink,
             entity_type: "track",
             entity_id: track_id,
             platform: platform_name
           ),
         {platform, {module, _provider_opts}} <- provider_for(platform_name),
         true <- function_exported?(module, :catalog, 2),
         {:ok, catalog} <- module.catalog(platform, link.external_id) do
      attrs =
        Map.merge(track.attrs || %{}, catalog)
        |> Map.put("catalog_enriched", %{
          platform_name => DateTime.utc_now() |> DateTime.to_iso8601()
        })
        |> Map.put("source_url", link.url)

      track
      |> MusicTrack.changeset(%{attrs: attrs, enriched_at: DateTime.utc_now(:second)})
      |> Repo.update()

      project_catalog(track, platform_name, catalog)
      :ok
    else
      _ -> :ok
    end
  end

  def resolutions_for_asset(asset_id) do
    resolutions =
      from(r in SetEntryResolution, where: r.media_asset_id == ^asset_id, order_by: r.position)
      |> Repo.all()

    track_ids = resolutions |> Enum.map(& &1.track_id) |> Enum.reject(&is_nil/1)

    links =
      from(l in MusicPlatformLink,
        where:
          l.entity_type == "track" and l.entity_id in ^track_ids and l.confidence >= 0.8 and
            l.source != "set_ingest",
        order_by: [asc: l.platform]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.entity_id)

    Map.new(resolutions, fn resolution ->
      {resolution.position,
       %{resolution: resolution, links: Map.get(links, resolution.track_id, [])}}
    end)
  end

  def reconcile_asset(asset_id) do
    from(r in SetEntryResolution,
      where: r.media_asset_id == ^asset_id and not is_nil(r.track_id),
      select: r.track_id,
      distinct: true
    )
    |> Repo.all()
    |> Enum.each(&refresh_track_status/1)

    Kino.Media.broadcast({:set_enrichment_updated, asset_id})
    :ok
  end

  defp ingest_entry(asset, set_key, set_node, entry) do
    identity = TrackIdentity.from_entry(entry)
    entry_key = EntityKey.set_entry(set_key, entry["position"])

    entry_node =
      upsert_node(
        entry_key,
        "set_entry",
        entry["label"],
        nil,
        Map.take(entry, ["position", "start_seconds", "end_seconds"])
      )

    link_nodes(
      set_node,
      entry_node,
      "contains_entry",
      1.0,
      Map.take(entry, ["position", "start_seconds", "end_seconds"])
    )

    resolution = upsert_resolution(asset.id, set_key, entry_key, entry, identity)

    if identity.resolvable? do
      track = upsert_track(identity)

      work_node =
        upsert_node(track.canonical_work_key, "canonical_work", track.title, nil, %{
          artist: identity.artist,
          fingerprint: track.canonical_fingerprint
        })

      artist_node = upsert_node(slug(identity.artist), "artist", identity.artist, nil, %{})
      link_nodes(entry_node, work_node, "resolves_to", 1.0, %{confidence: 1.0})

      link_nodes(set_node, work_node, "contains_entry", 1.0, %{
        position: entry["position"],
        entry_key: entry_key
      })

      link_nodes(work_node, artist_node, "performed_by", 1.0, %{})
      anchor_set_entry(track, asset, set_key, entry)

      resolution
      |> SetEntryResolution.changeset(%{
        status: "resolving",
        track_id: track.id,
        work_key: track.canonical_work_key,
        confidence: 1.0
      })
      |> Repo.update!()

      enqueue_missing_providers(track)
    else
      resolution |> SetEntryResolution.changeset(%{status: "unresolved"}) |> Repo.update!()
    end
  end

  defp upsert_resolution(asset_id, set_key, entry_key, entry, identity) do
    attrs = %{
      media_asset_id: asset_id,
      position: entry["position"],
      set_key: set_key,
      entry_key: entry_key,
      raw_label: entry["label"],
      artist: identity.artist,
      title: identity.title,
      base_title: identity.base_title,
      remix_name: identity.remix_name,
      version_type: identity.version_type,
      label_name: identity.label_name,
      status: "pending"
    }

    case Repo.get_by(SetEntryResolution, media_asset_id: asset_id, position: entry["position"]) do
      nil -> %SetEntryResolution{} |> SetEntryResolution.changeset(attrs) |> Repo.insert!()
      row -> row |> SetEntryResolution.changeset(attrs) |> Repo.update!()
    end
  end

  defp upsert_track(identity) do
    fingerprint = TrackIdentity.fingerprint(identity)
    artist_id = upsert_artist(identity.artist)

    attrs = %{
      title: identity.title,
      base_title: identity.base_title,
      remix_name: identity.remix_name,
      version_type: identity.version_type,
      canonical_fingerprint: fingerprint,
      canonical_work_key: TrackIdentity.work_key(identity),
      primary_artist_id: artist_id,
      attrs: %{"label" => identity.label_name}
    }

    case Repo.get_by(MusicTrack, canonical_fingerprint: fingerprint) do
      nil -> %MusicTrack{} |> MusicTrack.changeset(attrs) |> Repo.insert!()
      track -> track |> MusicTrack.changeset(attrs) |> Repo.update!()
    end
  end

  defp upsert_artist(name) do
    case Repo.query!(
           "SELECT id FROM music_artist WHERE lower(name)=lower($1) ORDER BY created_at LIMIT 1",
           [name]
         ).rows do
      [[id] | _] ->
        id

      [] ->
        Repo.query!("INSERT INTO music_artist(name,sort_name) VALUES($1,$1) RETURNING id", [name]).rows
        |> hd()
        |> hd()
    end
  end

  defp anchor_set_entry(track, asset, set_key, entry) do
    {platform, external_set_id} = split_key(set_key)
    external_id = "#{external_set_id}##{entry["position"]}"

    attrs = %{
      entity_type: "track",
      entity_id: track.id,
      platform: platform,
      external_id: external_id,
      url: asset.source_url,
      confidence: 0.95,
      source: "set_ingest",
      resolved_by: "setlist",
      attrs: %{
        "set_key" => set_key,
        "position" => entry["position"],
        "start_seconds" => entry["start_seconds"]
      }
    }

    %MusicPlatformLink{}
    |> MusicPlatformLink.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:platform, :external_id])
  end

  defp enqueue_missing_providers(track) do
    existing =
      from(l in MusicPlatformLink,
        where: l.entity_type == "track" and l.entity_id == ^track.id,
        select: l.platform
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.each(LinkResolver.providers(), fn {platform, _provider} ->
      name = to_string(platform)

      if not MapSet.member?(existing, name) and lookup_due?(track.id, name),
        do: enqueue_provider(track.id, name)
    end)
  end

  defp enqueue_provider(track_id, platform) do
    Repo.transaction(fn ->
      case Oban.insert(
             PlatformEnrichmentWorker.new(%{"track_id" => track_id, "platform" => platform})
           ) do
        {:ok, %Oban.Job{conflict?: false} = job} ->
          # Commit the lookup marker with the job. That prevents a fast worker,
          # or a later idempotent ingest that hits Oban uniqueness, from
          # overwriting a terminal result back to "queued".
          update_lookup(track_id, platform, "queued", 0, nil, nil)
          job

        {:ok, %Oban.Job{} = job} ->
          job

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp enqueue_catalog(track_id, platform),
    do:
      Oban.insert(CatalogEnrichmentWorker.new(%{"track_id" => track_id, "platform" => platform}))

  defp lookup_due?(track_id, platform) do
    case Repo.get_by(MusicPlatformLookup, track_id: track_id, platform: platform) do
      nil -> true
      %{status: "matched"} -> false
      %{retry_after: nil} -> true
      %{retry_after: retry_after} -> DateTime.compare(retry_after, DateTime.utc_now()) != :gt
    end
  end

  defp eligible_lookup?(track_id, platform),
    do: if(lookup_due?(track_id, platform), do: :ok, else: :cached)

  defp update_lookup(track_id, platform, status, count, error, retry_after \\ :default) do
    now = DateTime.utc_now(:second)

    retry_after =
      if retry_after == :default and status in ["missing", "error"],
        do: DateTime.add(now, @retry_seconds),
        else: retry_after

    attrs = %{
      track_id: track_id,
      platform: platform,
      status: status,
      candidate_count: count,
      last_attempt_at: now,
      retry_after: retry_after,
      error: error
    }

    %MusicPlatformLookup{}
    |> MusicPlatformLookup.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:status, :candidate_count, :last_attempt_at, :retry_after, :error, :updated_at]},
      conflict_target: [:track_id, :platform]
    )
  end

  defp provider_for(name) do
    Enum.find_value(LinkResolver.providers(), :unknown_provider, fn {platform, provider} ->
      if to_string(platform) == name, do: {platform, provider}
    end)
  end

  defp persist_platform_match(track, match) do
    attrs = %{
      entity_type: "track",
      entity_id: track.id,
      platform: to_string(match.platform),
      external_id: to_string(match.external_id),
      url: match.url,
      confidence: match.confidence,
      source: "resolver",
      resolved_by: "artist_title_similarity",
      attrs: %{"title" => match.title, "artist" => match.artist}
    }

    result =
      %MusicPlatformLink{}
      |> MusicPlatformLink.changeset(attrs)
      |> Repo.insert(
        on_conflict:
          {:replace,
           [
             :entity_type,
             :entity_id,
             :url,
             :confidence,
             :source,
             :resolved_by,
             :attrs,
             :updated_at
           ]},
        conflict_target: [:platform, :external_id]
      )

    case result do
      {:ok, link} ->
        recording_node =
          upsert_node(
            "#{link.platform}:#{link.external_id}",
            "recording",
            link.attrs["title"] || track.title,
            link.url,
            link.attrs
          )

        work_node =
          upsert_node(track.canonical_work_key, "canonical_work", track.title, nil, track.attrs)

        link_nodes(work_node, recording_node, "has_recording", link.confidence, %{
          source: "resolver"
        })

      _ ->
        :ok
    end

    result
  end

  defp broadcast_track(track_id) do
    from(r in SetEntryResolution,
      where: r.track_id == ^track_id,
      select: r.media_asset_id,
      distinct: true
    )
    |> Repo.all()
    |> Enum.each(&Kino.Media.broadcast({:set_enrichment_updated, &1}))
  end

  defp refresh_track_status(track_id) do
    Repo.transaction(fn ->
      # Provider jobs for one track finish concurrently. Serialize their final
      # snapshot so an older "queued" map cannot overwrite the completed one.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [track_id])

      statuses =
        from(l in MusicPlatformLookup,
          where: l.track_id == ^track_id,
          select: {l.platform, l.status}
        )
        |> Repo.all()
        |> Map.new()

      expected = LinkResolver.providers() |> Enum.map(fn {platform, _} -> to_string(platform) end)

      complete? =
        Enum.all?(expected, &(Map.get(statuses, &1) in ["matched", "missing", "error"]))

      status = if complete?, do: "enriched", else: "resolving"

      from(r in SetEntryResolution, where: r.track_id == ^track_id)
      |> Repo.update_all(
        set: [status: status, provider_status: statuses, updated_at: DateTime.utc_now(:second)]
      )
    end)
  end

  defp project_catalog(track, platform, catalog) do
    work_node =
      upsert_node(track.canonical_work_key, "canonical_work", track.title, nil, track.attrs)

    Enum.each(catalog["credits"] || [], fn credit ->
      if name = credit["name"] do
        artist_node =
          upsert_node(
            "#{platform}:artist:#{credit["external_id"] || slug(name)}",
            "artist",
            name,
            nil,
            credit
          )

        link_nodes(work_node, artist_node, "performed_by", 1.0, %{"role" => credit["role"]})
      end
    end)

    if release = catalog["release"] do
      release_key =
        "#{platform}:release:#{release["external_id"] || slug(release["title"] || track.title)}"

      release_node =
        upsert_node(release_key, "release", release["title"] || track.title, nil, release)

      link_nodes(work_node, release_node, "appears_on", 1.0, %{})

      Enum.each(catalog["tracks"] || [], fn item ->
        item_key = "#{release_key}:track:#{item["position"] || slug(item["title"] || "unknown")}"
        item_node = upsert_node(item_key, "canonical_work", item["title"] || item_key, nil, item)

        link_nodes(release_node, item_node, "contains_entry", 1.0, %{
          "position" => item["position"]
        })
      end)
    end
  end

  defp track_artist(%MusicTrack{primary_artist_id: nil}), do: ""

  defp track_artist(track),
    do:
      Repo.query!("SELECT name FROM music_artist WHERE id=$1", [
        Ecto.UUID.dump!(track.primary_artist_id)
      ]).rows
      |> List.first()
      |> List.first()

  defp upsert_node(domain_id, type, label, description, attrs) do
    Repo.query!(
      """
      INSERT INTO ontology_node(domain,domain_id,node_type,label,slug,description,attrs)
      VALUES('music',$1,$2,$3,$4,$5,$6)
      ON CONFLICT(domain,domain_id,node_type) DO UPDATE SET label=EXCLUDED.label,
        description=COALESCE(EXCLUDED.description,ontology_node.description), attrs=ontology_node.attrs||EXCLUDED.attrs, updated_at=now()
      RETURNING id
      """,
      [domain_id, type, label || domain_id, slug(domain_id), description, attrs]
    ).rows
    |> hd()
    |> hd()
  end

  defp link_nodes(source, target, type, confidence, evidence) do
    Repo.query!(
      """
      INSERT INTO ontology_edge(source_id,target_id,edge_type,dimension,confidence,evidence)
      VALUES($1,$2,$3,'semantic',$4,$5)
      ON CONFLICT(source_id,target_id,edge_type,dimension) DO UPDATE SET confidence=EXCLUDED.confidence,evidence=EXCLUDED.evidence
      """,
      [source, target, type, confidence, evidence]
    )
  end

  defp split_key(key) do
    case String.split(key, ":", parts: 2) do
      [platform, id] -> {platform, id}
      [id] -> {"url", id}
    end
  end

  defp slug(value),
    do:
      value
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 96)
end
