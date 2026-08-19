#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/nix-env.sh"
# shellcheck disable=SC1091
source "$ROOT/scripts/pg-env.sh"

if ! command -v initdb >/dev/null 2>&1 || ! command -v pg_ctl >/dev/null 2>&1; then
  echo "PostgreSQL 19 tools are not on PATH. Enter the Kino FHS shell first:" >&2
  echo "  nix run path:$ROOT#fhs -- $0 ${1:-start}" >&2
  exit 1
fi

mkdir -p "$PGDATA" "$PGHOST"

if [[ ! -f "$PGDATA/PG_VERSION" ]]; then
  initdb \
    --locale=C.UTF-8 \
    --encoding=UTF8 \
    --auth-local=peer \
    --auth-host=scram-sha-256 \
    -D "$PGDATA"

  cat >> "$PGDATA/postgresql.conf" <<EOF
listen_addresses = ''
unix_socket_directories = '$PGHOST'
unix_socket_permissions = 0770
port = $PGPORT
EOF
fi

running() {
  pg_ctl -D "$PGDATA" status >/dev/null 2>&1
}

cmd="${1:-start}"
case "$cmd" in
  start)
    if running; then
      echo "PostgreSQL already running (PGHOST=$PGHOST PGDATA=$PGDATA)"
    else
      pg_ctl \
        -D "$PGDATA" \
        -l "$PGDATA/postgres.log" \
        -o "-k $PGHOST -c listen_addresses='' -p $PGPORT" \
        start
    fi
    for _ in $(seq 1 50); do
      if pg_isready -h "$PGHOST" -p "$PGPORT" -q; then
        break
      fi
      sleep 0.2
    done
    if ! pg_isready -h "$PGHOST" -p "$PGPORT" -q; then
      echo "PostgreSQL did not become ready. Last log lines:" >&2
      tail -n 40 "$PGDATA/postgres.log" >&2 || true
      exit 1
    fi
    createdb -h "$PGHOST" -p "$PGPORT" kino_dev 2>/dev/null || true
    createdb -h "$PGHOST" -p "$PGPORT" kino_test 2>/dev/null || true
    echo "PostgreSQL ready at unix socket $PGHOST (port $PGPORT)"
    ;;
  stop)
    if running; then
      pg_ctl -D "$PGDATA" stop
    else
      echo "PostgreSQL is not running"
    fi
    ;;
  status)
    pg_ctl -D "$PGDATA" status || true
    pg_isready -h "$PGHOST" -p "$PGPORT"
    ;;
  *)
    echo "usage: $0 start|stop|status" >&2
    exit 1
    ;;
esac
