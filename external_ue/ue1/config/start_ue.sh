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
UE_USE_NETNS=${UE_USE_NETNS:-false}

if [[ "${UE_USE_NETNS,,}" == "true" ]]; then
  # Ensure the namespace is valid and usable. Restarted containers can leave
  # stale namespace references that exist but cannot be entered.
  if ip netns list | grep -qw "${NS}"; then
    if ! ip netns exec "${NS}" true >/dev/null 2>&1; then
      echo "Recreating broken netns ${NS}"
      ip netns del "${NS}" >/dev/null 2>&1 || true
      rm -f "${NSFILE}" >/dev/null 2>&1 || true
    fi
  fi

  if ! ip netns list | grep -qw "${NS}"; then
    rm -f "${NSFILE}" >/dev/null 2>&1 || true
    ip netns add "${NS}"
  fi

  # Bring up loopback inside the namespace
  ip netns exec "${NS}" ip link set lo up >/dev/null 2>&1 || true

  # Ensure per-netns DNS is usable (avoid container stub resolver in UE netns)
  mkdir -p "/etc/netns/${NS}"
  cat > "/etc/netns/${NS}/resolv.conf" <<EOF
nameserver ${UE_DNS1}
nameserver ${UE_DNS2}
EOF
fi

# Background helper: once tun_srsue appears, install default route via tunnel
(
  for _ in $(seq 1 "${ROUTE_WAIT_SECONDS}"); do
    if [[ "${UE_USE_NETNS,,}" == "true" ]]; then
      if ip netns exec "${NS}" ip link show tun_srsue >/dev/null 2>&1; then
        ip netns exec "${NS}" ip route replace default dev tun_srsue scope link || true
        exit 0
      fi
    else
      if ip link show tun_srsue >/dev/null 2>&1; then
        ip route replace default dev tun_srsue scope link || true
        exit 0
      fi
    fi
    sleep 1
  done
  if [[ "${UE_USE_NETNS,,}" == "true" ]]; then
    echo "Warning: tun_srsue did not appear in ${NS} within ${ROUTE_WAIT_SECONDS}s" >&2
  else
    echo "Warning: tun_srsue did not appear in container namespace within ${ROUTE_WAIT_SECONDS}s" >&2
  fi
) &
ROUTE_HELPER_PID=$!
trap 'kill "${ROUTE_HELPER_PID}" 2>/dev/null || true' EXIT

# Generate the UE config file
python3 /srsran/config/generate_ue_conf.py "${UE}" /tmp/ --mode "${UE_ZMQ_MODE}" --gnb-ip "${GNB_IP}" --bridge-ip "${ZMQ_BRIDGE_IP}" --ue-bind-ip "${UE_BIND_IP}"

# Start srsUE in the container network namespace (so it can bind to the container IP).
# srsUE will create the tun_srsue interface inside ${NS} after a successful attach.
/opt/srsRAN_4G/build/srsue/src/srsue /tmp/ue_${UE}.conf
