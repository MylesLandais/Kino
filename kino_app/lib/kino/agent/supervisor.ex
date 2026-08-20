defmodule Kino.Agent.Supervisor do
  @moduledoc """
  `/agent` supervision tree.

  `Kino.Agent.Registry` + `Kino.Agent.DynamicSupervisor` sit next to
  `Kino.TaskSupervisor` / `Kino.Theater.RoomSession`. Training jobs use Oban's
  `adaptation` queue, not this DynamicSupervisor, so a failed train cannot
  take down an agent.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Kino.Agent.Registry},
      {DynamicSupervisor, name: Kino.Agent.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
