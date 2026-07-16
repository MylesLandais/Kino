defmodule Kino.Media.StorageFail do
  @behaviour Kino.Media.Storage

  @impl true
  def put_file(_key, _path), do: {:error, :unavailable}

  @impl true
  def exists?(_key), do: false

  @impl true
  def public_url(_key), do: {:error, :unavailable}

  @impl true
  def delete(_key), do: :ok
end
