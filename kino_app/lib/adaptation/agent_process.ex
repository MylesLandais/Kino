defmodule Adaptation.AgentProcess do
  @moduledoc """
  Per-domain agent process: adapter *reference* only.

  Holds `domain`, `base_model`, `adapter_version`, `adapter_uri`, and opaque
  `memory_state`. Adopting a promoted adapter is a state update. It never
  mutates weights and never reads trajectories into the context window.
  """

  use GenServer, restart: :transient

  defstruct [:domain, :base_model, :adapter_version, :adapter_uri, memory_state: %{}]

  def child_spec(opts) do
    domain = Keyword.fetch!(opts, :domain)

    %{
      id: {:adaptation_agent, domain},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }
  end

  def start_link(opts) do
    domain = Keyword.fetch!(opts, :domain)
    GenServer.start_link(__MODULE__, opts, name: via(domain))
  end

  def via(domain), do: {:via, Registry, {Kino.Adaptation.Registry, domain}}

  def current_adapter(domain), do: GenServer.call(via(domain), :current_adapter)

  def adopt_adapter(domain, version, uri) when is_binary(version) and is_binary(uri) do
    GenServer.call(via(domain), {:adopt_adapter, version, uri})
  end

  def snapshot(domain), do: GenServer.call(via(domain), :snapshot)

  @impl true
  def init(opts) do
    domain = Keyword.fetch!(opts, :domain)
    Phoenix.PubSub.subscribe(Kino.PubSub, Adaptation.Pipeline.topic(domain))

    state = %__MODULE__{
      domain: domain,
      base_model: Keyword.get(opts, :base_model, "base"),
      adapter_version: Keyword.get(opts, :adapter_version),
      adapter_uri: Keyword.get(opts, :adapter_uri),
      memory_state: Keyword.get(opts, :memory_state, %{})
    }

    {:ok, maybe_load_promoted(state)}
  end

  @impl true
  def handle_call(:current_adapter, _from, state) do
    {:reply, %{version: state.adapter_version, uri: state.adapter_uri}, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply,
     Map.take(state, [:domain, :base_model, :adapter_version, :adapter_uri, :memory_state]),
     state}
  end

  def handle_call({:adopt_adapter, version, uri}, _from, state) do
    {:reply, :ok, %{state | adapter_version: version, adapter_uri: uri}}
  end

  @impl true
  def handle_info(
        {:adaptation, %{decision: :promoted, version: version, artifact_uri: uri}},
        state
      )
      when is_binary(version) and is_binary(uri) do
    {:noreply, %{state | adapter_version: version, adapter_uri: uri}}
  end

  def handle_info({:adaptation, _payload}, state), do: {:noreply, state}

  defp maybe_load_promoted(state) do
    case Adaptation.Pipeline.current_adapter(state.domain) do
      %{version: version, artifact_uri: uri} ->
        %{state | adapter_version: version, adapter_uri: uri}

      _ ->
        state
    end
  end
end
