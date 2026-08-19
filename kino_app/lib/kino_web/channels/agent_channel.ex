defmodule KinoWeb.AgentChannel do
  @moduledoc """
  `/agent` websocket channel for the agent workbench UI.

  This v1 forwards:
  - chat user messages (user-sent)
  - agent events and pipeline progress emitted by `Kino.Media`
  """

  use KinoWeb, :channel

  alias Kino.Media
  alias Kino.Theater.ChatCommands

  def join("agent:lobby", _payload, socket) do
    user = socket.assigns.current_user
    Phoenix.PubSub.subscribe(Kino.PubSub, Media.topic())
    send(self(), :after_join)

    {:ok, %{username: user.username}, socket}
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

  def handle_info(:after_join, socket) do
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

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- internal

  defp push_agent_error(socket, reason) do
    Media.broadcast_agent(:error, "Could not process message — #{inspect(reason)}")
    socket
  end
end
