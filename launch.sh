#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/nix-env.sh"
"$ROOT/scripts/ensure-nix-daemon.sh"

if [[ -z "${KINO_FHS:-}" && -z "${KINO_NIX_REEXEC:-}" ]] && command -v nix >/dev/null 2>&1; then
  exec env KINO_NIX_REEXEC=1 nix run "path:$ROOT#fhs" -- "$ROOT/launch.sh" "$@"
fi

if ! command -v mix >/dev/null 2>&1; then
  echo "Kino requires the Nix FHS shell (Elixir). Install Nix, then run ./launch.sh again." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/openbao-env.sh"
"$ROOT/scripts/postgres.sh" start

cd "$ROOT/kino_app"
mix setup

if [[ "${1:-}" == "--setup-only" ]]; then
  exit 0
fi

exec mix phx.server "$@"
