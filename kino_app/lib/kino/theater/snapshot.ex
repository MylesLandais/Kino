defmodule Kino.Theater.Snapshot do
  @moduledoc "Builds theater state payloads for `/agent` websocket clients."

  alias Kino.Media
  alias Kino.Media.SetBroker
  alias Kino.Theater.RoomSession

  @capabilities ~w(chat-only live-audio live-video)

  def capabilities, do: @capabilities

  def build(username, opts \\ []) do
    playback = RoomSession.current()
    media_id = playback.media_id

    %{
      username: username,
      capabilities: @capabilities,
      channel_mode: Keyword.get(opts, :channel_mode, "chat-only"),
      playback: playback_payload(playback),
      reactions: if(media_id, do: Media.reactions_for(media_id), else: %{}),
      play_counts:
        if media_id do
          case Media.get_asset(media_id) do
            nil -> %{}
            asset -> Media.play_counts_for(asset)
          end
        else
          %{}
        end,
      set_resolutions: if(media_id, do: SetBroker.resolutions_for_asset(media_id), else: %{})
    }
  end

  def playback_payload(%RoomSession{} = pb) do
    %{
      media_id: pb.media_id,
      title: pb.title,
      provider: pb.provider,
      cache_key: pb.cache_key,
      requested_by: pb.requested_by,
      duration_seconds: pb.duration_seconds,
      chapters: pb.chapters || [],
      source: pb.source && to_string(pb.source),
      src: pb.src,
      revision: pb.revision,
      desired: pb.desired && to_string(pb.desired),
      observed: pb.observed && to_string(pb.observed),
      position: pb.position,
      playback_session_id: pb.playback_session_id,
      markers:
        Enum.map(pb.chapters || [], fn ch ->
          %{time: ch["start_seconds"], label: ch["label"]}
        end)
    }
  end
end
