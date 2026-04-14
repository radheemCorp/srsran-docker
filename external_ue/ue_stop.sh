#!/usr/bin/env bash
set -euo pipefail

# Determine directories relative to script location
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="${ROOT_DIR}/host_ue_bridge"
UE1_DIR="${ROOT_DIR}/host_ue1"
UE2_DIR="${ROOT_DIR}/host_ue2"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

compose_down() {
  local dir="$1"
  if [ -d "$dir" ]; then
    echo "Stopping containers in $dir..."
    docker compose --project-directory "$dir" -f "$dir/docker-compose.yaml" down
  else
    echo "Warning: Directory $dir not found, skipping."
  fi
}

# Ensure docker is available
require_cmd docker

echo "[1/2] Shutting down UE and Bridge containers"

# Shutdown in reverse order of startup
compose_down "$UE2_DIR"
compose_down "$UE1_DIR"
compose_down "$BRIDGE_DIR"

echo "[2/2] Cleanup complete"
echo "Note: Docker network 'n3br' and host bridge 'virbr0' were preserved."