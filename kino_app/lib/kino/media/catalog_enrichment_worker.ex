defmodule Kino.Media.CatalogEnrichmentWorker do
  use Oban.Worker,
    queue: :catalog,
    max_attempts: 3,
    unique: [period: 604_800, fields: [:worker, :args]]

  @impl true
  def perform(%Oban.Job{args: %{"track_id" => track_id, "platform" => platform}}) do
    Kino.Media.SetBroker.enrich_catalog(track_id, platform)
  end
end
