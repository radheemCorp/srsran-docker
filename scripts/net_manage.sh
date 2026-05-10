#!/usr/bin/env bash
set -euo pipefail

# Create Docker macvlan networks for 5G interfaces (N2, N3, N4, N6).
# Defaults are chosen to match docs/networks.md but can be overridden
# by exporting environment variables before running this script.

# Host physical interface used as macvlan parent
PARENT_IF=${PARENT_IF:-eth1}

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

# ============================================
# IP Forwarding + NAT Masquerade for UE subnets
# ============================================

# Internet-facing external interface (auto-detected if not set)
OUT_IF=${OUT_IF:-$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')}
if [ -z "$OUT_IF" ]; then
  OUT_IF=${OUT_IF:-eth0}
fi

# UE IP range for NAT masquerading
UE_SUBNET=${UE_SUBNET:-10.45.0.0/16}

# TUN interface name used by open5gs
OGSTUN_IF=${OGSTUN_IF:-ogstun}

# --- Apply NAT forwarding ---
enable_nat_forwarding() {
  echo "=== Enabling IP forwarding and NAT for UE subnets ==="

  # 1. Enable IPv4 forwarding
  echo "Enabling IP forwarding..."
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  # Also persist it for reboots
  mkdir -p /etc/sysctl.d
  echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-srsran-nat.conf

  # 2. NAT masquerade for the UE subnet
  echo "Setting up MASQUERADE for ${UE_SUBNET} via ${OUT_IF}..."
  if ! iptables -t nat -C POSTROUTING -s "${UE_SUBNET}" -o "${OUT_IF}" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s "${UE_SUBNET}" -o "${OUT_IF}" -j MASQUERADE
  fi

  # 3. Allow forwarding rules
  if ! iptables -C FORWARD -i "${OGSTUN_IF}" -o "${OUT_IF}" -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i "${OGSTUN_IF}" -o "${OUT_IF}" -j ACCEPT
  fi

  if ! iptables -C FORWARD -i "${OUT_IF}" -o "${OGSTUN_IF}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i "${OUT_IF}" -o "${OGSTUN_IF}" -m state --state RELATED,ESTABLISHED -j ACCEPT
  fi

  echo "NAT forwarding enabled."
}

# --- Remove NAT forwarding ---
disable_nat_forwarding() {
  echo "=== Removing NAT and rules ==="

  # Reverse iptables rules
  iptables -t nat -D POSTROUTING -s "${UE_SUBNET}" -o "${OUT_IF}" -j MASQUERADE 2>/dev/null || true
  iptables -D FORWARD -i "${OGSTUN_IF}" -o "${OUT_IF}" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i "${OUT_IF}" -o "${OGSTUN_IF}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

  echo "NAT forwarding disabled (sysctl.d file preserved for next use)."
}

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  create         Create all macvlan networks and enable NAT (default)
  remove         Remove all macvlan networks and disable NAT
  nat-enable     Enable IP forwarding and NAT masquerade only
  nat-disable    Disable NAT and forwarding rules only
  nat-status     Show current NAT/forwarding status
  help           Show this help

Environment overrides:
  PARENT_IF, N2_NAME, N2_SUBNET, N2_GW, N3_NAME, N3_SUBNET, N3_GW,
  N6_NAME, N6_SUBNET, N6_GW, METRICS_NAME, METRICS_SUBNET, METRICS_GW,
  RIC_NAME, RIC_DOCKER_NAME, ric_network,
  OUT_IF, UE_SUBNET, OGSTUN_IF

Examples:
  $0                    # Create networks + enable NAT
  $0 nat-status         # Show NAT status
  OUT_IF=ens33 UE_SUBNET=10.46.0.0/16 \$0 nat-enable  # Custom subnet/interface
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
    create_ric_network
    create_host_macvlan
    enable_nat_forwarding
    echo "Done. Networks created (or already existed): $N2_NAME $N3_NAME $N6_NAME $METRICS_NAME $RIC_NAME"
    ;;
  remove)
    remove_host_macvlan
    remove_macvlan_network "$N6_NAME"
    remove_macvlan_network "$N3_NAME"
    remove_macvlan_network "$N2_NAME"
    remove_bridge_network "$METRICS_NAME"
    remove_ric_network
    disable_nat_forwarding
    echo "Done. Networks removed (if they existed): $N2_NAME $N3_NAME $N6_NAME $METRICS_NAME $RIC_NAME"
    ;;
  nat-enable)
    enable_nat_forwarding
    ;;
  nat-disable)
    disable_nat_forwarding
    ;;
  nat-status)
    echo "--- IP Forwarding:"
    cat /proc/sys/net/ipv4/ip_forward
    echo "--- NAT/MASQUERADE rules:"
    iptables -t nat -L POSTROUTING -v -n --line-numbers
    echo "--- FORWARD rules:"
    iptables -L FORWARD -v -n --line-numbers
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
