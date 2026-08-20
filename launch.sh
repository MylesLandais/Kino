#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/nix-env.sh"
"$ROOT/scripts/ensure-nix-daemon.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Run Kino (Phoenix) via the Nix dev shell / flake.

Options:
  --setup-only   Install deps, create/migrate DB, build assets, then exit
  --release      Run the Nix-built release (nix run .#kino_app) instead of mix phx.server
  --docker       Build and run the docker image (requires docker)
  --help, -h     Show this help

Examples:
  ./launch.sh
  ./launch.sh --setup-only
  ./launch.sh --release
  nix develop -c ./launch.sh
  nix run .#kino_app
EOF
}

# Re-exec inside `nix develop` if not already in a Nix shell and nix is available
if [[ -z "${IN_NIX_SHELL:-}" && -z "${KINO_NIX_REEXEC:-}" ]] && command -v nix >/dev/null 2>&1; then
  exec env KINO_NIX_REEXEC=1 nix develop --command "$ROOT/launch.sh" "$@"
fi

if ! command -v mix >/dev/null 2>&1; then
  echo "Kino requires the Nix dev shell (Elixir). Run 'nix develop' or 'direnv allow' first." >&2
  exit 1
fi

# Parse args
MODE="dev"
for arg in "$@"; do
  case "$arg" in
    --setup-only) MODE="setup-only" ;;
    --release) MODE="release" ;;
    --docker) MODE="docker" ;;
    --help|-h) usage; exit 0 ;;
    *) ;;
  esac
done

# Load shared PG env first so PGHOST/PGDATA propagate to this shell and to mix.
# postgres.sh also sources it internally, but sourcing here ensures `mix` sees it.
# shellcheck disable=SC1091
source "$ROOT/scripts/pg-env.sh"
# Load secrets (no-op if OpenBao not configured) and start Postgres
# shellcheck disable=SC1091
source "$ROOT/scripts/openbao-env.sh"
"$ROOT/scripts/postgres.sh" start

case "$MODE" in
  setup-only)
    cd "$ROOT/kino_app"
    mix setup
    ;;

  release)
    # Prefer the Nix-built release when available; fallback to mix release
    if command -v nix >/dev/null 2>&1; then
      echo "Running Nix release via nix run .#kino_app..."
      exec nix run "path:$ROOT#kino_app" -- start
    else
      cd "$ROOT/kino_app"
      mix setup
      exec mix phx.server
    fi
    ;;

  docker)
    if ! command -v docker >/dev/null 2>&1; then
      echo "Docker is required for --docker mode" >&2
      exit 1
    fi
    echo "Building docker image via nix build .#kino_app-docker..."
    image="$(nix build "path:$ROOT#kino_app-docker" --print-out-paths --no-link 2>&1 | grep -E '^/nix/store' | tail -n1)"
    if [[ -z "$image" ]]; then
      image="$(nix build "path:$ROOT#kino_app-dockerImage" --print-out-paths --no-link 2>&1 | grep -E '^/nix/store' | tail -n1)"
    fi
    if [[ -z "$image" ]]; then
      echo "Failed to build docker image" >&2; exit 1
    fi
    echo "Loading image $image into docker..."
    docker load < "$image"
    echo "Running kino_app:latest (docker)..."
    # Note: PGHOST as unix socket ($HOME/.local/state/kino/postgresql-run) is not usable inside docker; use DATABASE_URL for --docker
    if [[ "$PGHOST" == /* ]] && [[ -z "${DATABASE_URL:-}" ]]; then
      echo "Warning: PGHOST=$PGHOST is a host unix socket, not reachable inside docker. Set DATABASE_URL for --docker." >&2
    fi
    exec docker run --rm -p 4000:4000 --env-file <(env | grep -E '^(SECRET_KEY_BASE|DATABASE_URL|PGHOST|PGPORT|BAO_|VAULT_)') kino_app:latest
    ;;

  dev)
    cd "$ROOT/kino_app"
    mix setup
    exec mix phx.server
    ;;

  *)
    echo "Unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac
