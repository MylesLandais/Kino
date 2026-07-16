#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${KINO_NIX_SHELL:-}" && -z "${KINO_NIX_REEXEC:-}" ]] && command -v nix >/dev/null 2>&1; then
  exec env KINO_NIX_REEXEC=1 nix develop "path:$ROOT" -c "$ROOT/scripts/check-assets.sh"
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
