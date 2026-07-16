defmodule Kino.Media.SetEnrichmentWorker do
  use Oban.Worker,
    queue: :enrichment,
    max_attempts: 5,
    unique: [period: 86_400, fields: [:worker, :args]]

  @impl true
  def perform(%Oban.Job{args: %{"media_asset_id" => id}}) do
    id |> Kino.Media.get_asset!() |> Kino.Media.SetBroker.ingest_asset()
  end
end
