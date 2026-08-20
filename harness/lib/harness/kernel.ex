defmodule Harness.Kernel do
  @moduledoc false
  use GenServer

  alias Harness.{Effect, Event, Scope}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def via(runtime_id), do: {:via, Registry, {Harness.Registry, {runtime_id, :kernel}}}

  def init(opts) do
    {:ok,
     %{
       id: Keyword.fetch!(opts, :id),
       pubsub: Keyword.fetch!(opts, :pubsub),
       event_store: nil,
       services: %{},
       listeners: %{},
       tools: %{},
       effects: %{},
       plugins: %{},
       event_log: []
     }}
  end

  def register_service(kernel, plugin_id, behaviour, impl, opts) do
    GenServer.call(kernel, {:register_service, plugin_id, behaviour, impl, opts})
  end

  def fetch_service(kernel, behaviour, scope) do
    GenServer.call(kernel, {:fetch_service, behaviour, scope})
  end

  def has_service?(kernel, behaviour), do: GenServer.call(kernel, {:has_service, behaviour})

  def subscribe(kernel, plugin_id, name, handler, opts) do
    GenServer.call(kernel, {:subscribe, plugin_id, name, handler, opts})
  end

  def emit(kernel, event), do: GenServer.call(kernel, {:emit, event})
  def waterfall(kernel, name, value), do: GenServer.call(kernel, {:waterfall, name, value})
  def serial(kernel, name, value), do: GenServer.call(kernel, {:serial, name, value})
  def parallel(kernel, name, value), do: GenServer.call(kernel, {:parallel, name, value})

  def effect(kernel, plugin_id, disposer),
    do: GenServer.call(kernel, {:effect, plugin_id, disposer})

  def register_tool(kernel, plugin_id, tool, opts) do
    GenServer.call(kernel, {:register_tool, plugin_id, tool, opts})
  end

  def list_tools(kernel, scope), do: GenServer.call(kernel, {:list_tools, scope})
  def fetch_tool(kernel, id, scope), do: GenServer.call(kernel, {:fetch_tool, id, scope})

  def plugin_starting(kernel, plugin_id, pid),
    do: GenServer.call(kernel, {:plugin_starting, plugin_id, pid})

  def plugin_active(kernel, plugin_id), do: GenServer.call(kernel, {:plugin_active, plugin_id})
  def plugin_status(kernel, plugin_id), do: GenServer.call(kernel, {:plugin_status, plugin_id})
  def active_plugins(kernel), do: GenServer.call(kernel, :active_plugins)
  def replay(kernel), do: GenServer.call(kernel, :replay)
  def fork_log(kernel, boundary), do: GenServer.call(kernel, {:fork_log, boundary})
  def dispose_plugin(kernel, plugin_id), do: GenServer.call(kernel, {:dispose_plugin, plugin_id})
  def set_event_store(kernel, store), do: GenServer.call(kernel, {:set_event_store, store})

  def handle_call({:register_service, plugin_id, behaviour, impl, opts}, _from, state) do
    scope = Keyword.get(opts, :scope, [:global])
    key = {behaviour, Scope.key(scope)}
    entry = %{id: id(), plugin_id: plugin_id, impl: impl, opts: opts, scope: scope}
    services = Map.update(state.services, key, [entry], &[entry | &1])
    kernel = self()

    disposer = fn ->
      GenServer.call(kernel, {:drop_service, key, entry.id})
    end

    :telemetry.execute([:harness, :service, :register], %{count: 1}, %{
      behaviour: behaviour,
      plugin: plugin_id
    })

    {:reply, {:ok, disposer}, %{state | services: services}}
  end

  def handle_call({:drop_service, key, entry_id}, _from, state) do
    services =
      Map.update(state.services, key, [], fn entries ->
        Enum.reject(entries, &(&1.id == entry_id))
      end)

    {:reply, :ok, %{state | services: services}}
  end

  def handle_call({:fetch_service, behaviour, scope}, _from, state) do
    {:reply, lookup_service(state, behaviour, scope), state}
  end

  def handle_call({:has_service, behaviour}, _from, state) do
    found =
      Enum.any?(state.services, fn {{mod, _scope}, entries} ->
        mod == behaviour and entries != []
      end)

    {:reply, found, state}
  end

  def handle_call({:subscribe, plugin_id, name, handler, opts}, _from, state) do
    entry = %{
      id: id(),
      plugin_id: plugin_id,
      handler: handler,
      opts: opts,
      name: name
    }

    listeners =
      Map.update(state.listeners, name, [entry], fn existing ->
        if Keyword.get(opts, :prepend, false), do: [entry | existing], else: existing ++ [entry]
      end)

    kernel = self()

    disposer = fn ->
      GenServer.call(kernel, {:drop_listener, name, entry.id})
    end

    {:reply, {:ok, disposer}, %{state | listeners: listeners}}
  end

  def handle_call({:drop_listener, name, entry_id}, _from, state) do
    listeners =
      Map.update(state.listeners, name, [], fn entries ->
        Enum.reject(entries, &(&1.id == entry_id))
      end)

    {:reply, :ok, %{state | listeners: listeners}}
  end

  def handle_call({:emit, event}, _from, state) do
    state = persist(state, event)
    listeners = Map.get(state.listeners, event.name, [])
    Enum.each(listeners, fn entry -> invoke_emit(entry.handler, event) end)
    Phoenix.PubSub.broadcast(state.pubsub, topic(event.name), {:harness_event, event})

    :telemetry.execute([:harness, :event, :emit], %{count: 1}, %{
      name: event.name,
      class: event.class
    })

    {:reply, :ok, state}
  end

  def handle_call({:waterfall, name, value}, _from, state) do
    {:reply, call_waterfall(Map.get(state.listeners, name, []), value), state}
  end

  def handle_call({:serial, name, value}, _from, state) do
    result =
      Enum.reduce_while(Map.get(state.listeners, name, []), nil, fn entry, _ ->
        case invoke_serial(entry.handler, value) do
          nil -> {:cont, nil}
          other -> {:halt, other}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:parallel, name, value}, _from, state) do
    listeners = Map.get(state.listeners, name, [])

    results =
      listeners
      |> Task.async_stream(fn entry -> invoke_emit(entry.handler, value) end,
        ordered: false,
        timeout: 5_000,
        on_timeout: :kill_task,
        max_concurrency: max(length(listeners), 1)
      )
      |> Enum.to_list()

    {:reply, results, state}
  end

  def handle_call({:effect, plugin_id, disposer}, _from, state) do
    {:reply, :ok, push_effect(state, plugin_id, Effect.wrap(disposer))}
  end

  def handle_call({:register_tool, plugin_id, tool, opts}, _from, state) do
    scope = Keyword.get(opts, :scope, tool.scope || [:global])
    key = {tool.id, Scope.key(scope)}
    entry = %{plugin_id: plugin_id, tool: %{tool | scope: scope}}
    kernel = self()

    disposer = fn ->
      GenServer.call(kernel, {:drop_tool, key})
    end

    {:reply, {:ok, disposer}, %{state | tools: Map.put(state.tools, key, entry)}}
  end

  def handle_call({:drop_tool, key}, _from, state) do
    {:reply, :ok, %{state | tools: Map.delete(state.tools, key)}}
  end

  def handle_call({:list_tools, scope}, _from, state) do
    tools =
      Enum.reduce(Scope.chain(scope), %{}, fn path, acc ->
        Enum.reduce(state.tools, acc, fn {{id, key}, entry}, acc ->
          if key == Scope.key(path) and not Map.has_key?(acc, id) do
            Map.put(acc, id, entry.tool)
          else
            acc
          end
        end)
      end)
      |> Map.values()

    {:reply, tools, state}
  end

  def handle_call({:fetch_tool, id, scope}, _from, state) do
    result =
      Enum.find_value(Scope.chain(scope), fn path ->
        case Map.get(state.tools, {id, Scope.key(path)}) do
          %{tool: tool} -> {:ok, tool}
          _ -> nil
        end
      end) || {:error, :not_found}

    {:reply, result, state}
  end

  def handle_call({:plugin_starting, plugin_id, pid}, _from, state) do
    Process.monitor(pid)
    plugins = Map.put(state.plugins, plugin_id, %{pid: pid, status: :loading})
    {:reply, :ok, %{state | plugins: plugins}}
  end

  def handle_call({:plugin_active, plugin_id}, _from, state) do
    plugins = Map.update!(state.plugins, plugin_id, &Map.put(&1, :status, :active))
    {:reply, :ok, %{state | plugins: plugins}}
  end

  def handle_call({:plugin_status, plugin_id}, _from, state) do
    status =
      case Map.get(state.plugins, plugin_id) do
        %{status: status} -> status
        _ -> :missing
      end

    {:reply, status, state}
  end

  def handle_call(:active_plugins, _from, state) do
    {:reply, for({id, %{status: :active}} <- state.plugins, do: id), state}
  end

  def handle_call(:replay, _from, state) do
    {:reply, Enum.reverse(state.event_log), state}
  end

  def handle_call({:fork_log, boundary}, _from, state) do
    chrono = Enum.reverse(state.event_log)

    events =
      if is_nil(boundary) do
        chrono
      else
        {keep, rest} = Enum.split_while(chrono, &(&1.id != boundary))
        keep ++ Enum.take(rest, 1)
      end

    {:reply, {:ok, events}, state}
  end

  def handle_call({:dispose_plugin, plugin_id}, _from, state) do
    {:reply, :ok, drop_plugin(state, plugin_id)}
  end

  def handle_call({:set_event_store, store}, _from, state) do
    {:reply, :ok, %{state | event_store: store}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    plugin_id =
      Enum.find_value(state.plugins, fn {id, meta} ->
        if meta.pid == pid, do: id
      end)

    {:noreply, if(plugin_id, do: drop_plugin(state, plugin_id), else: state)}
  end

  defp lookup_service(state, behaviour, scope) do
    Enum.find_value(Scope.chain(scope), fn path ->
      case Map.get(state.services, {behaviour, Scope.key(path)}) do
        [entry | _] -> {:ok, entry.impl}
        _ -> nil
      end
    end) || {:error, {:unregistered, behaviour}}
  end

  defp persist(state, %Event{class: :durable} = event) do
    if store = state.event_store do
      _ = Harness.EventStore.append(store, stream_id(event), event)
    end

    %{state | event_log: [event | state.event_log]}
  end

  defp persist(state, _event), do: state

  defp stream_id(%Event{session_id: id}) when not is_nil(id), do: id
  defp stream_id(%Event{run_id: id}) when not is_nil(id), do: id
  defp stream_id(_), do: :default

  defp push_effect(state, plugin_id, disposer) do
    effects = Map.update(state.effects, plugin_id, [disposer], &(&1 ++ [disposer]))
    %{state | effects: effects}
  end

  defp drop_plugin(state, plugin_id) do
    state.effects
    |> Map.get(plugin_id, [])
    |> Enum.reverse()
    |> Enum.each(&Effect.safe_call/1)

    services =
      Map.new(state.services, fn {key, entries} ->
        {key, Enum.reject(entries, &(&1.plugin_id == plugin_id))}
      end)

    listeners =
      Map.new(state.listeners, fn {name, entries} ->
        {name, Enum.reject(entries, &(&1.plugin_id == plugin_id))}
      end)

    tools =
      state.tools
      |> Enum.reject(fn {_key, entry} -> entry.plugin_id == plugin_id end)
      |> Map.new()

    %{
      state
      | effects: Map.delete(state.effects, plugin_id),
        plugins: Map.delete(state.plugins, plugin_id),
        services: services,
        listeners: listeners,
        tools: tools
    }
  end

  defp call_waterfall([], value), do: value

  defp call_waterfall([entry | rest], value) do
    next = fn next_value -> call_waterfall(rest, next_value) end
    invoke_waterfall(entry.handler, value, next)
  end

  defp invoke_emit(handler, event) when is_function(handler, 1), do: handler.(event)
  defp invoke_emit({mod, fun, args}, event), do: apply(mod, fun, args ++ [event])

  defp invoke_serial(handler, value) when is_function(handler, 1), do: handler.(value)

  defp invoke_waterfall(handler, value, next) when is_function(handler, 2) do
    handler.(value, next)
  end

  defp invoke_waterfall(handler, value, next) when is_function(handler, 1) do
    handler.(value)
    next.(value)
  end

  defp topic(name), do: "harness:#{name}"
  defp id, do: System.unique_integer([:positive])
end
