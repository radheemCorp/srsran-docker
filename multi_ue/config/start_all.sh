#!/bin/bash
#
# Bring up the co-located ZMQ bridge + N srsUE instances inside ONE container,
# then supervise them. All UEs share this container's IP and are multiplexed by
# ZMQ port (see multi_ue_scenario.py). Each srsUE lands its tun_srsue in its own
# netns ue<n>.
#
# Supervision policy:
#   - The BRIDGE is critical (it carries every UE's RF). If it dies, this script
#     exits non-zero so the container stops and can be recreated cleanly.
#   - A UE is independent. If a srsUE exits (e.g. radio-link failure under heavy
#     load), it is logged and restarted up to MAX_UE_RESTARTS times; one UE
#     failing never tears the whole container down.
#
# Usage: start_all.sh [N]      (N defaults to $NUM_UES, else 2)
#
# Env knobs:
#   NUM_UES, GNB_IP, UE_HOST_IP, UE_BIND_IP, ZMQ_BRIDGE_IP
#   START_STAGGER       seconds between UE starts            (default 3)
#   SUPERVISE_INTERVAL  seconds between health checks        (default 5)
#   RESTART_UES         restart a UE that exits (true|false) (default true)
#   MAX_UE_RESTARTS     per-UE restart cap                   (default 3)
#   LOG_DIR             where bridge.log / ue<n>.log go      (default /tmp)
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

N="${1:-${NUM_UES:-2}}"
GNB_IP="${GNB_IP:-10.10.3.231}"
UE_HOST_IP="${UE_HOST_IP:-10.10.4.237}"
START_STAGGER="${START_STAGGER:-3}"
SUPERVISE_INTERVAL="${SUPERVISE_INTERVAL:-5}"
RESTART_UES="${RESTART_UES:-true}"
MAX_UE_RESTARTS="${MAX_UE_RESTARTS:-3}"
LOG_DIR="${LOG_DIR:-/tmp}"

# srsUE + bridge both bind ZMQ to the container IP, so point the per-UE config
# generator at the host IP for both the bind and bridge endpoints.
export GNB_IP UE_ZMQ_MODE="bridge"
export UE_BIND_IP="${UE_BIND_IP:-$UE_HOST_IP}"
export ZMQ_BRIDGE_IP="${ZMQ_BRIDGE_IP:-$UE_HOST_IP}"

# Ensure the TUN device node exists (srsUE creates tun_srsue from it).
mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200

BRIDGE_PID=""
declare -A UE_PID        # n -> pid of its start_ue.sh subshell
declare -A UE_RESTARTS   # n -> restart count

cleanup() {
  trap - EXIT INT TERM
  echo "Stopping bridge + UEs..."
  [ -n "${BRIDGE_PID}" ] && kill "${BRIDGE_PID}" 2>/dev/null || true
  if [ "${#UE_PID[@]}" -gt 0 ]; then
    for pid in "${UE_PID[@]}"; do kill "${pid}" 2>/dev/null || true; done
  fi
}
trap cleanup EXIT INT TERM

start_one_ue() {
  local n="$1"
  UE_NUM="${n}" "${HERE}/start_ue.sh" "${n}" >"${LOG_DIR}/ue${n}.log" 2>&1 &
  UE_PID[$n]=$!
}

echo "=== Starting co-located bridge for ${N} UE(s): gNB=${GNB_IP} host=${UE_HOST_IP} ==="
python3 "${HERE}/multi_ue_scenario.py" --num-ues "${N}" \
  --gnb-ip "${GNB_IP}" --host-ip "${UE_HOST_IP}" >"${LOG_DIR}/bridge.log" 2>&1 &
BRIDGE_PID=$!

# Give the bridge a moment to bind its sockets before UEs connect.
sleep 2

for n in $(seq 1 "${N}"); do
  echo "=== Starting UE ${n} (netns ue${n}) ==="
  start_one_ue "${n}"
  sleep "${START_STAGGER}"
done

echo "=== All started. Supervising (interval ${SUPERVISE_INTERVAL}s). Logs in ${LOG_DIR}. ==="
echo "    Check attach:  ip netns exec ue1 ip addr show tun_srsue"
echo "    Generate load: ${HERE}/run_all_scenarios.sh --voip-client --server-ip 10.45.0.1"

# ── Supervisor loop ──────────────────────────────────────────────────────────
while true; do
  sleep "${SUPERVISE_INTERVAL}"

  # Bridge is critical: its death takes down the whole RF path.
  if ! kill -0 "${BRIDGE_PID}" 2>/dev/null; then
    echo "FATAL: bridge (pid ${BRIDGE_PID}) exited; tearing down container." >&2
    exit 1
  fi

  # UEs are independent: log, and restart up to the cap.
  for n in "${!UE_PID[@]}"; do
    pid="${UE_PID[$n]}"
    if kill -0 "${pid}" 2>/dev/null; then continue; fi
    wait "${pid}" 2>/dev/null || true
    echo "WARN: UE ${n} (pid ${pid}) exited." >&2
    if [ "${RESTART_UES}" = "true" ] && [ "${UE_RESTARTS[$n]:-0}" -lt "${MAX_UE_RESTARTS}" ]; then
      UE_RESTARTS[$n]=$(( ${UE_RESTARTS[$n]:-0} + 1 ))
      echo "      restarting UE ${n} (attempt ${UE_RESTARTS[$n]}/${MAX_UE_RESTARTS})..." >&2
      start_one_ue "${n}"
    else
      echo "      not restarting UE ${n} (RESTART_UES=${RESTART_UES}, restarts=${UE_RESTARTS[$n]:-0}/${MAX_UE_RESTARTS})." >&2
      unset 'UE_PID[$n]'
    fi
  done
done
