#!/usr/bin/env bash
set -euo pipefail

# Create Docker macvlan networks for 5G interfaces (N2, N3, N4, N6).
# Defaults are chosen to match docs/networks.md but can be overridden
# by exporting environment variables before running this script.

# Host physical interface used as macvlan parent
PARENT_IF=${PARENT_IF:-eth3}

# Network names and subnets (can be overridden)
N2_NAME=${N2_NAME:-n2}
N2_SUBNET=${N2_SUBNET:-10.53.1.0/24}
N2_GW=${N2_GW:-10.53.1.1}

N3_NAME=${N3_NAME:-n3}
N3_SUBNET=${N3_SUBNET:-10.53.2.0/24}
N3_GW=${N3_GW:-10.53.2.1}


N6_NAME=${N6_NAME:-n6}
N6_SUBNET=${N6_SUBNET:-10.41.0.0/24}
N6_GW=${N6_GW:-10.41.0.1}

# Metrics network (bridge, not macvlan)
METRICS_NAME=${METRICS_NAME:-metrics}
METRICS_SUBNET=${METRICS_SUBNET:-172.19.1.0/24}
METRICS_GW=${METRICS_GW:-172.19.1.1}

DOCKER_OPTS_PARENT="-o parent=${PARENT_IF} -o macvlan_mode=bridge"

create_macvlan_network() {
  local name=$1 subnet=$2 gateway=$3
  if docker network inspect "$name" >/dev/null 2>&1; then
    echo "Docker network '$name' already exists — skipping"
    return 0
  fi

  echo "Creating macvlan network '$name' (subnet=$subnet gateway=$gateway parent=$PARENT_IF)"
  docker network create -d macvlan \
    --subnet="$subnet" \
    --gateway="$gateway" \
    $DOCKER_OPTS_PARENT \
    "$name"
}

remove_macvlan_network() {
  local name=$1
  if docker network inspect "$name" >/dev/null 2>&1; then
    echo "Removing docker network '$name'"
    docker network rm "$name" || {
      echo "Failed to remove network '$name'" >&2
      return 1
    }
  else
    echo "Docker network '$name' does not exist — skipping"
  fi
}

create_bridge_network() {
  local name=$1 subnet=$2 gateway=$3
  if docker network inspect "$name" >/dev/null 2>&1; then
    echo "Docker network '$name' already exists — skipping"
    return 0
  fi

  echo "Creating bridge network '$name' (subnet=$subnet gateway=$gateway)"
  docker network create --driver bridge \
    --subnet="$subnet" \
    --gateway="$gateway" \
    "$name"
}

remove_bridge_network() {
  local name=$1
  remove_macvlan_network "$name"
}

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  create    Create all macvlan networks (default)
  remove    Remove all macvlan networks
  help      Show this help

Environment overrides:
  PARENT_IF, N2_NAME, N2_SUBNET, N2_GW, N3_NAME, N3_SUBNET, N3_GW,
  N6_NAME, N6_SUBNET, N6_GW, METRICS_NAME, METRICS_SUBNET, METRICS_GW
EOF
}

# Validate parent interface exists
if ! ip link show "$PARENT_IF" >/dev/null 2>&1; then
  echo "Parent interface '$PARENT_IF' not found. Export PARENT_IF to override (default eth3)." >&2
  exit 1
fi

action=${1:-create}

case "$action" in
  create)
    create_macvlan_network "$N2_NAME" "$N2_SUBNET" "$N2_GW"
    create_macvlan_network "$N3_NAME" "$N3_SUBNET" "$N3_GW"
    create_macvlan_network "$N6_NAME" "$N6_SUBNET" "$N6_GW"
    create_bridge_network "$METRICS_NAME" "$METRICS_SUBNET" "$METRICS_GW"
    echo "Done. Networks created (or already existed): $N2_NAME $N3_NAME $N6_NAME $METRICS_NAME"
    ;;
  remove)
    remove_macvlan_network "$N6_NAME"
    remove_macvlan_network "$N3_NAME"
    remove_macvlan_network "$N2_NAME"
    remove_bridge_network "$METRICS_NAME"
    echo "Done. Networks removed (if they existed): $N2_NAME $N3_NAME $N6_NAME $METRICS_NAME"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $action" >&2
    usage
    exit 2
    ;;
esac