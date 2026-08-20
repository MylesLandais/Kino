defmodule Harness.RuntimeTest do
  use ExUnit.Case, async: true

  alias Harness.{Context, Event, Profile, Runtime, Services, Tools}

  defp start_profile(layers) do
    profile = Profile.new(:test, layers)
    start_supervised!({Runtime, profile: profile})
  end

  test "plugin mounts, registers a service, and a consumer resolves it" do
    runtime =
      start_profile([
        %{id: :provider, plugin: Harness.Test.ProviderPlugin},
        %{id: :consumer, plugin: Harness.Test.ConsumerPlugin}
      ])

    ctx = Runtime.context(runtime)

    assert {:ok, %Harness.Test.EchoService{name: :global}} =
             Services.fetch(ctx, Harness.Test.EchoService)

    assert :provider in Harness.Kernel.active_plugins(ctx.kernel)
    assert :consumer in Harness.Kernel.active_plugins(ctx.kernel)
  end

  test "unmounting a plugin removes its service registration" do
    runtime =
      start_profile([
        %{id: :provider, plugin: Harness.Test.ProviderPlugin}
      ])

    ctx = Runtime.context(runtime)
    assert {:ok, _} = Services.fetch(ctx, Harness.Test.EchoService)

    assert :ok = Runtime.unmount(runtime, :provider)

    assert {:error, {:unregistered, Harness.Test.EchoService}} =
             Services.fetch(ctx, Harness.Test.EchoService)
  end

  test "narrower agent scope shadows the global provider" do
    runtime =
      start_profile([
        %{id: :provider, plugin: Harness.Test.ProviderPlugin},
        %{id: :shadow, plugin: Harness.Test.ShadowPlugin}
      ])

    ctx = Runtime.context(runtime)

    assert {:ok, %Harness.Test.EchoService{name: :global}} =
             Services.fetch(ctx, Harness.Test.EchoService)

    agent_ctx = Context.nest(ctx, {:agent, :a})

    assert {:ok, %Harness.Test.EchoService{name: :agent_a}} =
             Services.fetch(agent_ctx, Harness.Test.EchoService)
  end

  test "later profile layers replace a plugin row by id" do
    base =
      Profile.new(:base, [
        %{id: :llm, plugin: Harness.Plugins.MockLLM}
      ])

    overlay =
      Profile.new(:computer_use, [
        %{id: :llm, plugin: Harness.Plugins.MockLLM, config: %{model: "overlay"}}
      ])

    composed = Profile.overlay(base, overlay)
    assert [%{id: :llm, config: %{model: "overlay"}}] = composed.layers
  end

  test "profile can disable a layer" do
    profile =
      Profile.new(:base, [
        %{id: :provider, plugin: Harness.Test.ProviderPlugin},
        %{id: :provider, plugin: Harness.Test.ProviderPlugin, disabled: true}
      ])

    # overlay-style: second row with same id replaces and disables
    runtime = start_supervised!({Runtime, profile: profile})
    ctx = Runtime.context(runtime)

    assert {:error, {:unregistered, Harness.Test.EchoService}} =
             Services.fetch(ctx, Harness.Test.EchoService)
  end

  test "event subscriptions are live and disposed with the plugin" do
    runtime =
      start_profile([
        %{id: :listener, plugin: Harness.Test.ListenerPlugin, config: %{notify: self()}}
      ])

    ctx = Runtime.context(runtime)
    event = Event.new("agent/request", %{step: 1}, class: :live, context: ctx)
    :ok = Context.emit(ctx, event)
    assert_receive {:heard, %Event{name: "agent/request"}}

    :ok = Runtime.unmount(runtime, :listener)
    assert_receive :effect_disposed

    :ok = Context.emit(ctx, event)
    refute_receive {:heard, _}, 50
  end

  test "durable events are reconstructable from the log" do
    runtime =
      start_profile([
        %{id: :event_log, plugin: Harness.Plugins.EventLog}
      ])

    ctx = %{Runtime.context(runtime) | session_id: "sess-1"}
    event = Event.new("user/message", %{text: "hi"}, class: :durable, context: ctx)
    :ok = Context.emit(ctx, event)

    assert [%Event{name: "user/message", payload: %{text: "hi"}}] = Context.replay(ctx)
    assert {:ok, forked} = Context.fork_log(ctx, event.id)
    assert [%Event{name: "user/message"}] = forked
  end

  test "waterfall middleware must call next to delegate" do
    runtime =
      start_profile([
        %{id: :policy, plugin: Harness.Test.WaterfallPlugin}
      ])

    ctx = Runtime.context(runtime)
    result = Context.waterfall(ctx, "agent/pre_step", %{trace: [:claim]})
    assert result.trace == [:claim, :policy]
  end

  test "waterfall short-circuits when next is not called" do
    runtime =
      start_profile([
        %{id: :policy, plugin: Harness.Test.WaterfallPlugin}
      ])

    ctx = Runtime.context(runtime)

    {:ok, _} =
      Context.subscribe(
        ctx,
        "agent/pre_step",
        fn _value, _next ->
          %{trace: [:blocked]}
        end,
        prepend: true
      )

    result = Context.waterfall(ctx, "agent/pre_step", %{trace: [:claim]})
    assert result.trace == [:blocked]
  end

  test "tools are scoped registrations and survive the execute pipeline" do
    runtime =
      start_profile([
        %{id: :tools, plugin: Harness.Test.ToolPlugin}
      ])

    ctx = Runtime.context(runtime)
    assert [%Harness.Tool{id: :echo}] = Tools.list(ctx)
    assert {:ok, {:ok, %{"q" => 1}}} = Tools.execute(ctx, :echo, %{"q" => 1})

    :ok = Runtime.unmount(runtime, :tools)
    assert Tools.list(ctx) == []
  end

  test "consumers use the LLM seam rather than a concrete provider" do
    runtime =
      start_profile([
        %{id: :llm, plugin: Harness.Plugins.MockLLM}
      ])

    ctx = Runtime.context(runtime)
    assert {:ok, %{content: "ok"}} = Harness.LLM.complete(ctx, %{prompt: "hi"})
  end

  test "sandbox seam is swappable behind Harness.Sandbox" do
    runtime =
      start_profile([
        %{id: :sandbox, plugin: Harness.Plugins.LocalSandbox}
      ])

    ctx = Runtime.context(runtime)
    assert {:ok, %{status: 0}} = Harness.Sandbox.exec(ctx, ["echo", "ok"])
  end

  test "plugin inject waits for the service definition to exist" do
    assert {:error,
            {{:shutdown,
              {:failed_to_start_child, Harness.Runtime.Loader,
               {:unsatisfied_dependencies, [:consumer]}}},
             _child}} =
             start_supervised(
               {Runtime,
                profile:
                  Profile.new(:broken, [%{id: :consumer, plugin: Harness.Test.ConsumerPlugin}])}
             )
  end
end
