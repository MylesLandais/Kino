defmodule KinoWeb.AgentChannel do
  @moduledoc """
  `/agent` websocket channel for the agent workbench UI.

  This v1 forwards:
  - chat user messages (user-sent)
  - agent events and pipeline progress emitted by `Kino.Media`
  """

  use KinoWeb, :channel

  alias Kino.Media
  alias Kino.Media.LinkResolver
  alias Kino.Theater.RoomSession

  def join("agent:lobby", _payload, socket) do
    user = socket.assigns.current_user
    Phoenix.PubSub.subscribe(Kino.PubSub, Media.topic())
    {:ok, %{username: user.username}, socket}
  end

  def handle_in("chat_send", %{"text" => text}, socket) when is_binary(text) do
    user = socket.assigns.current_user
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      socket =
        socket
        |> push_user_message(user.username, text)

      case handle_command(text, user.username) do
        :ok -> {:noreply, socket}
        {:error, reason} -> {:noreply, push_agent_error(socket, user.username, reason)}
      end
    end
  end

  def handle_info({:chat_message, msg}, socket) do
    # msg is already a Kino-theater shape: %{id, type, timestamp, user, text, state, payload}
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

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- internal

  defp push_user_message(socket, username, text) do
    msg =
      %{
        id: System.unique_integer([:positive]),
        type: :user,
        timestamp: Calendar.strftime(Time.utc_now(), "%H:%M"),
        user: username,
        text: text,
        state: nil,
        payload: %{}
      }

    # Broadcast so other clients keep parity with the old LiveView stream.
    Media.broadcast({:chat_message, msg})
    socket
  end

  defp push_agent_error(socket, _username, reason) do
    Media.broadcast_agent(:error, "Could not process message — #{inspect(reason)}")
    socket
  end

  defp handle_command(text, username) do
    cond do
      String.starts_with?(text, "/play ") ->
        url = text |> String.trim_leading("/play ") |> String.trim()

        case Media.request_play(url, username) do
          {:ok, _asset} -> :ok
          {:error, reason} -> {:error, reason}
        end

      text == "/pause" ->
        RoomSession.set_desired(:paused)
        :ok

      text == "/resume" ->
        RoomSession.set_desired(:playing)
        :ok

      String.starts_with?(text, "/wish ") ->
        # v1: We keep wish functionality minimal (no async resolution pipeline yet).
        # Later we can port the full resolve_wish logic from TheaterLive.
        query = text |> String.trim_leading("/wish ") |> String.trim()

        case LinkResolver.parse_query(query) do
          {:ok, _recording} ->
            # kick off the existing wish resolver by simulating the old flow would come later.
            Media.broadcast_agent(:working, "Wish resolver is not fully ported to /agent yet.")
            :ok

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        # Plain chat: for v1 we just send the user message; agent responses will
        # be produced by whatever orchestration owns `Kino.Media.broadcast_agent/3`.
        :ok
    end
  end
end

