defmodule KinoWeb.AgentSocket do
  @moduledoc """
  Phoenix socket for the `/agent` websocket contract.

  This is the transport layer used by the React/Tint “workbench” UI.
  """

  use Phoenix.Socket

  ## Channels
  channel "agent:lobby", KinoWeb.AgentChannel

  @impl true
  def connect(_params, socket, connect_info) do
    # Reuse the same cookie-based session logic as LiveView.
    session = connect_info[:session] || %{}
    auth_token = session["auth_token"]

    case Kino.Accounts.user_for_session(auth_token) do
      nil ->
        :error

      user ->
        {:ok,
         assign(socket,
           current_user: user
         )}
    end
  end

  @impl true
  def id(_socket), do: nil
end

