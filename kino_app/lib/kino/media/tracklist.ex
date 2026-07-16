defmodule Kino.Media.Tracklist do
  @moduledoc """
  Extracts a setlist from yt-dlp metadata: prefers the structured `chapters`
  array, falling back to parsing timestamp lines out of the video description
  (`"00:48 Forbidden Society - Addict (VIP) • VISION"`).
  """

  @trackline_re ~r/^\s*(\d{1,2}:\d{2}(?::\d{2})?)\s+(.+?)\s*$/m
  @split_re ~r/\s+[-–—:]\s+/

  @doc "Entries from a decoded yt-dlp -J map. Returns [] when nothing parses."
  def from_ytdlp(info, duration \\ nil) when is_map(info) do
    duration = duration || info["duration"]

    case info["chapters"] do
      chapters when is_list(chapters) and chapters != [] ->
        from_chapters(chapters)

      _ ->
        parse_description(info["description"] || "", duration)
    end
  end

  def from_chapters(chapters) do
    chapters
    |> Enum.with_index(1)
    |> Enum.map(fn {ch, position} ->
      start = round_or_nil(ch["start_time"]) || 0

      entry(position, start, round_or_nil(ch["end_time"]), ch["title"] || "")
    end)
  end

  @doc "Parses `MM:SS label` / `HH:MM:SS label` lines out of free text."
  def parse_description(text, duration \\ nil) do
    matches = Regex.scan(@trackline_re, text)

    entries =
      matches
      |> Enum.with_index(1)
      |> Enum.map(fn {[_, timestamp, label], position} ->
        entry(position, timestamp_to_seconds(timestamp), nil, label)
      end)

    fill_end_seconds(entries, duration)
  end

  defp entry(position, start_seconds, end_seconds, label) do
    {artist, title} = split_label(label)

    %{
      "position" => position,
      "start_seconds" => start_seconds,
      "end_seconds" => end_seconds,
      "label" => label,
      "artist" => artist,
      "title" => title
    }
  end

  defp split_label(label) do
    case String.split(label, @split_re, parts: 2) do
      [artist, title] -> {String.trim(artist), String.trim(title)}
      _ -> {nil, label}
    end
  end

  defp fill_end_seconds(entries, duration) do
    next_starts = entries |> Enum.drop(1) |> Enum.map(& &1["start_seconds"])

    entries
    |> Enum.zip(next_starts ++ [round_or_nil(duration)])
    |> Enum.map(fn {entry, next} -> %{entry | "end_seconds" => next} end)
  end

  def timestamp_to_seconds(timestamp) do
    timestamp
    |> String.split(":")
    |> Enum.map(&String.to_integer/1)
    |> Enum.reduce(0, fn part, acc -> acc * 60 + part end)
  end

  defp round_or_nil(nil), do: nil
  defp round_or_nil(n) when is_number(n), do: round(n)
end
