#!/usr/bin/env bash
# Per-boot Cloud Agent start: Nix PostgreSQL 19 + migrations + SQL/PGQ graph.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/pg-env.sh"
# shellcheck disable=SC1091
source "$ROOT/scripts/openbao-env.sh"

"$ROOT/scripts/postgres.sh" start

# Hex packages can extract Erlang sources at Unix epoch. Mix then skips .erl
# compilation on later boots when the install script is not re-run.
if [[ -d "$ROOT/kino_app/deps" ]]; then
  find "$ROOT/kino_app/deps" -type f \( -name '*.erl' -o -name '*.yrl' -o -name '*.xrl' \) \
    -exec touch {} + 2>/dev/null || true
fi

cd "$ROOT/kino_app"
mix ecto.create
mix ecto.migrate

psql -h "$PGHOST" -p "$PGPORT" -d kino_dev -v ON_ERROR_STOP=1 -c \
  "SELECT COUNT(*) AS graph_probe FROM GRAPH_TABLE (ontology_graph MATCH (n IS ontology_node) COLUMNS (1 AS one));"
