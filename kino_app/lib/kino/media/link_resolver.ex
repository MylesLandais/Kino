defmodule Kino.Media.LinkResolver do
  @moduledoc "Resolve a recording across music platforms and retain confident ontology links."

  alias Kino.Media.{EntityKey, MusicPlatformLink}
  alias Kino.Repo

  @threshold 0.80

  def providers, do: Application.get_env(:kino, :music_link_providers, [])

  def search_provider(platform, provider, recording) do
    resolve_provider(platform, provider, recording)
  end

  def resolve(query, opts \\ []) do
    with {:ok, recording} <- parse_query(query) do
      providers = Keyword.get(opts, :providers, configured_providers())

      results =
        providers
        |> Task.async_stream(
          fn {platform, provider} -> resolve_provider(platform, provider, recording) end,
          ordered: false,
          timeout: Keyword.get(opts, :timeout, 20_000),
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, "provider task failed: #{inspect(reason)}"}
        end)

      matches = for {:ok, match} <- results, do: match

      provider_errors =
        for {:unavailable, platform, reason} <- results, into: %{}, do: {platform, reason}

      entity_id = entity_id(recording)

      {persisted, persistence_errors} =
        Enum.reduce(matches, {[], %{}}, fn match, {accepted, errors} ->
          case persist(entity_id, recording, match) do
            {:ok, _link} ->
              {[match | accepted], errors}

            {:error, reason} ->
              {accepted, Map.put(errors, match.platform, inspect(reason.errors))}
          end
        end)

      {:ok,
       %{
         recording: recording,
         entity_id: entity_id,
         matches: Enum.reverse(persisted),
         unavailable: Map.merge(provider_errors, persistence_errors)
       }}
    end
  end

  def parse_query(query) do
    value = String.trim(query || "")

    case Regex.run(~r/^(.+?)\s+(?:—|–|-|::)\s+(.+)$/u, value, capture: :all_but_first) do
      [artist, title] ->
        {:ok, %{artist: String.trim(artist), title: String.trim(title)}}

      _ ->
        {:error, "Use /wish Artist — Track so I can resolve the recording confidently."}
    end
  end

  def confidence(wanted, candidate) do
    artist = similarity(wanted.artist, candidate[:artist] || candidate["artist"])
    title = similarity(wanted.title, candidate[:title] || candidate["title"])

    score =
      if candidate[:artist] || candidate["artist"] do
        title * 0.6 + artist * 0.4
      else
        title
      end

    Float.round(score, 4)
  end

  defp resolve_provider(platform, provider, recording) do
    response =
      case provider do
        {module, provider_opts} -> module.search(recording, provider_opts)
        module -> module.search(recording)
      end

    case response do
      {:ok, candidates} ->
        candidates
        |> Enum.filter(&valid_candidate?/1)
        |> Enum.map(&Map.put(&1, :confidence, confidence(recording, &1)))
        |> Enum.max_by(& &1.confidence, fn -> nil end)
        |> case do
          %{confidence: score} = match when score >= @threshold ->
            {:ok, match |> Map.put(:platform, platform) |> Map.put(:confidence, score)}

          _ ->
            {:unavailable, platform, "no match at or above 80%"}
        end

      {:error, reason} ->
        {:unavailable, platform, to_string(reason)}
    end
  rescue
    error -> {:unavailable, platform, Exception.message(error)}
  end

  defp persist(entity_id, recording, match) do
    attrs = %{
      entity_type: "track",
      entity_id: entity_id,
      platform: to_string(match.platform),
      external_id: to_string(match.external_id),
      url: match.url,
      confidence: match.confidence,
      source: "resolver",
      resolved_by: "artist_title_similarity",
      attrs: %{"artist" => recording.artist, "title" => recording.title}
    }

    %MusicPlatformLink{}
    |> MusicPlatformLink.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:entity_type, :entity_id, :url, :confidence, :source, :resolved_by, :attrs, :updated_at]},
      conflict_target: [:platform, :external_id]
    )
  end

  defp valid_candidate?(candidate) do
    is_binary(candidate[:url]) and candidate[:url] != "" and
      candidate[:external_id] not in [nil, ""] and
      is_binary(candidate[:title]) and candidate[:title] != ""
  end

  defp configured_providers do
    providers()
  end

  defp entity_id(recording) do
    key = "track:" <> normalize(recording.artist) <> ":" <> normalize(recording.title)
    EntityKey.uuid(key)
  end

  defp similarity(_, nil), do: 0.0

  defp similarity(left, right) do
    left = normalize(left)
    right = normalize(right)

    cond do
      left == "" or right == "" -> 0.0
      left == right -> 1.0
      true -> dice(left, right)
    end
  end

  defp dice(left, right) do
    a = bigrams(left)
    b = bigrams(right)
    overlap = MapSet.intersection(a, b) |> MapSet.size()
    2 * overlap / max(MapSet.size(a) + MapSet.size(b), 1)
  end

  defp bigrams(value) do
    chars = String.graphemes(value)

    case chars do
      [_] -> MapSet.new([value])
      _ -> chars |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.join/1) |> MapSet.new()
    end
  end

  defp normalize(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end
end
