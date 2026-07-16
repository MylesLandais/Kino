defmodule Kino.Media.YtDlp do
  @moduledoc "Behaviour for yt-dlp access so tests can stub the subprocess."

  @type stream_info :: %{
          id: String.t() | nil,
          title: String.t(),
          duration: integer() | nil,
          stream_url: String.t() | nil,
          chapters: [map()],
          description: String.t() | nil
        }

  @doc """
  Single -J probe: metadata plus a direct progressive stream URL (for instant
  playback) and the parsed chapter/tracklist entries.
  """
  @callback fetch_stream_info(url :: String.t()) :: {:ok, stream_info()} | {:error, String.t()}

  @doc "Download to dest_path. opts: `progress: fun(%{percent, speed, eta})`."
  @callback download(url :: String.t(), dest_path :: String.t(), opts :: keyword()) ::
              :ok | {:error, String.t()}

  def impl do
    Application.fetch_env!(:kino, :media)[:ytdlp] || Kino.Media.YtDlp.Cli
  end
end
