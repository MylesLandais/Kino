#!/usr/bin/env bash
# Re-exec the given command inside the Kino FHS Nix shell.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/nix-env.sh"
"$ROOT/scripts/ensure-nix-daemon.sh"

if [[ -z "${KINO_FHS:-}" ]] && command -v nix >/dev/null 2>&1; then
  exec nix run "path:$ROOT#fhs" -- "$@"
fi

exec "$@"
