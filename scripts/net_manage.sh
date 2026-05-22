#!/usr/bin/env bash
set -euo pipefail

# Create Docker macvlan networks for 5G interfaces (N2, N3, N4, N6).
# Defaults are chosen to match docs/networks.md but can be overridden
# by exporting environment variables before running this script.

# Host physical interface used as macvlan parent
PARENT_IF=${PARENT_IF:-enp2s0}

# Network names and subnets (can be overridden)
N2_NAME=${N2_NAME:-n2}
N2_SUBNET=${N2_SUBNET:-10.53.1.0/24}
N2_GW=${N2_GW:-10.53.1.1}

N3_NAME=${N3_NAME:-n3}
N3_SUBNET=${N3_SUBNET:-10.10.3.0/24}
N3_GW=${N3_GW:-10.10.3.236}


N6_NAME=${N6_NAME:-n6}
N6_SUBNET=${N6_SUBNET:-10.41.0.0/24}
N6_GW=${N6_GW:-10.41.0.1}

# Metrics network (bridge, not macvlan)
METRICS_NAME=${METRICS_NAME:-metrics}
METRICS_SUBNET=${METRICS_SUBNET:-172.19.1.0/24}
METRICS_GW=${METRICS_GW:-172.19.1.1}

# RIC network (bridge)
RIC_NAME=${RIC_NAME:-ric_network}
RIC_DOCKER_NAME=${RIC_DOCKER_NAME:-oran-sc-ric}
RIC_SUBNET=${RIC_SUBNET:-${RIC_NETWORK_SUBNET:-10.0.2.0/24}}
RIC_GW=${RIC_GW:-10.0.2.1}

# N3 bridge macvlan (parent for UE macvlan networks)
N3BR_NAME=${N3BR_NAME:-n3br}
N3BR_SUBNET=${N3BR_SUBNET:-10.10.3.0/24}
N3BR_GW=${N3BR_GW:-10.10.3.254}

# UE macvlan (children of n3br)
UE_N3_NAME=${UE_N3_NAME:-ue_n3}

# Host-side helper macvlan (so host can reach macvlan networks)
HOST_MACVLAN_IF=${HOST_MACVLAN_IF:-macvlan_ran}
HOST_MACVLAN_IP=${HOST_MACVLAN_IP:-10.53.1.254/24}

# PDN aggregate route (via Open5GS on ran)
PDN_ROUTE_SUBNET=${PDN_ROUTE_SUBNET:-10.45.0.0/16}
PDN_ROUTE_VIA=${PDN_ROUTE_VIA:-10.53.1.2}

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

create_ric_network() {
  local name=${RIC_NAME} subnet=${RIC_SUBNET} gateway=${RIC_GW}
  local docker_name="${RIC_DOCKER_NAME:-oran-sc-ric}"
  if docker network inspect "$docker_name" >/dev/null 2>&1; then
    echo "Docker network '$docker_name' ($name) already exists — skipping"
    return 0
  fi

  echo "Creating bridge network '$name' (docker_name=$docker_name subnet=$subnet gateway=$gateway)"
  docker network create --driver bridge \
    --subnet="$subnet" \
    --gateway="$gateway" \
    "$docker_name"
}

remove_ric_network() {
  local docker_name="${RIC_DOCKER_NAME:-oran-sc-ric}"
  remove_macvlan_network "$docker_name"
}

# Create a child macvlan network under the n3br bridge parent
create_macvlan_child_network() {
  local name=${UE_N3_NAME} subnet=${N3BR_SUBNET} gateway=${N3BR_GW} parent=${N3BR_NAME}
  if docker network inspect "$name" >/dev/null 2>&1; then
    echo "Docker network '$name' already exists — skipping"
    return 0
  fi

  echo "Creating macvlan child network '$name' (subnet=$subnet gateway=$gateway parent=$parent)"
  docker network create -d macvlan \
    --subnet="$subnet" \
    --gateway="$gateway" \
    -o parent="$parent" \
    -o macvlan_mode=bridge \
    "$name"
}

remove_macvlan_child_network() {
  local name=${UE_N3_NAME}
  remove_macvlan_network "$name"
}

create_host_macvlan() {
  local ifname=${HOST_MACVLAN_IF} ipaddr=${HOST_MACVLAN_IP}
  if ip link show "$ifname" >/dev/null 2>&1; then
    echo "Host macvlan interface '$ifname' already exists — skipping"
  else
    echo "Creating host macvlan interface '$ifname' linked to $PARENT_IF"
    sudo ip link add "$ifname" link "$PARENT_IF" type macvlan mode bridge
  fi

  if ip addr show dev "$ifname" | grep -q "${ipaddr%/*}"; then
    echo "IP $ipaddr already assigned to $ifname — skipping"
  else
    echo "Assigning $ipaddr to $ifname"
    sudo ip addr add "$ipaddr" dev "$ifname" || true
  fi

  sudo ip link set "$ifname" up

  # add PDN route via open5gs if missing
  if ip route show | grep -q "${PDN_ROUTE_SUBNET}"; then
    echo "Route for ${PDN_ROUTE_SUBNET} already exists — skipping"
  else
    echo "Adding route ${PDN_ROUTE_SUBNET} via ${PDN_ROUTE_VIA} dev ${ifname}"
    sudo ip route add ${PDN_ROUTE_SUBNET} via ${PDN_ROUTE_VIA} dev ${ifname}
  fi
}

remove_host_macvlan() {
  local ifname=${HOST_MACVLAN_IF}
  # remove PDN route if present
  if ip route show | grep -q "${PDN_ROUTE_SUBNET}"; then
    echo "Removing route ${PDN_ROUTE_SUBNET}"
    sudo ip route del ${PDN_ROUTE_SUBNET} || true
  else
    echo "Route ${PDN_ROUTE_SUBNET} not present — skipping"
  fi

  if ip link show "$ifname" >/dev/null 2>&1; then
    echo "Deleting host macvlan interface '$ifname'"
    sudo ip link delete "$ifname" || true
  else
    echo "Host macvlan interface '$ifname' does not exist — skipping"
  fi
}


# List all Docker networks with their subnets
dnet() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker: command not found" >&2
    return 1
  fi

  printf "%-30s %-30s %-40s\n" "NETWORK" "IPv4 SUBNETS" "IPv6 SUBNETS"
  printf "%-30s %-30s %-40s\n" "-------" "------------" "------------"

  docker network ls --format '{{.Name}}' | while IFS= read -r name; do
    subnets=$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}|{{end}}' "$name" 2>/dev/null || echo "")
    IFS='|' read -r -a parts <<< "$subnets"

    ipv4=""
    ipv6=""
    for p in "${parts[@]}"; do
      [ -z "$p" ] && continue
      if [[ "$p" == *:* ]]; then
        ipv6+="$p "
      else
        ipv4+="$p "
      fi
    done

    [ -z "$ipv4" ] && ipv4="-"
    [ -z "$ipv6" ] && ipv6="-"

    printf "%-30s %-30s %-40s\n" "$name" "$ipv4" "$ipv6"
  done
}

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  init           Create ALL required Docker and host networks (recommended default)
  create         Same as init — creates all macvlan networks and enables NAT
  remove         Remove ALL networks and disable NAT
  dnet           List all Docker networks with their subnets
  help           Show this help

Networks created by init:
  $N2_NAME ($N2_SUBNET)              N2 — macvlan (5GC/gNB control plane)
  $N3_NAME ($N3_SUBNET)              N3 — macvlan (5GC/gNB user plane)
  $N6_NAME ($N6_SUBNET)              N6 — macvlan (5GC internet-facing)
  $METRICS_NAME ($METRICS_SUBNET)    metrics — bridge Telegraf/InfluxDB/Grafana
  $RIC_NAME / $RIC_DOCKER_NAME       RIC bridge — ORAN-SC Near-RT RIC
  $N3BR_NAME ($N3BR_SUBNET)          n3br — macvlan parent for UE bridge
  $UE_N3_NAME                        ue_n3 — macvlan child of n3br for external UEs

Environment overrides:
  PARENT_IF, N2_NAME, N2_SUBNET, N2_GW, N3_NAME, N3_SUBNET, N3_GW,
  N6_NAME, N6_SUBNET, N6_GW, METRICS_NAME, METRICS_SUBNET, METRICS_GW,
  RIC_NAME, RIC_DOCKER_NAME, RIC_SUBNET, RIC_GW,
  N3BR_NAME, N3BR_SUBNET, N3BR_GW, UE_N3_NAME

Examples:
  $0               List networks (shortcut for dnet) — actually: init
  $0 init          Create all required networks
  $0 dnet          List all Docker networks
  $0 remove        Remove all networks
  $0 help          Show this help
EOF
}

# Validate parent interface exists
if ! ip link show "$PARENT_IF" >/dev/null 2>&1; then
  echo "Parent interface '$PARENT_IF' not found. Export PARENT_IF to override (default eth3)." >&2
  exit 1
fi

action=${1:-create}

case "$action" in
  init|create)
    create_macvlan_network "$N2_NAME" "$N2_SUBNET" "$N2_GW"
    # create_macvlan_network "$N3_NAME" "$N3_SUBNET" "$N3_GW"
    create_macvlan_network "$N6_NAME" "$N6_SUBNET" "$N6_GW"
    create_bridge_network "$METRICS_NAME" "$METRICS_SUBNET" "$METRICS_GW"
    create_ric_network
    create_host_macvlan
    # UE bridge macvlan network (child of n3br, used by ZMQ external UE setups)
    create_macvlan_child_network
    echo "Done. Networks initialized: $N2_NAME $N3_NAME $N6_NAME $METRICS_NAME $RIC_NAME $N3BR_NAME $UE_N3_NAME"
    ;;
  remove)
    remove_macvlan_child_network
    # remove n3br last because other networks may depend on it
    remove_host_macvlan
    remove_macvlan_network "$N6_NAME"
    # remove_macvlan_network "$N3_NAME"
    remove_macvlan_network "$N2_NAME"
    remove_bridge_network "$N3BR_NAME"
    remove_bridge_network "$METRICS_NAME"
    remove_ric_network
    echo "Done. Networks removed (if they existed): $N2_NAME $N3_NAME $N6_NAME $METRICS_NAME $RIC_NAME $N3BR_NAME"
    ;;
  dnet)
    dnet
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
