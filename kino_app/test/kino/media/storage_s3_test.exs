defmodule Kino.Media.StorageS3Test do
  use ExUnit.Case, async: false

  alias Kino.Media.Storage.S3

  setup do
    media = Application.fetch_env!(:kino, :media)
    access_key = System.get_env("AWS_ACCESS_KEY_ID")
    secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")

    Application.put_env(
      :kino,
      :media,
      media
      |> Keyword.put(:storage_bucket, "media")
      |> Keyword.put(:s3_public_endpoint, "https://objects.example")
      |> Keyword.put(:s3_region, "us-east-1")
    )

    System.put_env("AWS_ACCESS_KEY_ID", "test-access")
    System.put_env("AWS_SECRET_ACCESS_KEY", "test-secret")

    on_exit(fn ->
      Application.put_env(:kino, :media, media)
      restore_env("AWS_ACCESS_KEY_ID", access_key)
      restore_env("AWS_SECRET_ACCESS_KEY", secret_key)
    end)
  end

  test "generates a short-lived signed object URL" do
    assert {:ok, url} = S3.public_url("kino/media/example.mp4")
    assert URI.parse(url).host == "objects.example"
    assert url =~ "X-Amz-Signature="
    assert url =~ "X-Amz-Expires=900"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
