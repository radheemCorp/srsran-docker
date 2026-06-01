#!/bin/bash

# Start a UE instance inside the container.
# This script generates the UE config, ensures the UE netns exists, and then runs srsUE.

set -euo pipefail

if [ -z "${1-}" ]; then
  echo "Usage: $0 <ue-number>"
  exit 1
fi

UE=$1
NS=ue${UE}
NSFILE=/run/netns/${NS}
GNB_IP=${GNB_IP:-10.10.3.231}
UE_BIND_IP=${UE_BIND_IP:-*}
UE_ZMQ_MODE=${UE_ZMQ_MODE:-direct}
ZMQ_BRIDGE_IP=${ZMQ_BRIDGE_IP:-10.10.3.236}
UE_DNS1=${UE_DNS1:-1.1.1.1}
UE_DNS2=${UE_DNS2:-8.8.8.8}
ROUTE_WAIT_SECONDS=${ROUTE_WAIT_SECONDS:-120}
UE_CONF_PATH=${UE_CONF_PATH:-/srsran/config/ue.conf}

# Clean up stale netns mountpoints (they can be left behind if the UE process crashes)
if [ -e "${NSFILE}" ]; then
  # If it is a proper netns mount, `ip netns list` should include it and `ip netns exec` should work.
  # If it isn't, remove it so `ip netns add` can recreate it cleanly.
  if ! ip netns list | grep -qw "${NS}"; then
    echo "Removing stale netns file ${NSFILE}"
    rm -f "${NSFILE}"
  fi
fi

# Create the namespace if missing
ip netns add "${NS}" 2>/dev/null || true

# Bring up loopback inside the namespace
ip netns exec "${NS}" ip link set lo up 2>/dev/null || true

# Ensure per-netns DNS is usable (avoid container stub resolver in UE netns)
mkdir -p "/etc/netns/${NS}"
cat > "/etc/netns/${NS}/resolv.conf" <<EOF
nameserver ${UE_DNS1}
nameserver ${UE_DNS2}
EOF

# Background helper: once tun_srsue appears, install default route via tunnel
(
  for _ in $(seq 1 "${ROUTE_WAIT_SECONDS}"); do
    if ip netns exec "${NS}" ip link show tun_srsue >/dev/null 2>&1; then
      ip netns exec "${NS}" ip route replace default dev tun_srsue scope link || true
      exit 0
    fi
    sleep 1
  done
  echo "Warning: tun_srsue did not appear in ${NS} within ${ROUTE_WAIT_SECONDS}s" >&2
) &
ROUTE_HELPER_PID=$!
trap 'kill "${ROUTE_HELPER_PID}" 2>/dev/null || true' EXIT

# Generate the UE config file if a fixed config is not provided.
if [ -f "${UE_CONF_PATH}" ]; then
  UE_CONF_FILE="${UE_CONF_PATH}"
else
  python3 /srsran/config/generate_ue_conf.py "${UE}" /tmp/ --mode "${UE_ZMQ_MODE}" --gnb-ip "${GNB_IP}" --bridge-ip "${ZMQ_BRIDGE_IP}" --ue-bind-ip "${UE_BIND_IP}"
  UE_CONF_FILE="/tmp/ue_${UE}.conf"
fi

# Start srsUE in the container network namespace (so it can bind to the container IP).
# srsUE will create the tun_srsue interface inside ${NS} after a successful attach.
/opt/srsRAN_4G/build/srsue/src/srsue "${UE_CONF_FILE}"
