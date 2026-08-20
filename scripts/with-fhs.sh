#!/usr/bin/env bash
# Re-exec the given command inside the Kino Nix dev shell.
# Kept for backward compatibility; `with-fhs.sh` now delegates to `nix develop`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/nix-env.sh"
"$ROOT/scripts/ensure-nix-daemon.sh"

if [[ -z "${IN_NIX_SHELL:-}" ]] && command -v nix >/dev/null 2>&1; then
  exec nix develop --command "$@"
fi

exec "$@"
