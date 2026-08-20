defmodule Kino.Theater.ChatCommands do
  @moduledoc """
  Shared theater command dispatch for LiveView and `/agent` channel clients.
  """

  alias Kino.Media
  alias Kino.Media.LinkResolver
  alias Kino.Media.SetBroker
  alias Kino.Theater.RoomSession

  @spec execute(String.t(), Kino.Accounts.User.t()) :: :ok | {:error, term()} | :noop
  def execute(text, user) when is_binary(text) do
    text = String.trim(text)

    cond do
      text == "" ->
        :noop

      String.starts_with?(text, "/play ") ->
        url = text |> String.trim_leading("/play ") |> String.trim()
        broadcast_user_message(user.username, text)

        case Media.request_play(url, user.username) do
          {:ok, _asset} -> :ok
          {:error, reason} -> {:error, reason}
        end

      String.starts_with?(text, "/wish ") ->
        query = text |> String.trim_leading("/wish ") |> String.trim()
        broadcast_user_message(user.username, text)

        case LinkResolver.parse_query(query) do
          {:ok, recording} ->
            Media.broadcast_agent(:working, "Searching seven music platforms…", %{
              artist: recording.artist,
              title: recording.title,
              threshold: "80%"
            })

            Task.Supervisor.start_child(Kino.TaskSupervisor, fn -> resolve_wish(query) end)
            :ok

          {:error, reason} ->
            Media.broadcast_agent(:error, reason)
            {:error, reason}
        end

      text == "/pause" ->
        RoomSession.set_desired(:paused)
        :ok

      text == "/resume" ->
        RoomSession.set_desired(:playing)
        :ok

      true ->
        broadcast_user_message(user.username, text)
        maybe_trigger_avatar(user, text)
        :ok
    end
  end

  @spec command_hint(String.t()) :: String.t() | nil
  def command_hint(text) when is_binary(text) do
    cond do
      String.starts_with?(text, "/play") -> "/play <video-url> — fetch and cache with yt-dlp"
      String.starts_with?(text, "/wish") -> "/wish Artist — Track — resolve ≥80% platform links"
      String.starts_with?(text, "/") -> "command: #{text}"
      true -> nil
    end
  end

  defp broadcast_user_message(username, text) do
    Media.broadcast(
      {:chat_message,
       %{
         id: System.unique_integer([:positive]),
         type: :user,
         timestamp: Calendar.strftime(Time.utc_now(), "%H:%M"),
         user: username,
         text: text,
         state: nil,
         payload: %{}
       }}
    )
  end

  defp maybe_trigger_avatar(user, text) do
    if Kino.Accounts.allowed?(user, "avatar:trigger") do
      if asset = Kino.Avatar.match_motion(text), do: Kino.Avatar.trigger(asset)
    end
  end

  defp resolve_wish(query) do
    case SetBroker.resolve_query(query) do
      {:ok, %{recording: recording, matches: []}} ->
        Media.broadcast_agent(
          :error,
          "No platform returned an 80% match for #{recording.artist} — #{recording.title}."
        )

      {:ok, %{recording: recording, matches: matches}} ->
        links =
          matches
          |> Enum.sort_by(&to_string(&1.platform))
          |> Enum.map_join("\n", fn match ->
            confidence = round(match.confidence * 100)
            "#{platform_label(match.platform)} #{confidence}% — #{match.url}"
          end)

        Media.broadcast_agent(
          :success,
          "Links for #{recording.artist} — #{recording.title}:\n#{links}",
          %{matched: length(matches), checked: length(LinkResolver.providers())}
        )

      {:error, reason} ->
        Media.broadcast_agent(:error, reason)
    end
  rescue
    error -> Media.broadcast_agent(:error, "Platform lookup failed — #{Exception.message(error)}")
  end

  defp platform_label(platform) do
    platform
    |> to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end
end
