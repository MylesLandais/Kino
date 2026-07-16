defmodule KinoWeb.AvatarAssetController do
  use KinoWeb, :controller

  def show(conn, %{"id" => id}) do
    asset = Kino.Avatar.get_asset!(id)

    case Kino.Media.Storage.impl().public_url(asset.object_key) do
      {:ok, url} ->
        redirect(conn, external: url)

      _ ->
        send_download(conn, {:file, Kino.Avatar.local_path(asset)},
          filename: Path.basename(asset.object_key),
          disposition: :inline,
          content_type: asset.mime_type
        )
    end
  end
end
