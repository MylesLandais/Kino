defmodule Kino.Theater.RoomSession do
  @moduledoc """
  Holds the room's current playback state (desired vs observed) and
  broadcasts `{:playback_updated, state}` on the room topic.

  A video can play from two sources: `:stream` (direct progressive URL from
  yt-dlp, starts near-instantly) and `:cache` (the downloaded file served at
  /media/<cache_key>). `play_stream/3` starts the former; `play/2` swaps to
  the cache when the download completes, preserving position.
  """

  use GenServer

  defstruct media_id: nil,
            title: nil,
            provider: nil,
            cache_key: nil,
            requested_by: nil,
            duration_seconds: nil,
            chapters: [],
            source: nil,
            src: nil,
            revision: 0,
            desired: :idle,
            observed: :idle,
            position: 0.0,
            playback_session_id: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  def current(server \\ __MODULE__), do: GenServer.call(server, :current)

  @doc "Start playing the cached file (or swap to it if the same media is streaming)."
  def play(asset, requested_by, server \\ __MODULE__) do
    GenServer.cast(server, {:play, asset, requested_by, :cache, "/media/#{asset.cache_key}"})
  end

  @doc "Start playing a direct stream URL immediately, before the cache is ready."
  def play_stream(asset, stream_url, requested_by, server \\ __MODULE__) do
    GenServer.cast(server, {:play, asset, requested_by, :stream, stream_url})
  end

  @doc "Replace the current stream with its durable cached source without starting a new play session."
  def promote_to_cache(asset, requested_by, server \\ __MODULE__) do
    GenServer.cast(server, {:promote, asset, requested_by, :cache, "/media/#{asset.cache_key}"})
  end

  def set_desired(desired, server \\ __MODULE__) when desired in [:playing, :paused] do
    GenServer.cast(server, {:set_desired, desired})
  end

  def report_observed(observed, position, server \\ __MODULE__) do
    GenServer.cast(server, {:observed, observed, position})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast({:play, asset, requested_by, source, src}, state) do
    {:noreply, asset_state(asset, requested_by, source, src, state, false) |> broadcast()}
  end

  def handle_cast({:promote, asset, requested_by, source, src}, state) do
    preserve? = state.media_id == asset.id and state.media_id != nil
    {:noreply, asset_state(asset, requested_by, source, src, state, preserve?) |> broadcast()}
  end

  def handle_cast({:set_desired, _desired}, %{media_id: nil} = state), do: {:noreply, state}

  def handle_cast({:set_desired, desired}, %{desired: desired} = state), do: {:noreply, state}

  def handle_cast({:set_desired, desired}, state) do
    {:noreply, broadcast(%{state | desired: desired})}
  end

  def handle_cast({:observed, observed, position}, state) do
    {:noreply, broadcast(%{state | observed: observed, position: position})}
  end

  defp asset_state(asset, requested_by, source, src, state, preserve?) do
    %__MODULE__{
      media_id: asset.id,
      title: asset.title,
      provider: asset.provider,
      cache_key: asset.cache_key,
      requested_by: requested_by,
      duration_seconds: asset.duration_seconds,
      chapters: Map.get(asset, :chapters) || [],
      source: source,
      src: src,
      revision: state.revision + 1,
      desired: if(preserve?, do: state.desired, else: :playing),
      observed: :buffering,
      position: if(preserve?, do: state.position, else: 0.0),
      playback_session_id:
        if(preserve?, do: state.playback_session_id, else: Ecto.UUID.generate())
    }
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Kino.PubSub, Kino.Media.topic(), {:playback_updated, state})
    state
  end
end
