defmodule Adaptation.Thresholds do
  @moduledoc """
  Per-domain promotion gates. OSRS combat delta is not a coding-agent pass.
  """

  import Ecto.Query
  alias Adaptation.DomainThreshold
  alias Kino.Repo

  def suites(domain) do
    from(t in DomainThreshold, where: t.domain == ^domain, select: t.benchmark_suite)
    |> Repo.all()
    |> Enum.uniq()
  end

  def pass?(domain, metrics) when is_map(metrics) do
    thresholds = Repo.all(from(t in DomainThreshold, where: t.domain == ^domain))

    if thresholds == [] do
      {:error, {:no_thresholds, domain}}
    else
      failures =
        Enum.reject(thresholds, fn row ->
          value = metric_value(metrics, row.benchmark_suite, row.metric)
          compare(value, row.comparison, row.threshold)
        end)

      if failures == [] do
        :ok
      else
        {:error, {:below_threshold, Enum.map(failures, &{&1.benchmark_suite, &1.metric})}}
      end
    end
  end

  defp metric_value(metrics, suite, metric) do
    suite_metrics = Map.get(metrics, suite) || Map.get(metrics, to_string(suite)) || %{}

    Map.get(suite_metrics, metric) ||
      Map.get(suite_metrics, String.to_atom(metric)) ||
      get_in(suite_metrics, [Access.key("score")])
  end

  defp compare(nil, _op, _threshold), do: false
  defp compare(value, "gte", threshold), do: value >= threshold
  defp compare(value, "gt", threshold), do: value > threshold
  defp compare(value, "lte", threshold), do: value <= threshold
  defp compare(value, "lt", threshold), do: value < threshold
end
