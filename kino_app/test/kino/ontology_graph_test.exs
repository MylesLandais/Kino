defmodule Kino.OntologyGraphTest do
  use Kino.DataCase, async: false

  alias Kino.Repo

  test "PostgreSQL 19 SQL/PGQ can query the ontology property graph" do
    %{rows: [[version]]} = Repo.query!("SHOW server_version_num")

    if String.to_integer(version) >= 19_0000 do
      assert {:ok, _} =
               Repo.query("""
               SELECT COUNT(*) AS n
               FROM GRAPH_TABLE (
                 ontology_graph
                 MATCH (n IS ontology_node)
                 COLUMNS (1 AS one)
               )
               """)
    else
      flunk("Kino requires PostgreSQL 19+ for SQL/PGQ (got server_version_num=#{version})")
    end
  end
end
