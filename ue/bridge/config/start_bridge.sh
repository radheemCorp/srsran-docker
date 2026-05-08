#!/bin/bash

set -euo pipefail

NUM_UES=${1:-10}
UE_IDS=${2:-${UE_IDS:-}}
GNB_IP=${GNB_IP:-10.10.3.231}
BRIDGE_IP=${BRIDGE_IP:-10.10.3.236}
UE_IP_BASE=${UE_IP_BASE:-233}

ARGS=(--num-ues "${NUM_UES}" --gnb-ip "${GNB_IP}" --bridge-ip "${BRIDGE_IP}" --ue-ip-base "${UE_IP_BASE}")

if [ -n "${UE_IDS}" ]; then
  ARGS+=(--ue-ids "${UE_IDS}")
fi

python3 /srsran/config/zmq_bridge.py "${ARGS[@]}"
