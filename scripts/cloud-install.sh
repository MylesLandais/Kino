#!/usr/bin/env bash
# Idempotent Cloud Agent install: Hex deps and assets only. No servers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/kino_app"

mix local.hex --force
mix local.rebar --force
mix deps.get
mix deps.compile
npm install --prefix assets
mix assets.setup
mix assets.build
