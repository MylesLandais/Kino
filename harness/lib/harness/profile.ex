defmodule Harness.Profile do
  @moduledoc """
  Ordered plugin composition.

  Later layers may replace a row by `id`, disable a capability, override
  config, or insert a new plugin. This is the OTP analogue of DeepSeek
  Harness profiles/bundles/patches — runtime composition, not a hard-coded
  application core.
  """

  defmodule Layer do
    @moduledoc false
    defstruct [:id, :plugin, config: %{}, disabled: false, scope: nil]

    @type t :: %__MODULE__{
            id: atom(),
            plugin: module(),
            config: map(),
            disabled: boolean(),
            scope: Harness.Scope.t() | nil
          }
  end

  defstruct [:id, layers: []]

  @type t :: %__MODULE__{id: atom(), layers: [Layer.t()]}

  def new(id, layers) when is_list(layers) do
    collapsed =
      layers
      |> Enum.map(&normalize/1)
      |> Enum.reduce([], fn layer, acc -> apply_layer(acc, layer) end)

    %__MODULE__{id: id, layers: collapsed}
  end

  @doc "Apply `patch` on top of `base`. Later wins on the same layer id."
  def overlay(%__MODULE__{} = base, %__MODULE__{} = patch) do
    layers = Enum.reduce(patch.layers, base.layers, &apply_layer(&2, &1))
    %__MODULE__{id: patch.id || base.id, layers: layers}
  end

  def compose([first | rest]), do: Enum.reduce(rest, first, fn p, acc -> overlay(acc, p) end)
  def compose([]), do: %__MODULE__{id: :empty, layers: []}

  def enabled_layers(%__MODULE__{layers: layers}) do
    Enum.reject(layers, & &1.disabled)
  end

  defp apply_layer(layers, %Layer{id: id} = layer) do
    case Enum.find_index(layers, &(&1.id == id)) do
      nil -> layers ++ [layer]
      index -> List.replace_at(layers, index, layer)
    end
  end

  defp normalize(%Layer{} = layer), do: layer

  defp normalize(opts) when is_list(opts) or is_map(opts) do
    opts = Map.new(opts)

    %Layer{
      id: Map.fetch!(opts, :id),
      plugin: Map.fetch!(opts, :plugin),
      config: Map.get(opts, :config, %{}),
      disabled: Map.get(opts, :disabled, false),
      scope: Map.get(opts, :scope)
    }
  end
end
