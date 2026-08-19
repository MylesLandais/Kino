defmodule Harness.Events do
  @moduledoc """
  Event bus over the runtime kernel.

  Dispatch modes match Cordis contracts, expressed with OTP:

  * `emit/2` — observe in registration order (not awaited)
  * `waterfall/3` — around-middleware; call `next.(value)` to delegate
  * `serial/3` — ordered, first non-nil result wins
  * `parallel/3` — bounded `Task.async_stream`

  Durable events are also appended to the session log.
  """

  def subscribe(ctx, name, handler, opts \\ []) do
    Harness.Context.subscribe(ctx, name, handler, opts)
  end

  def emit(ctx, event), do: Harness.Context.emit(ctx, event)
  def emit(ctx, name, payload, opts \\ []), do: Harness.Context.emit(ctx, name, payload, opts)
  def waterfall(ctx, name, value), do: Harness.Context.waterfall(ctx, name, value)
  def serial(ctx, name, value), do: Harness.Context.serial(ctx, name, value)
  def parallel(ctx, name, value), do: Harness.Context.parallel(ctx, name, value)
end
