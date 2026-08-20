defmodule Harness.Event do
  @moduledoc """
  Typed event envelope.

  Durable facts (`:durable`) are appended to the event store. Live extension
  points (`:live`) and capability events (`:capability`) are not the session
  log; they are interceptors and subsystem signals.
  """

  @enforce_keys [:id, :name, :class]
  defstruct [
    :id,
    :name,
    :class,
    :payload,
    :run_id,
    :session_id,
    :agent_id,
    :node_id,
    :parent_event_id,
    :correlation_id,
    :timestamp,
    metadata: %{}
  ]

  @type class :: :durable | :live | :capability
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          class: class(),
          payload: term(),
          run_id: term(),
          session_id: term(),
          agent_id: term(),
          node_id: term(),
          parent_event_id: term(),
          correlation_id: term(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @spec new(String.t(), term(), keyword()) :: t()
  def new(name, payload \\ nil, opts \\ []) when is_binary(name) do
    ctx = Keyword.get(opts, :context)

    %__MODULE__{
      id: Keyword.get_lazy(opts, :id, &id/0),
      name: name,
      class: Keyword.get(opts, :class, :live),
      payload: payload,
      run_id: Keyword.get(opts, :run_id) || ctx_field(ctx, :run_id),
      session_id: Keyword.get(opts, :session_id) || ctx_field(ctx, :session_id),
      agent_id: Keyword.get(opts, :agent_id) || ctx_field(ctx, :agent_id),
      node_id: Keyword.get(opts, :node_id) || ctx_field(ctx, :node_id),
      parent_event_id: Keyword.get(opts, :parent_event_id),
      correlation_id: Keyword.get(opts, :correlation_id) || ctx_field(ctx, :correlation_id),
      timestamp: Keyword.get_lazy(opts, :timestamp, &DateTime.utc_now/0),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp ctx_field(nil, _key), do: nil
  defp ctx_field(ctx, key), do: Map.get(ctx, key)
end
