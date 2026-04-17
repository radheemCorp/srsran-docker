#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="${ROOT_DIR}/zmq_bridge"
UE1_DIR="${ROOT_DIR}/ue1"
UE2_DIR="${ROOT_DIR}/ue2"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

compose_up() {
  local dir="$1"
  docker compose --project-directory "$dir" -f "$dir/docker-compose.yaml" up -d
}

require_cmd docker
require_cmd ip


compose_up "$BRIDGE_DIR"
compose_up "$UE1_DIR"
compose_up "$UE2_DIR"

echo "[2/2] Ready"
echo "Start UE processes with:"
echo "  docker compose --project-directory \"$UE1_DIR\" -f \"$UE1_DIR/docker-compose.yaml\" exec -it srsran_ue_host bash -lc '/srsran/config/start_ue.sh 1'"
echo "  docker compose --project-directory \"$UE2_DIR\" -f \"$UE2_DIR/docker-compose.yaml\" exec -it srsran_ue_host bash -lc '/srsran/config/start_ue.sh 2'"
echo ""
echo "Bridge socket check:"
echo "  docker exec srsran_zmq_bridge ss -tnp"

docker compose --project-directory "/home/radr/tuilm/srsran-docker/external_ue/ue1" -f "/home/radr/tuilm/srsran-docker/external_ue/ue2/docker-compose.yaml" exec -it srsran_ue_host bash -lc '/srsran/config/start_ue.sh 2'