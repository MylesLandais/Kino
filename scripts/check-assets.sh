#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/nix-env.sh"
"$ROOT/scripts/ensure-nix-daemon.sh"

if [[ -z "${KINO_FHS:-}" && -z "${KINO_NIX_REEXEC:-}" ]] && command -v nix >/dev/null 2>&1; then
  exec env KINO_NIX_REEXEC=1 nix run "path:$ROOT#fhs" -- "$ROOT/scripts/check-assets.sh"
fi

cd "$ROOT/kino_app"
mix assets.build

CSS="priv/static/assets/css/app.css"
JS="priv/static/assets/js/app.js"

test -s "$CSS"
test -s "$JS"
rg -q '\.kino-shell' "$CSS"
rg -q '\.chat-panel' "$CSS"

echo "Kino assets verified: $CSS and $JS"
