defmodule Kino.Media.YtDlp.Cli do
  @behaviour Kino.Media.YtDlp

  require Logger

  alias Kino.Media.Tracklist

  @format "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
  @metadata_timeout :timer.seconds(60)
  @download_timeout :timer.minutes(15)

  @progress_re ~r/\[download\]\s+(\d+(?:\.\d+)?)%(?:.*?at\s+(\S+))?(?:.*?ETA\s+(\S+))?/

  @impl true
  def fetch_stream_info(url) do
    case run(["-J", "--no-playlist", url], [stderr_to_stdout: false], @metadata_timeout) do
      {:ok, {json, 0}} ->
        case Jason.decode(json) do
          {:ok, info} ->
            {:ok,
             %{
               id: info["id"],
               title: info["title"] || url,
               duration: round_duration(info["duration"]),
               stream_url: progressive_stream_url(info),
               chapters: Tracklist.from_ytdlp(info),
               description: info["description"]
             }}

          {:error, _} ->
            {:error, "yt-dlp returned invalid JSON"}
        end

      {:ok, {output, _code}} ->
        {:error, error_tail(output)}

      {:error, :timeout} ->
        {:error, "metadata fetch timed out after #{div(@metadata_timeout, 1000)}s"}
    end
  end

  # Best single-file (audio+video) direct-download mp4 ≤720p — playable
  # immediately in a <video> tag while the full-quality download runs.
  # Protocol must be plain http(s): YouTube's better combined formats are HLS
  # manifests, which a native <video> can't play (would need hls.js).
  defp progressive_stream_url(info) do
    (info["formats"] || [])
    |> Enum.filter(fn f ->
      f["vcodec"] not in [nil, "none"] and f["acodec"] not in [nil, "none"] and
        f["ext"] == "mp4" and is_binary(f["url"]) and (f["height"] || 0) <= 720 and
        f["protocol"] in ["https", "http"]
    end)
    |> Enum.max_by(& &1["height"], fn -> nil end)
    |> case do
      %{"url" => url} -> url
      nil -> nil
    end
  end

  @impl true
  def download(url, dest_path, opts \\ []) do
    # Download to a temp name and rename so retries never see partial files.
    tmp_path = dest_path <> ".part.mp4"
    File.mkdir_p!(Path.dirname(dest_path))

    args = [
      "-f",
      @format,
      "--no-playlist",
      "--merge-output-format",
      "mp4",
      "--newline",
      "--progress",
      "-o",
      tmp_path,
      url
    ]

    case run_streaming(args, Keyword.get(opts, :progress), @download_timeout) do
      {:ok, {_, 0}} ->
        File.rename!(tmp_path, dest_path)
        :ok

      {:ok, {output, _code}} ->
        File.rm(tmp_path)
        {:error, error_tail(output)}

      {:error, :timeout} ->
        File.rm(tmp_path)
        {:error, "download timed out after #{div(@download_timeout, 60_000)}min"}
    end
  end

  defp run(args, opts, timeout) do
    task = Task.async(fn -> System.cmd(bin(), args, opts) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, code} = result} ->
        if code != 0, do: Logger.warning("yt-dlp exited #{code}: #{output}")
        {:ok, result}

      nil ->
        Logger.warning("yt-dlp timed out after #{timeout}ms: #{bin()} #{Enum.join(args, " ")}")
        {:error, :timeout}
    end
  end

  # Port-based runner so we can surface yt-dlp's per-line download progress.
  defp run_streaming(args, progress_fun, timeout) do
    exe = System.find_executable(bin()) || raise "yt-dlp binary not found: #{bin()}"

    port =
      Port.open({:spawn_executable, exe}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        args: args
      ])

    deadline = System.monotonic_time(:millisecond) + timeout

    case collect(port, deadline, progress_fun, []) do
      {:exit, code, output} ->
        if code != 0, do: Logger.warning("yt-dlp exited #{code}: #{output}")
        {:ok, {output, code}}

      {:timeout, _output} ->
        Logger.warning("yt-dlp timed out after #{timeout}ms: #{bin()} #{Enum.join(args, " ")}")
        {:error, :timeout}
    end
  end

  defp collect(port, deadline, progress_fun, acc) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, {:eol, line}}} ->
        report_progress(line, progress_fun)
        collect(port, deadline, progress_fun, [line | acc])

      {^port, {:data, {:noeol, chunk}}} ->
        collect(port, deadline, progress_fun, [chunk | acc])

      {^port, {:exit_status, code}} ->
        {:exit, code, acc |> Enum.reverse() |> Enum.join("\n")}
    after
      remaining ->
        # Closing the port breaks yt-dlp's stdout pipe; it exits on next write.
        catch_port_close(port)
        {:timeout, acc |> Enum.reverse() |> Enum.join("\n")}
    end
  end

  defp catch_port_close(port) do
    Port.close(port)
  catch
    _, _ -> :ok
  end

  defp report_progress(_line, nil), do: :ok

  defp report_progress(line, fun) do
    case Regex.run(@progress_re, line) do
      [_, percent | rest] ->
        {percent, _} = Float.parse(percent)
        fun.(%{percent: percent, speed: Enum.at(rest, 0), eta: Enum.at(rest, 1)})

      _ ->
        :ok
    end
  end

  defp bin, do: Application.fetch_env!(:kino, :media)[:ytdlp_bin] || "yt-dlp"

  defp round_duration(nil), do: nil
  defp round_duration(seconds) when is_number(seconds), do: round(seconds)

  defp error_tail(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.take(-3)
    |> Enum.join(" | ")
    |> String.slice(0, 500)
  end
end
