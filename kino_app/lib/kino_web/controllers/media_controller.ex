defmodule KinoWeb.MediaController do
  use KinoWeb, :controller

  alias Kino.Media

  # Plug does not implement HTTP Range handling; <video> seeking needs 206s.
  def show(conn, %{"cache_key" => cache_key}) do
    with %{status: "ready"} = asset <- Media.get_asset_by_cache_key(cache_key) do
      serve_asset(conn, asset)
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end

  defp serve_asset(conn, %{file_path: path} = asset) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> serve_local(conn, path, size)
      _ -> serve_object(conn, asset)
    end
  end

  defp serve_asset(conn, asset), do: serve_object(conn, asset)

  defp serve_local(conn, path, size) do
    conn =
      conn
      |> put_resp_content_type("video/mp4")
      |> put_resp_header("accept-ranges", "bytes")

    case get_req_header(conn, "range") do
      ["bytes=" <> range] -> send_range(conn, path, size, range)
      _ -> send_file(conn, 200, path)
    end
  end

  defp serve_object(conn, %{object_key: key}) when is_binary(key) do
    case Kino.Media.Storage.impl().public_url(key) do
      {:ok, url} -> redirect(conn, external: url)
      _ -> send_resp(conn, 404, "not found")
    end
  end

  defp serve_object(conn, _asset), do: send_resp(conn, 404, "not found")

  defp send_range(conn, path, size, range) do
    case parse_range(range, size) do
      {first, last} when first < size ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      _ ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
    end
  end

  # Supports "N-", "N-M", and suffix "-N" forms; clamps end to size-1.
  defp parse_range(range, size) do
    case String.split(range, "-", parts: 2) do
      ["", suffix] ->
        case Integer.parse(suffix) do
          {n, ""} when n > 0 -> {max(size - n, 0), size - 1}
          _ -> :invalid
        end

      [first, ""] ->
        case Integer.parse(first) do
          {n, ""} -> {n, size - 1}
          _ -> :invalid
        end

      [first, last] ->
        with {f, ""} <- Integer.parse(first),
             {l, ""} <- Integer.parse(last) do
          {f, min(l, size - 1)}
        else
          _ -> :invalid
        end

      _ ->
        :invalid
    end
  end
end
