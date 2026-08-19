defmodule Kino.Adaptation.Supervisor do
  @moduledoc """
  Kino-named supervision for the Adaptation / Agent Process layers.

  `Kino.Adaptation.Registry` + `Kino.Adaptation.AgentSupervisor` sit next to
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
      {Registry, keys: :unique, name: Kino.Adaptation.Registry},
      {DynamicSupervisor, name: Kino.Adaptation.AgentSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
