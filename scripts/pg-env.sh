# shellcheck shell=bash
# Shared PostgreSQL 19 unix-socket location for Kino.

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/kino"
export PGDATA="${KINO_PGDATA:-${PGDATA:-$STATE/postgresql}}"
export PGHOST="${KINO_PGHOST:-${PGHOST:-$STATE/postgresql-run}}"
export PGPORT="${PGPORT:-5432}"
export KINO_PGDATA="$PGDATA"
export KINO_PGHOST="$PGHOST"
