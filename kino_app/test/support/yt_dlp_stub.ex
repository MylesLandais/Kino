defmodule Kino.Media.YtDlpStub do
  @moduledoc """
  Test stand-in for yt-dlp. Writes a tiny fake file instead of shelling out.
  Notifies the process registered under `:yt_dlp_stub_listener` (if any) so
  tests can assert whether a download actually ran.
  """

  @behaviour Kino.Media.YtDlp

  @impl true
  def fetch_stream_info("https://fail.example" <> _), do: {:error, "unsupported url"}

  def fetch_stream_info("https://nostream.example" <> _) do
    notify(:fetch_stream_info)
    {:ok, %{base_info() | stream_url: nil}}
  end

  def fetch_stream_info(_url) do
    notify(:fetch_stream_info)
    {:ok, base_info()}
  end

  defp base_info do
    %{
      id: "stub123",
      title: "Stub Video",
      duration: 212,
      stream_url: "https://stream.example/stub720.mp4",
      description: "00:00 Intro\n00:48 FS - Addict",
      chapters: [
        %{
          "position" => 1,
          "start_seconds" => 0,
          "end_seconds" => 48,
          "label" => "Intro",
          "artist" => nil,
          "title" => "Intro"
        },
        %{
          "position" => 2,
          "start_seconds" => 48,
          "end_seconds" => 212,
          "label" => "FS - Addict",
          "artist" => "FS",
          "title" => "Addict"
        }
      ]
    }
  end

  @impl true
  def download(_url, dest_path, opts \\ []) do
    notify(:download)

    if fun = Keyword.get(opts, :progress) do
      fun.(%{percent: 50.0, speed: "8MiB/s", eta: "00:10"})
      fun.(%{percent: 100.0, speed: "8MiB/s", eta: "00:00"})
    end

    File.mkdir_p!(Path.dirname(dest_path))
    File.write!(dest_path, "fake mp4 bytes")
    :ok
  end

  defp notify(event) do
    case Process.whereis(:yt_dlp_stub_listener) do
      nil -> :ok
      pid -> send(pid, {:yt_dlp_stub, event})
    end
  end
end
