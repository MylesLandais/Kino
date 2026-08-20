defmodule Harness.Services do
  @moduledoc """
  Service lookup. Consumers depend on a behaviour, never a provider module.
  """

  def fetch(ctx, behaviour), do: Harness.Context.fetch_service(ctx, behaviour)
  def fetch!(ctx, behaviour), do: Harness.Context.fetch_service!(ctx, behaviour)
  def registered?(kernel, behaviour), do: Harness.Kernel.has_service?(kernel, behaviour)
end
