# shellcheck shell=bash
# Load Kino secrets from OpenBao into the process environment.
#
# Secrets live in OpenBao (CLI: `bao` from the Nix FHS shell). The repo does
# not store application credentials. Cursor Cloud may inject BAO_ADDR and
# BAO_TOKEN so this script can reach OpenBao; everything else is kv-get'd.
#
# No-op when address/path are unset so local PostgreSQL/dev still starts.
# Source this file; do not execute it.

kino_openbao_addr="${BAO_ADDR:-${VAULT_ADDR:-}}"
kino_openbao_token="${BAO_TOKEN:-${VAULT_TOKEN:-}}"
kino_openbao_path="${KINO_OPENBAO_PATH:-}"

if [[ -n "$kino_openbao_addr" ]]; then
  export BAO_ADDR="$kino_openbao_addr"
  export VAULT_ADDR="${VAULT_ADDR:-$kino_openbao_addr}"
fi
if [[ -n "$kino_openbao_token" ]]; then
  export BAO_TOKEN="$kino_openbao_token"
  export VAULT_TOKEN="${VAULT_TOKEN:-$kino_openbao_token}"
fi

if [[ -z "$kino_openbao_addr" || -z "$kino_openbao_path" ]]; then
  return 0 2>/dev/null || true
fi

if ! command -v bao >/dev/null 2>&1; then
  echo "openbao-env: bao is not on PATH; enter the Nix dev shell (nix develop / nix-shell) if you need OpenBao" >&2
  if [[ "${KINO_OPENBAO_REQUIRED:-}" == "1" ]]; then
    return 1 2>/dev/null || exit 1
  fi
  return 0 2>/dev/null || true
fi

kino_openbao_exports="$(
  bao kv get -format=json "$kino_openbao_path" | python3 -c '
import json, re, shlex, sys

doc = json.load(sys.stdin)
data = doc.get("data") or {}
if isinstance(data, dict) and isinstance(data.get("data"), dict) and "metadata" in data:
    data = data["data"]
if not isinstance(data, dict):
    sys.exit("openbao-env: unexpected kv payload")

safe = re.compile(r"^[A-Z][A-Z0-9_]*$")
for key, value in data.items():
    if not safe.fullmatch(key) or value is None:
        continue
    print(f"export {key}={shlex.quote(str(value))}")
'
)" || {
  echo "openbao-env: failed to read ${kino_openbao_path}" >&2
  if [[ "${KINO_OPENBAO_REQUIRED:-}" == "1" ]]; then
    return 1 2>/dev/null || exit 1
  fi
  return 0 2>/dev/null || true
}

eval "$kino_openbao_exports"
unset kino_openbao_exports kino_openbao_addr kino_openbao_token kino_openbao_path
