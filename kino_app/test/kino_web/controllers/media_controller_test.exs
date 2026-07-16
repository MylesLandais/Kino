defmodule KinoWeb.MediaControllerTest do
  use KinoWeb.ConnCase, async: false

  alias Kino.Media.MediaAsset
  alias Kino.Repo

  @body "0123456789abcdef"

  setup do
    path = Path.join(System.tmp_dir!(), "kino_media_controller_test.mp4")
    File.write!(path, @body)
    on_exit(fn -> File.rm(path) end)

    {:ok, asset} =
      %MediaAsset{}
      |> MediaAsset.changeset(%{
        source_url: "https://example.com/v",
        cache_key: "testkey123",
        status: "ready",
        file_path: path
      })
      |> Repo.insert()

    %{asset: asset}
  end

  test "serves the full file without a Range header", %{conn: conn, asset: asset} do
    conn = get(conn, ~p"/media/#{asset.cache_key}")
    assert conn.status == 200
    assert conn.resp_body == @body
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
  end

  test "serves a byte range with 206 and content-range", %{conn: conn, asset: asset} do
    conn =
      conn
      |> put_req_header("range", "bytes=2-5")
      |> get(~p"/media/#{asset.cache_key}")

    assert conn.status == 206
    assert conn.resp_body == "2345"
    assert get_resp_header(conn, "content-range") == ["bytes 2-5/16"]
  end

  test "open-ended range is clamped to file size", %{conn: conn, asset: asset} do
    conn =
      conn
      |> put_req_header("range", "bytes=10-")
      |> get(~p"/media/#{asset.cache_key}")

    assert conn.status == 206
    assert conn.resp_body == "abcdef"
    assert get_resp_header(conn, "content-range") == ["bytes 10-15/16"]
  end

  test "out-of-range request returns 416", %{conn: conn, asset: asset} do
    conn =
      conn
      |> put_req_header("range", "bytes=99999-")
      |> get(~p"/media/#{asset.cache_key}")

    assert conn.status == 416
    assert get_resp_header(conn, "content-range") == ["bytes */16"]
  end

  test "unknown cache key returns 404", %{conn: conn} do
    assert conn |> get(~p"/media/nope") |> Map.fetch!(:status) == 404
  end

  test "redirects to a signed durable object when the hot cache is absent", %{
    conn: conn,
    asset: asset
  } do
    media_config = Application.fetch_env!(:kino, :media)

    Application.put_env(
      :kino,
      :media,
      Keyword.put(media_config, :storage, Kino.Media.StorageStub)
    )

    on_exit(fn -> Application.put_env(:kino, :media, media_config) end)

    File.rm!(asset.file_path)

    asset
    |> MediaAsset.changeset(%{object_key: "kino/media/#{asset.cache_key}.mp4"})
    |> Repo.update!()

    conn = get(conn, ~p"/media/#{asset.cache_key}")
    assert conn.status == 302

    assert get_resp_header(conn, "location") == [
             "https://objects.example/media/kino/media/#{asset.cache_key}.mp4?signed=1"
           ]
  end
end
