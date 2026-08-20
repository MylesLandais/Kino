defmodule Harness.EventStore do
  @moduledoc """
  Append-only durable log. Model-visible state must be reconstructable from it.
  """

  @type t :: pid() | term()
  @type stream_id :: term()

  @callback append(t(), stream_id(), Harness.Event.t()) :: :ok | {:error, term()}
  @callback replay(t(), stream_id()) :: [Harness.Event.t()]
  @callback fork(t(), stream_id(), boundary :: term()) ::
              {:ok, stream_id()} | {:error, term()}

  def append(store, stream_id, event) do
    Harness.EventStore.Memory.append(store, stream_id, event)
  end

  def replay(store, stream_id) do
    Harness.EventStore.Memory.replay(store, stream_id)
  end

  def fork(store, stream_id, boundary) do
    Harness.EventStore.Memory.fork(store, stream_id, boundary)
  end
end

defmodule Harness.EventStore.Memory do
  @moduledoc "In-memory event store. PostgreSQL is the intended durable backend."
  use Agent

  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{streams: %{}} end, Keyword.take(opts, [:name]))
  end

  def append(pid, stream_id, event) do
    Agent.update(pid, fn state ->
      streams = Map.update(state.streams, stream_id, [event], &(&1 ++ [event]))
      %{state | streams: streams}
    end)
  end

  def replay(pid, stream_id) do
    Agent.get(pid, fn state -> Map.get(state.streams, stream_id, []) end)
  end

  def fork(pid, stream_id, boundary) do
    Agent.get_and_update(pid, fn state ->
      events = Map.get(state.streams, stream_id, [])

      kept =
        if is_nil(boundary) do
          events
        else
          {keep, rest} = Enum.split_while(events, &(&1.id != boundary))
          keep ++ Enum.take(rest, 1)
        end

      child = {stream_id, System.unique_integer([:positive])}
      {{:ok, child}, %{state | streams: Map.put(state.streams, child, kept)}}
    end)
  end
end
