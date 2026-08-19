#!/usr/bin/env bash
# Start nix-daemon when systemd is not available (Cloud Agent VMs).
# Snapshots often keep a stale unix socket; always probe the daemon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/nix-env.sh"

SOCKET="/nix/var/nix/daemon-socket/socket"
DAEMON="${NIX_DAEMON_BIN:-/nix/var/nix/profiles/default/bin/nix-daemon}"

daemon_ready() {
  command -v nix >/dev/null 2>&1 && nix store info >/dev/null 2>&1
}

if daemon_ready; then
  exit 0
fi

if [[ ! -x "$DAEMON" ]]; then
  echo "nix-daemon not found at $DAEMON" >&2
  exit 1
fi

# Drop a snapshot-stale socket so the daemon can bind again.
if [[ -e "$SOCKET" ]] && ! daemon_ready; then
  if sudo -n true 2>/dev/null; then
    sudo -n rm -f "$SOCKET"
  else
    rm -f "$SOCKET" || true
  fi
fi

if sudo -n true 2>/dev/null; then
  sudo -n "$DAEMON" --daemon
else
  "$DAEMON" --daemon
fi

for _ in $(seq 1 50); do
  if daemon_ready; then
    exit 0
  fi
  sleep 0.2
done

echo "nix-daemon did not become reachable" >&2
tail -n 40 /tmp/nix-daemon.log >&2 || true
exit 1
