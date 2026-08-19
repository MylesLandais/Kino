#!/usr/bin/env bash
# Start nix-daemon when systemd is not available (Cloud Agent VMs).
set -euo pipefail

SOCKET="/nix/var/nix/daemon-socket/socket"
DAEMON="${NIX_DAEMON_BIN:-/nix/var/nix/profiles/default/bin/nix-daemon}"

if [[ -S "$SOCKET" ]]; then
  exit 0
fi

if [[ ! -x "$DAEMON" ]]; then
  echo "nix-daemon not found at $DAEMON" >&2
  exit 1
fi

if sudo -n true 2>/dev/null; then
  sudo -n -b "$DAEMON" --daemon >/tmp/nix-daemon.log 2>&1 || true
else
  nohup "$DAEMON" --daemon >/tmp/nix-daemon.log 2>&1 &
  disown || true
fi

for _ in $(seq 1 50); do
  if [[ -S "$SOCKET" ]]; then
    exit 0
  fi
  sleep 0.2
done

echo "nix-daemon did not create $SOCKET" >&2
tail -n 40 /tmp/nix-daemon.log >&2 || true
exit 1
