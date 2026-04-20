#!/bin/bash

set -euo pipefail

NUM_UES=${1:-10}
UE_IDS=${2:-${UE_IDS:-}}
GNB_IP=${GNB_IP:-10.53.1.3}
BRIDGE_IP=${BRIDGE_IP:-10.53.1.6}
UE_IP_BASE=${UE_IP_BASE:-233}
# If BRIDGE_BIND_ALL or BIND_ALL is truthy, pass --bind-all to the bridge
BRIDGE_BIND_ALL=${BRIDGE_BIND_ALL:-${BIND_ALL:-false}}

ARGS=(--num-ues "${NUM_UES}" --gnb-ip "${GNB_IP}" --bridge-ip "${BRIDGE_IP}" --ue-ip-base "${UE_IP_BASE}")

if [ -n "${UE_IDS}" ]; then
  ARGS+=(--ue-ids "${UE_IDS}")
fi

if [[ "${BRIDGE_BIND_ALL,,}" == "1" || "${BRIDGE_BIND_ALL,,}" == "true" || "${BRIDGE_BIND_ALL,,}" == "yes" ]]; then
  ARGS+=(--bind-all)
fi

python3 /srsran/config/zmq_bridge.py "${ARGS[@]}"
