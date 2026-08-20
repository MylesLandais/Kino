defmodule Harness.Context do
  @moduledoc """
  Explicit runtime context. No hidden process dictionary.

  Plugins contribute through this struct; consumers resolve capabilities
  from it. A narrower `scope` shadows a broader provider of the same
  service or tool.
  """

  defstruct [
    :runtime_id,
    :kernel,
    :pubsub,
    :plugin_id,
    :run_id,
    :session_id,
    :agent_id,
    :node_id,
    :correlation_id,
    scope: [:global],
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  def register_service(%__MODULE__{} = ctx, behaviour, impl, opts \\ []) do
    opts = Keyword.put_new(opts, :scope, ctx.scope)
    Harness.Kernel.register_service(ctx.kernel, ctx.plugin_id, behaviour, impl, opts)
  end

  def fetch_service(%__MODULE__{} = ctx, behaviour) do
    Harness.Kernel.fetch_service(ctx.kernel, behaviour, ctx.scope)
  end

  def fetch_service!(ctx, behaviour) do
    case fetch_service(ctx, behaviour) do
      {:ok, impl} -> impl
      {:error, reason} -> raise ArgumentError, "service #{inspect(behaviour)}: #{inspect(reason)}"
    end
  end

  def subscribe(%__MODULE__{} = ctx, name, handler, opts \\ []) do
    Harness.Kernel.subscribe(ctx.kernel, ctx.plugin_id, name, handler, opts)
  end

  def effect(%__MODULE__{} = ctx, disposer) do
    Harness.Kernel.effect(ctx.kernel, ctx.plugin_id, disposer)
  end

  def emit(%__MODULE__{} = ctx, %Harness.Event{} = event) do
    Harness.Kernel.emit(ctx.kernel, event)
  end

  def emit(%__MODULE__{} = ctx, name, payload \\ nil, opts \\ []) when is_binary(name) do
    event = Harness.Event.new(name, payload, Keyword.put(opts, :context, ctx))
    emit(ctx, event)
  end

  def waterfall(%__MODULE__{} = ctx, name, value) do
    Harness.Kernel.waterfall(ctx.kernel, name, value)
  end

  def serial(%__MODULE__{} = ctx, name, value) do
    Harness.Kernel.serial(ctx.kernel, name, value)
  end

  def parallel(%__MODULE__{} = ctx, name, value) do
    Harness.Kernel.parallel(ctx.kernel, name, value)
  end

  def child(%__MODULE__{} = ctx, attrs) when is_list(attrs) or is_map(attrs) do
    struct(ctx, Map.new(attrs))
  end

  def nest(%__MODULE__{} = ctx, segment) do
    %{ctx | scope: Harness.Scope.nest(ctx.scope, segment)}
  end

  def replay(%__MODULE__{} = ctx), do: Harness.Kernel.replay(ctx.kernel)
  def fork_log(%__MODULE__{} = ctx, boundary), do: Harness.Kernel.fork_log(ctx.kernel, boundary)
end
