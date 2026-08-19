defmodule KinoWeb.AgentChannel do
  @moduledoc """
  `/agent` websocket channel for the Tint/React theater workbench.

  Owns chat, playback observation, setlist interactions, and channel mode
  negotiation for connected clients.
  """

  use KinoWeb, :channel

  alias Kino.Avatar
  alias Kino.Media
  alias Kino.Media.SetBroker
  alias Kino.Theater.{ChatCommands, ListenAudit, RoomSession, Snapshot}

  @channel_modes ~w(chat-only live-audio live-video)

  def join("agent:lobby", _payload, socket) do
    user = socket.assigns.current_user
    Phoenix.PubSub.subscribe(Kino.PubSub, Media.topic())
    send(self(), :after_join)

    socket =
      assign(socket,
        listen_audit: nil,
        channel_mode: "chat-only",
        expanded_track_links: MapSet.new()
      )

    {:ok, join_payload(user), socket}
  end

  def handle_in("command_hint", %{"text" => text}, socket) when is_binary(text) do
    {:reply, {:ok, %{hint: ChatCommands.command_hint(text)}}, socket}
  end

  def handle_in("chat_send", %{"text" => text}, socket) when is_binary(text) do
    user = socket.assigns.current_user
    text = String.trim(text)

    if text == "" do
      {:reply, {:ok, %{status: "noop"}}, socket}
    else
      case ChatCommands.execute(text, user) do
        :ok ->
          {:reply, {:ok, %{status: "ok"}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: inspect(reason)}}, push_agent_error(socket, reason)}

        :noop ->
          {:reply, {:ok, %{status: "noop"}}, socket}
      end
    end
  end

  def handle_in("playback_intent", %{"desired" => desired}, socket)
      when desired in ~w(playing paused) do
    RoomSession.set_desired(String.to_existing_atom(desired))
    {:reply, {:ok, %{status: "ok"}}, socket}
  end

  def handle_in("observed_playback", params, socket) when is_map(params) do
    state = params["state"]

    if state in ~w(playing paused buffering error) do
      RoomSession.report_observed(String.to_existing_atom(state), number(params["position"]))
    end

    playback = RoomSession.current()

    audit =
      if playback.media_id do
        previous = socket.assigns.listen_audit
        payload = Map.from_struct(playback)

        if previous do
          ListenAudit.advance(previous, payload, params, user(socket).username)
        else
          ListenAudit.advance(
            ListenAudit.new(
              listener_id(params),
              playback.playback_session_id,
              number(params["position"]),
              params["state"]
            ),
            payload,
            params,
            user(socket).username
          )
        end
      else
        socket.assigns.listen_audit
      end

    {:reply, {:ok, %{status: "ok"}}, assign(socket, :listen_audit, audit)}
  end

  def handle_in("toggle_like", %{"position" => position}, socket) do
    playback = RoomSession.current()

    if media_id = playback.media_id do
      Media.toggle_reaction(media_id, String.to_integer(position), user(socket).username)
    end

    {:reply, {:ok, %{status: "ok"}}, socket}
  end

  def handle_in("avatar_profile_request", _params, socket) do
    {:reply, {:ok, Avatar.profile_payload()}, socket}
  end

  def handle_in("set_channel_mode", %{"mode" => mode}, socket) when mode in @channel_modes do
    socket = assign(socket, :channel_mode, mode)

    push(socket, "channel_mode_changed", %{
      mode: mode,
      capabilities: Snapshot.capabilities()
    })

    {:reply, {:ok, %{mode: mode}}, socket}
  end

  def handle_in("negotiate_capabilities", %{"requested" => requested}, socket)
      when is_list(requested) do
    granted = Enum.filter(requested, &(&1 in Snapshot.capabilities()))

    {:reply,
     {:ok,
      %{
        granted: granted,
        mode: socket.assigns.channel_mode,
        capabilities: Snapshot.capabilities()
      }}, socket}
  end

  def handle_in("negotiate_capabilities", _params, socket) do
    {:reply,
     {:ok,
      %{
        granted: Snapshot.capabilities(),
        mode: socket.assigns.channel_mode,
        capabilities: Snapshot.capabilities()
      }}, socket}
  end

  def handle_info({:chat_message, msg}, socket) do
    push(socket, "chat_message", %{msg: msg})
    {:noreply, socket}
  end

  def handle_info({:agent_event, %{state: state, text: text, payload: payload}}, socket) do
    push(socket, "agent_event", %{state: state, text: text, payload: payload})
    {:noreply, socket}
  end

  def handle_info({:pipeline_progress, progress}, socket) do
    push(socket, "pipeline_progress", %{progress: progress})
    {:noreply, socket}
  end

  def handle_info({:playback_updated, state}, socket) do
    push(socket, "playback_updated", %{playback: Snapshot.playback_payload(state)})
    {:noreply, assign(socket, :listen_audit, nil)}
  end

  def handle_info({:reactions_updated, asset_id}, socket) do
    playback = RoomSession.current()

    if playback.media_id == asset_id do
      push(socket, "theater_patch", %{reactions: Media.reactions_for(asset_id)})
    end

    {:noreply, socket}
  end

  def handle_info({:plays_updated, asset_id}, socket) do
    playback = RoomSession.current()

    if playback.media_id == asset_id do
      asset = Media.get_asset!(asset_id)
      push(socket, "theater_patch", %{play_counts: Media.play_counts_for(asset)})
    end

    {:noreply, socket}
  end

  def handle_info({:set_enrichment_updated, asset_id}, socket) do
    playback = RoomSession.current()

    if playback.media_id == asset_id do
      push(socket, "theater_patch", %{
        set_resolutions: SetBroker.resolutions_for_asset(asset_id)
      })
    end

    {:noreply, socket}
  end

  def handle_info({:avatar_animation, payload}, socket) do
    push(socket, "avatar_animation", payload)
    {:noreply, socket}
  end

  def handle_info({:avatar_profile_updated, _key}, socket) do
    push(socket, "avatar_profile", Avatar.profile_payload())
    {:noreply, socket}
  end

  def handle_info(:after_join, socket) do
    user = user(socket)

    push(socket, "chat_message", %{
      msg: %{
        id: System.unique_integer([:positive]),
        type: :system,
        timestamp: Calendar.strftime(Time.utc_now(), "%H:%M"),
        user: nil,
        text: "kino session started — /play <url> to queue a video",
        state: nil,
        payload: %{}
      }
    })

    push(socket, "theater_snapshot", %{
      snapshot: Snapshot.build(user.username, channel_mode: socket.assigns.channel_mode)
    })

    push(socket, "avatar_profile", Avatar.profile_payload())

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp join_payload(user) do
    %{
      username: user.username,
      capabilities: Snapshot.capabilities(),
      channel_mode: "chat-only"
    }
  end

  defp push_agent_error(socket, reason) do
    Media.broadcast_agent(:error, "Could not process message — #{inspect(reason)}")
    socket
  end

  defp user(socket), do: socket.assigns.current_user

  defp listener_id(%{"listener_id" => id}) when is_binary(id), do: id
  defp listener_id(_), do: "anonymous"

  defp number(value) when is_number(value), do: value * 1.0

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> 0.0
    end
  end

  defp number(_), do: 0.0
end
