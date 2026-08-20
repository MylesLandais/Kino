defmodule Harness.LLM.Mock do
  @moduledoc "Deterministic LLM provider for tests and local composition."
  @behaviour Harness.LLM

  defstruct replies: []

  def new(replies) when is_list(replies), do: %__MODULE__{replies: replies}

  @impl true
  def complete(%__MODULE__{replies: [next | _]}, _request), do: {:ok, next}
  def complete(%__MODULE__{replies: []}, _request), do: {:ok, %{content: "", tool_calls: []}}
end

defmodule Harness.Plugins.MockLLM do
  use Harness.Plugin

  @impl true
  def id, do: :llm

  @impl true
  def mount(ctx, _state) do
    provider = Harness.LLM.Mock.new([%{content: "ok", tool_calls: []}])
    {:ok, disposer} = Harness.Context.register_service(ctx, Harness.LLM, provider)
    {:ok, ctx, disposer}
  end
end

defmodule Harness.Sandbox.Local do
  @behaviour Harness.Sandbox
  defstruct []

  @impl true
  def exec(%__MODULE__{}, cmd, _opts), do: {:ok, %{cmd: cmd, status: 0, stdout: "", stderr: ""}}
  @impl true
  def read(%__MODULE__{}, _path), do: {:error, :not_found}
  @impl true
  def write(%__MODULE__{}, _path, _contents), do: :ok
end

defmodule Harness.Plugins.LocalSandbox do
  use Harness.Plugin

  @impl true
  def id, do: :sandbox

  @impl true
  def inject, do: []

  @impl true
  def mount(ctx, _state) do
    {:ok, disposer} =
      Harness.Context.register_service(ctx, Harness.Sandbox, %Harness.Sandbox.Local{})

    {:ok, ctx, disposer}
  end
end
