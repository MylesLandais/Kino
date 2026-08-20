defmodule KinoWeb.AgentSocket do
  @moduledoc """
  Phoenix socket for the `/agent` websocket contract.

  This is the transport layer used by the React/Tint “workbench” UI.
  """

  use Phoenix.Socket

  require Logger

  ## Channels
  channel "agent:lobby", KinoWeb.AgentChannel

  @impl true
  def connect(params, socket, connect_info) do
    # Primary auth is encrypted `_kino_key` cookie via `connect_info[:session]`
    # (see `KinoWeb.Endpoint` `socket "/agent"` `connect_info: [session: @session_options]`).
    # Params fallback is for `mix test` channel tests and non-browser clients; browsers
    # must rely on cookie. Do not log token contents.
    session = connect_info[:session] || %{}

    auth_token =
      session["auth_token"] ||
        session[:auth_token] ||
        # Fallback for browser edge cases / non-browser clients: token in query params
        # is visible in URL/logs and DOM (data-auth-token) — prefer cookie-only in future.
        params["auth_token"] ||
        params["token"]

    case Kino.Accounts.user_for_session(auth_token) do
      nil ->
        Logger.debug(
          "AgentSocket refused: token_present=#{not is_nil(auth_token)} session_keys=#{inspect(Map.keys(session))} param_keys=#{inspect(Map.keys(params))}"
        )

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

