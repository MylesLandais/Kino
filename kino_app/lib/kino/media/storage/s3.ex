defmodule Kino.Media.Storage.S3 do
  @moduledoc "S3-compatible durable media storage backed by ReqS3."
  @behaviour Kino.Media.Storage

  @impl true
  def put_file(key, source) do
    size = File.stat!(source).size

    response =
      Req.new()
      |> ReqS3.attach(aws_sigv4: credentials(), aws_endpoint_url_s3: endpoint())
      |> Req.put(
        url: s3_url(key),
        headers: [{"content-length", Integer.to_string(size)}],
        body: File.stream!(source, [], 1_048_576)
      )

    case response do
      {:ok, %{status: status, headers: headers}} when status in 200..299 ->
        {:ok, %{etag: header(headers, "etag")}}

      {:ok, response} ->
        {:error, {:s3_status, response.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def exists?(key) do
    case Req.new()
         |> ReqS3.attach(aws_sigv4: credentials(), aws_endpoint_url_s3: endpoint())
         |> Req.head(url: s3_url(key)) do
      {:ok, %{status: status}} when status in 200..299 -> true
      _ -> false
    end
  end

  @impl true
  def public_url(key) do
    media = Application.fetch_env!(:kino, :media)

    options =
      [
        bucket: media[:storage_bucket],
        key: key,
        endpoint_url: media[:s3_public_endpoint],
        region: media[:s3_region] || "us-east-1",
        expires: 900
      ] ++ credentials()

    {:ok, ReqS3.presign_url(options)}
  rescue
    error -> {:error, error}
  end

  @impl true
  def delete(key) do
    case Req.new()
         |> ReqS3.attach(aws_sigv4: credentials(), aws_endpoint_url_s3: endpoint())
         |> Req.delete(url: s3_url(key)) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, response} -> {:error, {:s3_status, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp s3_url(key) do
    bucket = Application.fetch_env!(:kino, :media)[:storage_bucket]
    "s3://#{bucket}/#{key}"
  end

  defp credentials do
    [
      access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
      region: Application.fetch_env!(:kino, :media)[:s3_region] || "us-east-1"
    ]
  end

  defp endpoint, do: Application.fetch_env!(:kino, :media)[:s3_endpoint]

  defp header(headers, name) do
    case headers[name] do
      [value | _] -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end
end
