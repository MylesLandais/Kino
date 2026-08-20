defmodule Adaptation.Graph do
  @moduledoc """
  SQL/PGQ queries over `maya_adaptation_graph`.

  Lineage is edges, not JSON. PostgreSQL 19beta1 does not support path
  quantifiers (`{1,n}`) on element patterns, so multi-generation walks are
  repeated one-hop `GRAPH_TABLE` matches — still graph queries, not joins
  over nested JSON.
  """

  alias Kino.Repo

  @doc "Walk an adapter back through `hops` generations of retraining."
  def lineage_walk(adapter_id, hops \\ 5) when hops >= 1 and hops <= 32 do
    walk_lineage([adapter_id], hops, MapSet.new([adapter_id]), [])
  end

  def trajectories_for_rejected_adapters(domain) when is_binary(domain) do
    sql = """
    SELECT adapter_id, adapter_version, trajectory_id, trajectory_bin
    FROM GRAPH_TABLE (
      maya_adaptation_graph
      MATCH (a IS adapter WHERE a.domain = $1 AND a.status = 'rejected')-[IS adapter_dataset_source]->(t IS trajectory)
      COLUMNS (a.id AS adapter_id, a.version AS adapter_version, t.id AS trajectory_id, t.bin AS trajectory_bin)
    )
    """

    graph_table(sql, [domain])
  end

  def available? do
    case Repo.query(
           "SELECT 1 FROM GRAPH_TABLE (maya_adaptation_graph MATCH (a IS adapter) COLUMNS (1 AS one)) LIMIT 1"
         ) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp walk_lineage(_frontier, 0, _seen, acc), do: {:ok, Enum.reverse(acc)}
  defp walk_lineage([], _hops, _seen, acc), do: {:ok, Enum.reverse(acc)}

  defp walk_lineage(frontier, hops, seen, acc) do
    Enum.reduce_while(frontier, {:ok, {[], seen, acc}}, fn id, {:ok, {next, seen, acc}} ->
      case parents_of(id) do
        {:ok, rows} ->
          {next, seen, acc} =
            Enum.reduce(rows, {next, seen, acc}, fn row, {next, seen, acc} ->
              parent_id = row["ancestor_id"] || row[:ancestor_id]

              if parent_id in seen do
                {next, seen, acc}
              else
                {[parent_id | next], MapSet.put(seen, parent_id), [row | acc]}
              end
            end)

          {:cont, {:ok, {next, seen, acc}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {next, seen, acc}} -> walk_lineage(Enum.uniq(next), hops - 1, seen, acc)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parents_of(adapter_id) do
    sql = """
    SELECT ancestor_id, ancestor_version, ancestor_status
    FROM GRAPH_TABLE (
      maya_adaptation_graph
      MATCH (child IS adapter WHERE child.id = $1::uuid)-[IS adapter_lineage]->(ancestor IS adapter)
      COLUMNS (ancestor.id AS ancestor_id, ancestor.version AS ancestor_version, ancestor.status AS ancestor_status)
    )
    """

    graph_table(sql, [dump_uuid(adapter_id)])
  end

  defp graph_table(sql, params) do
    case Repo.query(sql, params) do
      {:ok, %{columns: columns, rows: rows}} ->
        {:ok,
         Enum.map(rows, fn row ->
           columns
           |> Enum.zip(row)
           |> Map.new(fn {col, val} -> {col, normalize(val)} end)
         end)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize(id) when is_binary(id) and byte_size(id) == 16, do: Ecto.UUID.load!(id)
  defp normalize(other), do: other

  defp dump_uuid(id) when is_binary(id) and byte_size(id) == 16, do: id

  defp dump_uuid(id) when is_binary(id) do
    {:ok, dumped} = Ecto.UUID.dump(id)
    dumped
  end
end
