defmodule Adaptation.Pipeline.Worker do
  @moduledoc "Oban worker for offline train/eval/promote. Isolated from agent processes."

  use Oban.Worker,
    queue: :adaptation,
    max_attempts: 3,
    unique: [
      fields: [:worker, :args],
      keys: [:domain],
      states: [:available, :scheduled, :executing, :retryable, :suspended]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    domain = Map.fetch!(args, "domain")

    opts = [
      base_model: Map.get(args, "base_model", "base"),
      parent_adapter_id: args["parent_adapter_id"]
    ]

    case Adaptation.Pipeline.run(domain, opts) do
      {:ok, _adapter} -> :ok
      {:error, {:rejected, _adapter, _reason}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
