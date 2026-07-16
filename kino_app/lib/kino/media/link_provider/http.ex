defmodule Kino.Media.LinkProvider.Http do
  @moduledoc "Req-backed provider adapters for the cross-platform link resolver."

  @behaviour Kino.Media.LinkProvider

  @impl true
  def search(recording), do: search(recording, :apple_music)

  @impl true
  def search(recording, :apple_music) do
    with {:ok, body} <-
           get_json("https://itunes.apple.com/search",
             params: [term: query(recording), entity: "song", limit: 10]
           ) do
      {:ok,
       Enum.map(body["results"] || [], fn item ->
         candidate(
           item["artistName"],
           item["trackName"],
           item["trackViewUrl"],
           item["trackId"]
         )
       end)}
    end
  end

  def search(recording, :deezer) do
    with {:ok, body} <-
           get_json("https://api.deezer.com/search",
             params: [q: query(recording), limit: 10]
           ) do
      {:ok,
       Enum.map(body["data"] || [], fn item ->
         candidate(get_in(item, ["artist", "name"]), item["title"], item["link"], item["id"])
       end)}
    end
  end

  def search(recording, :spotify) do
    with {:ok, token} <- spotify_token(),
         {:ok, body} <-
           get_json("https://api.spotify.com/v1/search",
             params: [q: query(recording), type: "track", limit: 10],
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      {:ok,
       Enum.map(get_in(body, ["tracks", "items"]) || [], fn item ->
         artist = item |> Map.get("artists", []) |> List.first() |> then(&(&1 || %{})["name"])
         candidate(artist, item["name"], get_in(item, ["external_urls", "spotify"]), item["id"])
       end)}
    end
  end

  def search(recording, :soundcloud) do
    with {:ok, client_id} <- credential("SOUNDCLOUD_CLIENT_ID"),
         {:ok, body} <-
           get_json("https://api-v2.soundcloud.com/search/tracks",
             params: [q: query(recording), limit: 10, client_id: client_id]
           ) do
      {:ok,
       Enum.map(body["collection"] || [], fn item ->
         candidate(
           get_in(item, ["user", "username"]),
           item["title"],
           item["permalink_url"],
           item["id"]
         )
       end)}
    end
  end

  def search(recording, :discogs) do
    headers =
      case System.get_env("DISCOGS_TOKEN") do
        token when is_binary(token) and token != "" ->
          [{"authorization", "Discogs token=#{token}"}]

        _ ->
          []
      end

    with {:ok, body} <-
           get_json("https://api.discogs.com/database/search",
             params: [q: query(recording), type: "release", per_page: 10],
             headers: headers
           ) do
      {:ok,
       Enum.map(body["results"] || [], fn item ->
         {artist, title} = split_discogs_title(item["title"])
         candidate(artist, title, discogs_url(item), item["id"])
       end)}
    end
  end

  def search(recording, platform) when platform in [:bandcamp, :beatport] do
    base =
      case platform do
        :bandcamp -> "https://bandcamp.com/search"
        :beatport -> "https://www.beatport.com/search"
      end

    with {:ok, body} <- get_text(base, params: [q: query(recording)]) do
      {:ok, extract_html_candidates(body, platform)}
    end
  end

  def catalog(:deezer, external_id) do
    with {:ok, track} <- get_json("https://api.deezer.com/track/#{external_id}", []) do
      {:ok,
       %{
         "release" =>
           release(
             get_in(track, ["album", "id"]),
             get_in(track, ["album", "title"]),
             get_in(track, ["album", "cover_xl"])
           ),
         "credits" =>
           Enum.map(track["contributors"] || [], &credit(&1["id"], &1["name"], &1["role"])),
         "isrc" => track["isrc"],
         "duration_seconds" => track["duration"],
         "bpm" => track["bpm"]
       }}
    end
  end

  def catalog(:apple_music, external_id) do
    with {:ok, body} <-
           get_json("https://itunes.apple.com/lookup", params: [id: external_id, entity: "song"]) do
      item = List.first(body["results"] || []) || %{}

      {:ok,
       %{
         "release" =>
           release(item["collectionId"], item["collectionName"], item["artworkUrl100"]),
         "credits" => [credit(item["artistId"], item["artistName"], "primary")],
         "duration_seconds" =>
           if(item["trackTimeMillis"], do: div(item["trackTimeMillis"], 1000)),
         "genre" => item["primaryGenreName"],
         "release_date" => item["releaseDate"]
       }}
    end
  end

  def catalog(:discogs, external_id) do
    headers =
      case System.get_env("DISCOGS_TOKEN") do
        token when is_binary(token) and token != "" ->
          [{"authorization", "Discogs token=#{token}"}]

        _ ->
          []
      end

    with {:ok, body} <-
           get_json("https://api.discogs.com/releases/#{external_id}", headers: headers) do
      {:ok,
       %{
         "release" =>
           release(body["id"], body["title"], get_in(body, ["images", Access.at(0), "uri"])),
         "credits" =>
           Enum.map(body["artists"] || [], &credit(&1["id"], &1["name"], &1["role"] || "primary")),
         "tracks" =>
           Enum.map(
             body["tracklist"] || [],
             &%{
               "position" => &1["position"],
               "title" => &1["title"],
               "duration" => &1["duration"]
             }
           ),
         "genres" => body["genres"] || [],
         "styles" => body["styles"] || [],
         "labels" => body["labels"] || [],
         "release_year" => body["year"]
       }}
    end
  end

  def catalog(platform, external_id) when platform in [:bandcamp, :beatport] do
    url = to_string(external_id)

    with true <- String.starts_with?(url, "http"),
         {:ok, body} <- get_text(url, []) do
      {:ok, %{"page_metadata" => extract_json_ld(body), "source_url" => url}}
    else
      _ -> {:error, "catalog URL unavailable"}
    end
  end

  def catalog(_platform, _external_id), do: {:error, "catalog adapter unavailable"}

  defp get_json(url, opts) do
    case Req.get(url, request_options(opts)) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        Jason.decode(body)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp get_text(url, opts) do
    case Req.get(url, request_options(opts)) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp request_options(opts) do
    Keyword.merge(
      [
        connect_options: [timeout: 5_000],
        pool_timeout: 5_000,
        receive_timeout: 12_000,
        retry: false,
        headers: [{"user-agent", "Kino/0.1 music-link-resolver"}]
      ],
      opts,
      fn
        :headers, left, right -> left ++ right
        _key, _left, right -> right
      end
    )
  end

  defp spotify_token do
    with {:ok, id} <- credential("SPOTIFY_CLIENT_ID"),
         {:ok, secret} <- credential("SPOTIFY_CLIENT_SECRET"),
         {:ok, %{status: 200, body: %{"access_token" => token}}} <-
           Req.post("https://accounts.spotify.com/api/token",
             form: [grant_type: "client_credentials"],
             auth: {:basic, "#{id}:#{secret}"},
             connect_options: [timeout: 5_000],
             pool_timeout: 5_000,
             receive_timeout: 12_000,
             retry: false
           ) do
      {:ok, token}
    else
      {:error, reason} -> {:error, reason}
      {:ok, %{status: status}} -> {:error, "Spotify token HTTP #{status}"}
    end
  end

  defp credential(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{name} is not configured"}
    end
  end

  defp extract_html_candidates(body, platform) do
    host =
      if platform == :bandcamp,
        do: ~r{https?://[^"' ]+\.bandcamp\.com/(?:track|album)/[^"' ?<]+},
        else: ~r{https?://(?:www\.)?beatport\.com/(?:track|release)/[^"' ?<]+}

    host
    |> Regex.scan(body)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.take(10)
    |> Enum.map(fn url ->
      slug =
        url
        |> URI.parse()
        |> Map.get(:path)
        |> Path.basename()
        |> URI.decode()
        |> String.replace("-", " ")

      candidate(nil, slug, url, url)
    end)
  end

  defp split_discogs_title(value) do
    case String.split(to_string(value), " - ", parts: 2) do
      [artist, title] -> {artist, title}
      [title] -> {nil, title}
    end
  end

  defp discogs_url(%{"type" => "master", "id" => id}), do: "https://www.discogs.com/master/#{id}"
  defp discogs_url(%{"id" => id}), do: "https://www.discogs.com/release/#{id}"

  defp query(recording), do: "#{recording.artist} #{recording.title}"

  defp candidate(artist, title, url, external_id) do
    %{artist: artist, title: title, url: url, external_id: external_id}
  end

  defp release(nil, nil, _artwork), do: nil

  defp release(id, title, artwork),
    do: %{"external_id" => id, "title" => title, "artwork" => artwork}

  defp credit(nil, nil, _role), do: %{}
  defp credit(id, name, role), do: %{"external_id" => id, "name" => name, "role" => role}

  defp extract_json_ld(body) do
    case Regex.run(
           ~r/<script[^>]+type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/isu,
           body,
           capture: :all_but_first
         ) do
      [json] ->
        case Jason.decode(json) do
          {:ok, value} -> value
          _ -> %{}
        end

      _ ->
        %{}
    end
  end
end
