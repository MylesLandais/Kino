defmodule Harness.LLM do
  @moduledoc """
  Language-model seam. Consumers call this behaviour, never a provider.
  """

  @type t :: struct() | module()
  @type request :: map()
  @type response :: map()
  @type handler :: (term() -> any())

  @callback complete(t(), request()) :: {:ok, response()} | {:error, term()}
  @callback stream(t(), request(), handler()) :: {:ok, reference()} | {:error, term()}

  @optional_callbacks stream: 3

  def complete(ctx, request) do
    provider = Harness.Services.fetch!(ctx, __MODULE__)
    impl(provider).complete(provider, request)
  end

  defp impl(%mod{}), do: mod
  defp impl({mod, _state}), do: mod
  defp impl(mod) when is_atom(mod), do: mod
end

defmodule Harness.Sandbox do
  @moduledoc "Isolated execution world (local, Docker, Firecracker, …)."

  @type t :: struct() | module()

  @callback exec(t(), cmd :: [String.t()], opts :: keyword()) :: {:ok, term()} | {:error, term()}
  @callback read(t(), path :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback write(t(), path :: String.t(), contents :: binary()) :: :ok | {:error, term()}

  def exec(ctx, cmd, opts \\ []) do
    apply_service(ctx, :exec, [cmd, opts])
  end

  def read(ctx, path), do: apply_service(ctx, :read, [path])
  def write(ctx, path, contents), do: apply_service(ctx, :write, [path, contents])

  defp apply_service(ctx, fun, args) do
    provider = Harness.Services.fetch!(ctx, __MODULE__)
    apply(impl(provider), fun, [provider | args])
  end

  defp impl(%mod{}), do: mod
  defp impl({mod, _}), do: mod
  defp impl(mod) when is_atom(mod), do: mod
end

defmodule Harness.Environment do
  @moduledoc "Environment lifecycle seam. Firecracker is a provider, not the interface."

  @callback create(config :: map()) :: {:ok, term()} | {:error, term()}
  @callback start(environment()) :: :ok | {:error, term()}
  @callback pause(environment()) :: :ok | {:error, term()}
  @callback resume(environment()) :: :ok | {:error, term()}
  @callback snapshot(environment()) :: {:ok, term()} | {:error, term()}
  @callback restore(snapshot()) :: {:ok, term()} | {:error, term()}
  @callback destroy(environment()) :: :ok | {:error, term()}

  @type environment :: term()
  @type snapshot :: term()
end

defmodule Harness.ComputerUse do
  @moduledoc "Normalized desktop capability. Every action must emit a durable event."

  @type t :: struct() | module()

  @callback observe(t()) :: {:ok, map()} | {:error, term()}
  @callback screenshot(t()) :: {:ok, term()} | {:error, term()}
  @callback click(t(), coords :: {number(), number()}, opts :: keyword()) ::
              :ok | {:error, term()}
  @callback type(t(), text :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
  @callback key(t(), key :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
end

defmodule Harness.Lua do
  @moduledoc "Lua runtime seam. First provider may be a Rust/mlua worker; Luerl later."

  @type t :: struct() | module()
  @callback execute(t(), script :: String.t(), context :: map()) ::
              {:ok, term()} | {:error, term()}
end

defmodule Harness.Evaluator do
  @moduledoc "Evaluator plugin seam. Not part of the agent loop implementation."

  @type t :: struct() | module()
  @callback evaluate(t(), input :: map()) :: {:ok, Harness.Evaluation.t()} | {:error, term()}
end

defmodule Harness.Evaluation do
  defstruct [:score, :passed?, :failures, :evidence, metadata: %{}]

  @type t :: %__MODULE__{
          score: number() | nil,
          passed?: boolean(),
          failures: [term()],
          evidence: term(),
          metadata: map()
        }
end

defmodule Harness.Storage do
  @moduledoc "Artifact storage seam (object store for video, screenshots, traces)."

  @type t :: struct() | module()

  @callback put(t(), key :: String.t(), body :: iodata(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}
  @callback get(t(), key :: String.t()) :: {:ok, binary()} | {:error, term()}
end

defmodule Harness.Filesystem do
  @type t :: struct() | module()
  @callback read(t(), path :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback write(t(), path :: String.t(), body :: binary()) :: :ok | {:error, term()}
end

defmodule Harness.Subprocess do
  @type t :: struct() | module()
  @callback spawn(t(), cmd :: [String.t()], opts :: keyword()) :: {:ok, term()} | {:error, term()}
end
