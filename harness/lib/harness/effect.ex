defmodule Harness.Effect do
  @moduledoc """
  A reversible registration.

  Cordis treats every `ctx.on` / `ctx.effect` as something that must unwind
  when the plugin Fiber unloads. Here the disposer is a zero-arity function
  stored on the plugin scope and invoked in reverse registration order.
  """

  @type t :: (-> any())

  @spec wrap(t() | nil) :: t()
  def wrap(nil), do: fn -> :ok end
  def wrap(fun) when is_function(fun, 0), do: fun

  @spec compose([t()]) :: t()
  def compose(disposers) when is_list(disposers) do
    fn -> Enum.each(Enum.reverse(disposers), &safe_call/1) end
  end

  @spec safe_call(t()) :: :ok
  def safe_call(fun) when is_function(fun, 0) do
    fun.()
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
