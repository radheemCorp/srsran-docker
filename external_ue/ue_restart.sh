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

compose_restart() {
  local dir="$1"
  docker compose --project-directory "$dir" -f "$dir/docker-compose.yaml" restart
}

exec_in_service() {
  local dir="$1"
  local service="$2"
  local cmd="$3"
  docker compose --project-directory "$dir" -f "$dir/docker-compose.yaml" exec -T "$service" bash -lc "$cmd"
}

usage() {
  cat <<'EOF'
Usage: ./ue_restart.sh [target]

Targets:
  all      restart bridge + ue1 + ue2 (default)
  ue1      restart ue1 only
  ue2      restart ue2 only
  bridge   restart bridge only

This script restarts containers only.
Start UE processes manually after restart:
  /srsran/config/start_ue.sh 1 (in ue1 container)
  /srsran/config/start_ue.sh 2 (in ue2 container)
EOF
}

TARGET="${1:-all}"

if [[ "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd docker

case "$TARGET" in
  all)
    echo "Stopping UE processes if present"
    exec_in_service "$UE1_DIR" srsran_ue_external "pkill -f srsue || true" || true
    exec_in_service "$UE2_DIR" srsran_ue_external "pkill -f srsue || true" || true

    echo "Restarting bridge, ue1, ue2 containers"
    compose_restart "$BRIDGE_DIR"
    compose_restart "$UE1_DIR"
    compose_restart "$UE2_DIR"
    ;;
  ue1)
    echo "Stopping UE1 process if present"
    exec_in_service "$UE1_DIR" srsran_ue_external "pkill -f srsue || true" || true
    echo "Restarting ue1 container"
    compose_restart "$UE1_DIR"
    ;;
  ue2)
    echo "Stopping UE2 process if present"
    exec_in_service "$UE2_DIR" srsran_ue_external "pkill -f srsue || true" || true
    echo "Restarting ue2 container"
    compose_restart "$UE2_DIR"
    ;;
  bridge)
    echo "Restarting bridge container"
    compose_restart "$BRIDGE_DIR"
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    usage
    exit 1
    ;;
esac

echo "Done."
echo "UE start commands:"
echo "  docker compose --project-directory \"$UE1_DIR\" -f \"$UE1_DIR/docker-compose.yaml\" exec -it srsran_ue_external bash -lc '/srsran/config/start_ue.sh 1'"
echo "  docker compose --project-directory \"$UE2_DIR\" -f \"$UE2_DIR/docker-compose.yaml\" exec -it srsran_ue_external bash -lc '/srsran/config/start_ue.sh 2'"
