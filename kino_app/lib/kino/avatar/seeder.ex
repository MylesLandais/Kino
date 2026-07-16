defmodule Kino.Avatar.Seeder do
  use GenServer

  require Logger

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    case Kino.Avatar.Bootstrap.import_if_empty(Application.get_env(:kino, :avatar_bootstrap_dir)) do
      {:error, reason} -> Logger.warning("Kino avatar bootstrap unavailable: #{inspect(reason)}")
      _ -> :ok
    end

    :ignore
  end
end
