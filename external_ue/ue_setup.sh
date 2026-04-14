#!/usr/bin/env bash
set -euo pipefail

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

compose_up() {
  local dir="$1"
  docker compose --project-directory "$dir" -f "$dir/docker-compose.yaml" up -d
}

require_cmd docker
require_cmd ip

echo "[1/3] Preparing host bridge n3br"
if ! ip link show virbr0 >/dev/null 2>&1; then
  echo "virbr0 does not exist. Create it first, then re-run." >&2
  exit 1
fi

echo "[2/3] Ensuring Docker network n3br"
if ! docker network inspect n3br >/dev/null 2>&1; then
  docker network create -d macvlan \
  --subnet=10.10.3.0/24 \
  --gateway=10.10.3.254 \
  -o parent=virbr0 \
  n3br
fi

echo "[3/3] Starting bridge + UE containers"
compose_up "$BRIDGE_DIR"
compose_up "$UE1_DIR"
compose_up "$UE2_DIR"

echo "[3/3] Ready"
echo "Start UE processes with:"
echo "  docker compose --project-directory \"$UE1_DIR\" -f \"$UE1_DIR/docker-compose.yaml\" exec -it srsran_ue_external bash -lc '/srsran/config/start_ue.sh 1'"
echo "  docker compose --project-directory \"$UE2_DIR\" -f \"$UE2_DIR/docker-compose.yaml\" exec -it srsran_ue_external bash -lc '/srsran/config/start_ue.sh 2'"
echo ""
echo "Bridge socket check:"
echo "  docker exec srsran_zmq_bridge ss -tnp"
