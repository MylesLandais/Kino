defmodule Harness.Plugins.EventLog do
  @moduledoc "Registers the runtime event store as a replaceable service."
  use Harness.Plugin

  @impl true
  def id, do: :event_log

  @impl true
  def mount(ctx, _state) do
    store = Harness.Runtime.via(ctx.runtime_id, :event_store)
    {:ok, disposer} = Harness.Context.register_service(ctx, Harness.EventStore, store)
    {:ok, ctx, disposer}
  end
end
