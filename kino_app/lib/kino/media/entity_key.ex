defmodule Kino.Media.EntityKey do
  @moduledoc "Canonical music ontology keys shared with maya-unified."

  def recording(url) do
    uri = URI.parse(url)
    host = (uri.host || "") |> String.downcase() |> String.replace_prefix("www.", "")

    cond do
      host == "youtu.be" and uri.path not in [nil, "", "/"] ->
        "yt:" <> (uri.path |> String.trim("/") |> String.split("/") |> hd())

      host in ["youtube.com", "m.youtube.com", "music.youtube.com"] ->
        case URI.decode_query(uri.query || "")["v"] do
          id when is_binary(id) and id != "" -> "yt:" <> id
          _ -> generic(host, uri.path)
        end

      true ->
        generic(host, uri.path)
    end
  end

  def set_entry(set_key, position), do: "#{set_key}:#{position}"

  def uuid(key) do
    hex =
      :crypto.hash(:sha256, key)
      |> binary_part(0, 16)
      |> Base.encode16(case: :lower)

    <<a::binary-size(8), b::binary-size(4), _::binary-size(4), variant::binary-size(4),
      e::binary>> =
      hex

    version = "5" <> binary_part(hex, 13, 3)

    variant =
      variant
      |> binary_part(0, 1)
      |> String.to_integer(16)
      |> Bitwise.band(0x3)
      |> Bitwise.bor(0x8)
      |> Integer.to_string(16)
      |> Kernel.<>(binary_part(variant, 1, 3))

    "#{a}-#{b}-#{version}-#{variant}-#{e}"
  end

  defp generic(host, path) do
    path = String.trim(path || "", "/")
    "url:#{host}/#{if(path == "", do: "root", else: path)}" |> String.slice(0, 255)
  end
end
