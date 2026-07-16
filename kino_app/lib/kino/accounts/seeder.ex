defmodule Kino.Accounts.Seeder do
  use GenServer
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  @impl true
  def init(:ok) do
    Kino.Accounts.ensure_rbac!()
    bootstrap_configured_admin()
    :ignore
  end

  defp bootstrap_configured_admin do
    config =
      case Application.get_env(:kino, :bootstrap_admin) do
        values when is_list(values) -> Map.new(values)
        values -> values
      end

    case config do
      %{username: username, password: password} = config
      when is_binary(username) and is_binary(password) ->
        if Kino.Accounts.bootstrap_required?() do
          attrs = %{
            "username" => username,
            "email" => Map.get(config, :email, "#{username}@kino.local"),
            "display_name" => Map.get(config, :display_name, "Kino Admin"),
            "password" => password
          }

          case Kino.Accounts.bootstrap_admin(attrs, %{source: "configured_bootstrap"}) do
            {:ok, _user} ->
              :ok

            {:error, :already_bootstrapped} ->
              :ok

            {:error, reason} ->
              raise "could not bootstrap configured Kino admin: #{inspect(reason)}"
          end
        end

      _ ->
        :ok
    end
  end
end
