#!/usr/bin/env bash
# Idempotent Cloud Agent install: Hex deps and assets only. No servers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/kino_app"

mix local.hex --force
mix local.rebar --force
mix deps.get
# Hex tarballs can extract Erlang sources at Unix epoch. Mix then skips .erl
# compilation because the sources do not look newer than missing .beam files.
find deps -type f \( -name '*.erl' -o -name '*.yrl' -o -name '*.xrl' \) -exec touch {} + 2>/dev/null || true
mix deps.compile
npm install --prefix assets
mix assets.setup
mix assets.build
