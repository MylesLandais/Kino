defmodule Harness.Scope do
  @moduledoc """
  Capability lookup path. Narrower scopes shadow broader providers.

      global → profile → session → agent → subgraph → task
  """

  @type segment ::
          :global
          | {:profile, atom()}
          | {:session, term()}
          | {:agent, term()}
          | {:subgraph, term()}
          | {:task, term()}
          | {:plugin, atom()}
          | atom()
          | {atom(), term()}

  @type t :: [segment()]

  def global, do: [:global]
  def profile(id), do: [:global, {:profile, id}]
  def session(id), do: [:global, {:session, id}]
  def agent(id), do: [:global, {:agent, id}]

  def nest(scope, segment) when is_list(scope), do: scope ++ [segment]

  def key(scope) when is_list(scope), do: List.to_tuple(scope)

  @doc "Walk from the current scope toward global (narrowest first)."
  def chain(scope) when is_list(scope) do
    scope
    |> Enum.scan([], fn segment, acc -> acc ++ [segment] end)
    |> Enum.reverse()
  end
end
