defmodule Adaptation do
  @moduledoc """
  Adaptation Substrate facade.

  Trajectories are consumed here only. Live agents adopt adapter URIs.
  """

  alias Adaptation.{AgentProcess, Pipeline}

  defdelegate record_run(attrs), to: Experience, as: :record_run
  defdelegate ingest_run(run, evaluation), to: Pipeline
  defdelegate enqueue_train(domain, opts \\ []), to: Pipeline
  defdelegate current_adapter(domain), to: Pipeline
  defdelegate current_adapter_ref(domain), to: AgentProcess, as: :current_adapter
  defdelegate adopt_adapter(domain, version, uri), to: AgentProcess

  def start_agent(opts) do
    DynamicSupervisor.start_child(Kino.Adaptation.AgentSupervisor, {AgentProcess, opts})
  end

  def stop_agent(domain) do
    case Registry.lookup(Kino.Adaptation.Registry, domain) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Kino.Adaptation.AgentSupervisor, pid)
      [] -> {:error, :not_started}
    end
  end
end
