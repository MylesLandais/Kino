defmodule Harness.Test.EchoService do
  defstruct [:name]
  def ping(%__MODULE__{name: name}), do: {:pong, name}
end

defmodule Harness.Test.ProviderPlugin do
  use Harness.Plugin

  @impl true
  def id, do: :provider

  @impl true
  def mount(ctx, _state) do
    {:ok, disposer} =
      Harness.Context.register_service(ctx, Harness.Test.EchoService, %Harness.Test.EchoService{
        name: :global
      })

    {:ok, ctx, disposer}
  end
end

defmodule Harness.Test.ConsumerPlugin do
  use Harness.Plugin

  @impl true
  def id, do: :consumer

  @impl true
  def inject, do: [Harness.Test.EchoService]

  @impl true
  def mount(ctx, _state) do
    _impl = Harness.Services.fetch!(ctx, Harness.Test.EchoService)
    {:ok, ctx, fn -> :ok end}
  end
end

defmodule Harness.Test.ShadowPlugin do
  use Harness.Plugin

  @impl true
  def id, do: :shadow

  @impl true
  def dependencies, do: [:provider]

  @impl true
  def mount(ctx, _state) do
    ctx = Harness.Context.nest(ctx, {:agent, :a})

    {:ok, disposer} =
      Harness.Context.register_service(ctx, Harness.Test.EchoService, %Harness.Test.EchoService{
        name: :agent_a
      })

    {:ok, ctx, disposer}
  end
end

defmodule Harness.Test.ListenerPlugin do
  use Harness.Plugin

  @impl true
  def id, do: :listener

  @impl true
  def mount(ctx, state) do
    notify = Map.get(state, :notify, self())

    {:ok, disposer} =
      Harness.Context.subscribe(ctx, "agent/request", fn event ->
        send(notify, {:heard, event})
      end)

    :ok =
      Harness.Context.effect(ctx, fn ->
        send(notify, :effect_disposed)
      end)

    {:ok, ctx, disposer}
  end
end

defmodule Harness.Test.ToolPlugin do
  use Harness.Plugin

  @impl true
  def id, do: :tools

  @impl true
  def mount(ctx, _state) do
    tool = %Harness.Tool{
      id: :echo,
      description: "echo",
      executor: fn args -> {:ok, args} end
    }

    {:ok, disposer} = Harness.Tools.register(ctx, tool)
    {:ok, ctx, disposer}
  end
end

defmodule Harness.Test.WaterfallPlugin do
  use Harness.Plugin

  @impl true
  def id, do: :policy

  @impl true
  def mount(ctx, _state) do
    {:ok, disposer} =
      Harness.Context.subscribe(ctx, "agent/pre_step", fn value, next ->
        value
        |> Map.update(:trace, [:policy], &(&1 ++ [:policy]))
        |> next.()
      end)

    {:ok, ctx, disposer}
  end
end
