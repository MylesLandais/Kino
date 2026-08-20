defmodule Harness.Runtime do
  @moduledoc """
  Supervised plugin tree for one profile.

  Children: kernel, PubSub, plugin DynamicSupervisor, in-memory event store,
  and a loader that mounts layers once dependencies and injected services
  are satisfied.
  """

  use Supervisor

  def start_link(opts) do
    id = Keyword.get_lazy(opts, :id, fn -> System.unique_integer([:positive]) end)
    opts = Keyword.put(opts, :id, id)
    name = Keyword.get(opts, :name, via(id, :supervisor))
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    id = Keyword.get(opts, :id, :runtime)

    %{
      id: {:harness_runtime, id},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def stop(sup) when is_pid(sup), do: Supervisor.stop(sup)
  def stop(id), do: Supervisor.stop(via(id, :supervisor))

  def context(runtime), do: Harness.Runtime.Loader.context(loader(runtime))
  def unmount(runtime, plugin_id), do: Harness.Runtime.Loader.unmount(loader(runtime), plugin_id)
  def mount_layer(runtime, layer), do: Harness.Runtime.Loader.mount_layer(loader(runtime), layer)

  def via(id, role), do: {:via, Registry, {Harness.Registry, {id, role}}}
  def pubsub_name(id), do: :"harness.pubsub.#{id}"

  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    pubsub = pubsub_name(id)

    children = [
      {Phoenix.PubSub, [name: pubsub]},
      {Task.Supervisor, name: via(id, :tasks)},
      {Harness.EventStore.Memory, [name: via(id, :event_store)]},
      {Harness.Kernel, [id: id, name: via(id, :kernel), pubsub: pubsub]},
      {DynamicSupervisor, name: via(id, :plugins), strategy: :one_for_one},
      {Harness.Runtime.Loader, opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp loader(pid) when is_pid(pid) do
    pid
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {Harness.Runtime.Loader, child, _, _} -> child
      _ -> nil
    end)
  end

  defp loader(id), do: via(id, :loader)
end

defmodule Harness.Runtime.Loader do
  @moduledoc false
  use GenServer

  alias Harness.{Context, Kernel, Plugin, Profile}

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: Harness.Runtime.via(id, :loader))
  end

  def context(loader), do: GenServer.call(loader, :context)
  def unmount(loader, plugin_id), do: GenServer.call(loader, {:unmount, plugin_id})
  def mount_layer(loader, layer), do: GenServer.call(loader, {:mount_layer, layer})

  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    profile = Keyword.fetch!(opts, :profile)
    kernel = Harness.Runtime.via(id, :kernel)
    store = Harness.Runtime.via(id, :event_store)

    :ok = Kernel.set_event_store(kernel, store)

    ctx = %Context{
      runtime_id: id,
      kernel: kernel,
      pubsub: Harness.Runtime.pubsub_name(id),
      plugin_id: :runtime,
      scope: Harness.Scope.profile(profile.id),
      run_id: Keyword.get(opts, :run_id),
      session_id: Keyword.get(opts, :session_id),
      metadata: %{profile: profile.id}
    }

    case mount_profile(profile, ctx, id) do
      {:ok, children} ->
        {:ok, %{id: id, ctx: ctx, profile: profile, children: children}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_call(:context, _from, state), do: {:reply, state.ctx, state}

  def handle_call({:unmount, plugin_id}, _from, state) do
    case Map.get(state.children, plugin_id) do
      nil ->
        {:reply, {:error, :not_mounted}, state}

      pid ->
        _ = DynamicSupervisor.terminate_child(Harness.Runtime.via(state.id, :plugins), pid)
        {:reply, :ok, %{state | children: Map.delete(state.children, plugin_id)}}
    end
  end

  def handle_call({:mount_layer, layer}, _from, state) do
    case start_plugin(layer, state.ctx, state.id) do
      {:ok, pid, plugin_id} ->
        {:reply, :ok, %{state | children: Map.put(state.children, plugin_id, pid)}}

      other ->
        {:reply, other, state}
    end
  end

  defp mount_profile(profile, ctx, runtime_id) do
    mount_pass(Profile.enabled_layers(profile), ctx, runtime_id, %{})
  end

  defp mount_pass([], _ctx, _runtime_id, mounted), do: {:ok, mounted}

  defp mount_pass(pending, ctx, runtime_id, mounted) do
    {ready, waiting} = Enum.split_with(pending, &ready?(&1, ctx, mounted))

    if ready == [] do
      {:error, {:unsatisfied_dependencies, Enum.map(waiting, & &1.id)}}
    else
      Enum.reduce_while(ready, {:ok, mounted}, fn layer, {:ok, mounted} ->
        case start_plugin(layer, ctx, runtime_id) do
          {:ok, pid, plugin_id} -> {:cont, {:ok, Map.put(mounted, plugin_id, pid)}}
          {:error, reason} -> {:halt, {:error, {layer.id, reason}}}
        end
      end)
      |> case do
        {:ok, mounted} -> mount_pass(waiting, ctx, runtime_id, mounted)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp ready?(layer, ctx, mounted) do
    plugin = layer.plugin
    deps = Plugin.dependencies(plugin)
    inject = Plugin.inject(plugin)

    Enum.all?(deps, &Map.has_key?(mounted, &1)) and
      Enum.all?(inject, &Harness.Kernel.has_service?(ctx.kernel, &1))
  end

  defp start_plugin(layer, ctx, runtime_id) do
    ctx = %{ctx | scope: layer.scope || ctx.scope, plugin_id: layer.plugin.id()}

    spec = %{
      id: layer.plugin.id(),
      start:
        {Harness.Plugin.Server, :start_link,
         [
           [
             plugin: layer.plugin,
             kernel: ctx.kernel,
             context: ctx,
             config: layer.config
           ]
         ]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(Harness.Runtime.via(runtime_id, :plugins), spec) do
      {:ok, pid} -> {:ok, pid, layer.plugin.id()}
      {:error, {:already_started, pid}} -> {:ok, pid, layer.plugin.id()}
      other -> other
    end
  end
end
