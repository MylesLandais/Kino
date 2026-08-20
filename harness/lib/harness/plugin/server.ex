defmodule Harness.Plugin.Server do
  @moduledoc false
  use GenServer, restart: :temporary

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def init(opts) do
    Process.flag(:trap_exit, true)

    plugin = Keyword.fetch!(opts, :plugin)
    kernel = Keyword.fetch!(opts, :kernel)
    config = Keyword.get(opts, :config, %{})
    ctx = Keyword.fetch!(opts, :context)
    ctx = %{ctx | plugin_id: plugin.id()}

    with {:ok, state} <- plugin.init(config),
         :ok <- Harness.Kernel.plugin_starting(kernel, plugin.id(), self()),
         {:ok, ctx, disposer} <- plugin.mount(ctx, state) do
      :ok = Harness.Kernel.effect(kernel, plugin.id(), disposer)
      :ok = Harness.Kernel.plugin_active(kernel, plugin.id())

      :telemetry.execute([:harness, :plugin, :mount], %{count: 1}, %{plugin: plugin.id()})

      {:ok, %{plugin: plugin, state: state, ctx: ctx, kernel: kernel}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  def terminate(_reason, %{plugin: plugin, ctx: ctx, state: state, kernel: kernel}) do
    if function_exported?(plugin, :unmount, 2) do
      plugin.unmount(ctx, state)
    end

    Harness.Kernel.dispose_plugin(kernel, plugin.id())
    :telemetry.execute([:harness, :plugin, :unmount], %{count: 1}, %{plugin: plugin.id()})
    :ok
  catch
    :exit, _ -> :ok
  end
end
