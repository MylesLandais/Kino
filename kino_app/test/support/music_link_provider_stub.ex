defmodule Kino.TestMusicLinkProviderStub do
  @behaviour Kino.Media.LinkProvider

  @impl true
  def search(recording) do
    {:ok,
     [
       %{
         artist: recording.artist,
         title: recording.title,
         external_id: "match-1",
         url: "https://music.example/track/match-1"
       }
     ]}
  end

  @impl true
  def search(_recording, :low) do
    {:ok,
     [
       %{
         artist: "Unrelated Artist",
         title: "Different Song",
         external_id: "wrong-1",
         url: "https://low.example/wrong-1"
       }
     ]}
  end
end
