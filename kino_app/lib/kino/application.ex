defmodule Kino.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KinoWeb.Telemetry,
      Kino.Repo,
      Kino.Accounts.Seeder,
      {DNSCluster, query: Application.get_env(:kino, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Kino.PubSub},
      Kino.Avatar.Seeder,
      {Oban, Application.fetch_env!(:kino, Oban)},
      {Task.Supervisor, name: Kino.TaskSupervisor},
      Kino.Theater.RoomSession,
      KinoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kino.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KinoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
