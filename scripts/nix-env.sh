# shellcheck shell=bash
# Source this file to put Nix on PATH in non-interactive cloud/agent shells.

if command -v nix >/dev/null 2>&1; then
  return 0 2>/dev/null || true
fi

if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
elif [[ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
  # shellcheck disable=SC1091
  . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
elif [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
fi
