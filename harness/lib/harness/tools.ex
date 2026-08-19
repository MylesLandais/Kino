defmodule Harness.Tool do
  @moduledoc "Plugin-declared tool. Execution is scoped to the registering agent."

  defstruct [
    :id,
    :description,
    :schema,
    :authorization,
    :executor,
    :timeout,
    scope: [:global]
  ]

  @type t :: %__MODULE__{
          id: atom(),
          description: String.t() | nil,
          schema: map() | nil,
          authorization: term(),
          executor: (map() -> {:ok, term()} | {:error, term()}),
          timeout: pos_integer() | nil,
          scope: Harness.Scope.t()
        }
end

defmodule Harness.Tools do
  @moduledoc """
  Scoped tool registry and execution pipeline.

  Pipeline:

      tool/call → tools/pre_execute → authorization → tools/execute
      → tools/post_execute → tool/result
  """

  def register(%Harness.Context{} = ctx, %Harness.Tool{} = tool, opts \\ []) do
    opts = Keyword.put_new(opts, :scope, ctx.scope)
    Harness.Kernel.register_tool(ctx.kernel, ctx.plugin_id, tool, opts)
  end

  def list(%Harness.Context{} = ctx), do: Harness.Kernel.list_tools(ctx.kernel, ctx.scope)
  def fetch(ctx, id), do: Harness.Kernel.fetch_tool(ctx.kernel, id, ctx.scope)

  def execute(%Harness.Context{} = ctx, tool_id, arguments) when is_map(arguments) do
    with {:ok, tool} <- fetch(ctx, tool_id) do
      call = %{
        tool: tool,
        arguments: arguments,
        ctx: ctx,
        cancelled?: false,
        result: nil
      }

      _ = Harness.Events.emit(ctx, "tool/call", call, class: :durable)
      prepared = Harness.Events.waterfall(ctx, "tools/pre_execute", call)

      cond do
        prepared[:cancelled?] ->
          {:error, :cancelled}

        true ->
          executed =
            Harness.Events.waterfall(ctx, "tools/execute", put_exec(prepared, tool, arguments))

          finalized = Harness.Events.waterfall(ctx, "tools/post_execute", executed)
          _ = Harness.Events.emit(ctx, "tool/result", finalized, class: :durable)
          {:ok, finalized.result}
      end
    end
  end

  defp put_exec(call, tool, arguments) do
    result =
      case call.result do
        nil -> tool.executor.(arguments)
        existing -> existing
      end

    Map.put(call, :result, result)
  end
end
