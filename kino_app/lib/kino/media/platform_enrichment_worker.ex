defmodule Kino.Media.PlatformEnrichmentWorker do
  use Oban.Worker,
    queue: :enrichment,
    max_attempts: 4,
    unique: [period: 86_400, fields: [:worker, :args]]

  @impl true
  def perform(%Oban.Job{args: %{"track_id" => track_id, "platform" => platform}}) do
    Kino.Media.SetBroker.enrich_platform(track_id, platform)
  end
end
