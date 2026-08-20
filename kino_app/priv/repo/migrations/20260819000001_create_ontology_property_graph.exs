defmodule Kino.Repo.Migrations.CreateOntologyPropertyGraph do
  use Ecto.Migration

  def up do
    execute("""
    DO $migration$
    BEGIN
      IF current_setting('server_version_num')::int >= 190000 THEN
        EXECUTE $graph$
          CREATE PROPERTY GRAPH ontology_graph
            VERTEX TABLES (
              ontology_node KEY (id) LABEL ontology_node PROPERTIES ALL COLUMNS
            )
            EDGE TABLES (
              ontology_edge KEY (source_id, target_id, edge_type, dimension)
                SOURCE KEY (source_id) REFERENCES ontology_node (id)
                DESTINATION KEY (target_id) REFERENCES ontology_node (id)
                LABEL ontology_edge
                PROPERTIES ALL COLUMNS
            )
        $graph$;
      END IF;
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
    END
    $migration$;
    """)
  end

  def down do
    execute("""
    DO $migration$
    BEGIN
      IF current_setting('server_version_num')::int >= 190000 THEN
        EXECUTE 'DROP PROPERTY GRAPH IF EXISTS ontology_graph';
      END IF;
    END
    $migration$;
    """)
  end
end
