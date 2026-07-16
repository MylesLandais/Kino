#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "${KINO_NIX_SHELL:-}" && -z "${KINO_NIX_REEXEC:-}" ]] && command -v nix >/dev/null 2>&1; then
  exec env KINO_NIX_REEXEC=1 nix develop "path:$ROOT" -c "$ROOT/launch.sh" "$@"
fi

if ! command -v mix >/dev/null 2>&1; then
  echo "Kino requires Elixir. Install Nix or run this script from the Kino dev shell." >&2
  exit 1
fi

if ! pg_isready -q; then
  echo "PostgreSQL is not accepting local Unix-socket connections." >&2
  echo "Start the host PostgreSQL service, then run ./launch.sh again." >&2
  exit 1
fi

cd "$ROOT/kino_app"
mix setup

if [[ "${1:-}" == "--setup-only" ]]; then
  exit 0
fi

exec mix phx.server "$@"
