defmodule Harness.Plugin do
  @moduledoc """
  Plugin contract.

  Every replaceable capability is a plugin. `mount/2` contributes services,
  event handlers, tools, and workers through `Harness.Context`. Every
  registration is an effect with a disposer; unloading the plugin must leave
  nothing behind.
  """

  @type config :: map()
  @type state :: term()
  @type disposer :: (-> any()) | nil

  @callback id() :: atom()
  @callback dependencies() :: [atom()]
  @callback inject() :: [module()]
  @callback init(config()) :: {:ok, state()} | {:error, term()}
  @callback mount(Harness.Context.t(), state()) ::
              {:ok, Harness.Context.t(), disposer()} | {:error, term()}
  @callback unmount(Harness.Context.t(), state()) :: :ok

  @optional_callbacks inject: 0, unmount: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Harness.Plugin

      @impl Harness.Plugin
      def dependencies, do: []

      @impl Harness.Plugin
      def inject, do: []

      @impl Harness.Plugin
      def init(config), do: {:ok, config}

      defoverridable dependencies: 0, inject: 0, init: 1
    end
  end

  @doc "Plugin ids that must be ACTIVE before this plugin mounts."
  def dependencies(module) do
    Code.ensure_loaded!(module)
    if function_exported?(module, :dependencies, 0), do: module.dependencies(), else: []
  end

  @doc "Service behaviours that must already be registered."
  def inject(module) do
    Code.ensure_loaded!(module)
    if function_exported?(module, :inject, 0), do: module.inject(), else: []
  end
end
