defmodule Harness.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Harness.Registry},
      {DynamicSupervisor, name: Harness.Runtime.Supervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Harness.Supervisor)
  end
end
