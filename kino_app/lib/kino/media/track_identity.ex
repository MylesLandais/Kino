defmodule Kino.Media.TrackIdentity do
  @moduledoc "Normalize setlist labels into Maya-compatible track identity fields."

  @version_re ~r/\((?<name>[^)]*?\b(?:remix|mix|vip|edit|version|dub|bootleg|rework)\b[^)]*)\)/iu

  def from_entry(entry) do
    artist = clean(entry["artist"])
    raw_title = clean(entry["title"] || entry["label"])
    {title_part, label_name} = split_label(raw_title)
    {base_title, remix_name, version_type} = split_version(title_part)

    %{
      artist: artist,
      title: title_part,
      base_title: base_title,
      remix_name: remix_name,
      version_type: version_type,
      label_name: label_name,
      resolvable?: is_binary(artist) and artist != "" and base_title != ""
    }
  end

  def fingerprint(identity) do
    [
      identity.artist,
      identity.base_title,
      identity.remix_name || "",
      identity.version_type || "original"
    ]
    |> Enum.map(&normalize/1)
    |> Enum.join("::")
  end

  def work_key(identity), do: "fp:" <> fingerprint(identity)

  defp split_label(title) do
    case String.split(title, ~r/\s+•\s+/u, parts: 2) do
      [name, label] -> {String.trim(name), String.trim(label)}
      [name] -> {String.trim(name), nil}
    end
  end

  defp split_version(title) do
    case Regex.named_captures(@version_re, title) do
      %{"name" => name} ->
        base = title |> String.replace(@version_re, "") |> String.trim()
        {base, String.trim(name), version_type(name)}

      _ ->
        {title, nil, nil}
    end
  end

  defp version_type(value) do
    value = String.downcase(value)

    cond do
      String.contains?(value, "vip") -> "vip"
      String.contains?(value, "remix") -> "remix"
      String.contains?(value, "edit") -> "edit"
      String.contains?(value, "dub") -> "dub"
      String.contains?(value, "bootleg") -> "bootleg"
      String.contains?(value, "rework") -> "rework"
      true -> "version"
    end
  end

  defp clean(nil), do: nil
  defp clean(value), do: value |> String.trim() |> blank_to_nil()
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp normalize(nil), do: ""

  defp normalize(value) do
    value
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
    |> String.trim("-")
  end
end
