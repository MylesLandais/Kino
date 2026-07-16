defmodule Kino.Media.StorageStub do
  @behaviour Kino.Media.Storage

  @impl true
  def put_file(_key, _path), do: {:ok, %{etag: "stub-etag"}}

  @impl true
  def exists?(_key), do: true

  @impl true
  def public_url(key), do: {:ok, "https://objects.example/media/#{key}?signed=1"}

  @impl true
  def delete(_key), do: :ok
end
