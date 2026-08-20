#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/nix-env.sh"
"$ROOT/scripts/ensure-nix-daemon.sh"

APPS=("$@")
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: $(basename "$0") [app...]

Build Nix docker images and load them into the Docker daemon.

  $(basename "$0")              # all apps: kino_app harness dnd_app image_graph_vectorizer
  $(basename "$0") kino_app     # single app
  $(basename "$0") --help       # this help

Images are built via \`nix build .#<app>-docker\` (alias .#<app>-dockerImage)
using nix/mkImage.nix + default.nix passthru.dockerImage.

Inside \`nix develop\`, also available as \`docker-load\` command.
EOF
  exit 0
fi

if [[ ${#APPS[@]} -eq 0 ]]; then
  APPS=(kino_app harness dnd_app image_graph_vectorizer)
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "Nix is required to build images" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to load images (docker CLI not found)" >&2
  exit 1
fi

for app in "${APPS[@]}"; do
  clean_app="${app#docker-}"
  clean_app="${clean_app%-docker}"
  clean_app="${clean_app%-dockerImage}"

  attr="${clean_app}-docker"

  echo "==> Building ${clean_app} docker image (nix build .#${attr})..."
  # Use nix build with --print-out-paths; capture last line that looks like /nix/store/...
  image_path="$(nix build "path:$ROOT#${attr}" --print-out-paths --no-link 2>&1 | grep -E '^/nix/store' | tail -n1)"
  if [[ -z "$image_path" ]]; then
    # Fallback without path: prefix (when running from repo root)
    image_path="$(nix build ".#${attr}" --print-out-paths --no-link 2>&1 | grep -E '^/nix/store' | tail -n1)"
  fi

  if [[ -z "$image_path" || ! -e "$image_path" ]]; then
    # Try -dockerImage alias
    attr_alias="${clean_app}-dockerImage"
    echo "Retrying with alias ${attr_alias}..."
    image_path="$(nix build "path:$ROOT#${attr_alias}" --print-out-paths --no-link 2>&1 | grep -E '^/nix/store' | tail -n1)"
    if [[ -z "$image_path" ]]; then
      image_path="$(nix build ".#${attr_alias}" --print-out-paths --no-link 2>&1 | grep -E '^/nix/store' | tail -n1)"
    fi
  fi

  if [[ -z "$image_path" || ! -e "$image_path" ]]; then
    echo "Failed to build image for $clean_app (path $image_path not found)" >&2
    exit 1
  fi

  echo "==> Loading ${clean_app} into docker daemon (docker load < $image_path)..."
  # buildLayeredImage produces a tar file; docker load expects tar on stdin
  if [[ -f "$image_path" ]]; then
    docker load < "$image_path"
  elif [[ -d "$image_path" ]]; then
    tar_file="$(find "$image_path" -maxdepth 1 -name "*.tar*" | head -n1)"
    if [[ -n "$tar_file" ]]; then
      docker load < "$tar_file"
    else
      echo "Could not find tar for $clean_app in $image_path" >&2
      ls -la "$image_path" >&2
      exit 1
    fi
  else
    echo "Unexpected image path type for $clean_app: $image_path" >&2
    exit 1
  fi

  echo "✓ ${clean_app} loaded"
done

echo "All requested images loaded. Available images:"
docker images | grep -E "kino_app|harness|dnd_app|image_graph_vectorizer" || true
