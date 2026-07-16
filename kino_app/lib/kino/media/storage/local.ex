defmodule Kino.Media.Storage.Local do
  @moduledoc "Local hot-cache storage used in development and tests."
  @behaviour Kino.Media.Storage

  @impl true
  def put_file(key, source) do
    destination = Path.join(Kino.Media.cache_dir(), key)
    File.mkdir_p!(Path.dirname(destination))

    if Path.expand(source) != Path.expand(destination) do
      File.cp!(source, destination)
    end

    {:ok, %{etag: digest(destination)}}
  end

  @impl true
  def exists?(key), do: File.exists?(Path.join(Kino.Media.cache_dir(), key))

  @impl true
  def public_url(_key), do: {:error, :local_only}

  @impl true
  def delete(key) do
    case File.rm(Path.join(Kino.Media.cache_dir(), key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  defp digest(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end
end
