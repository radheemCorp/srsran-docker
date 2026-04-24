#!/bin/bash
set -euo pipefail

# entrypoint: prepare ue config and run srsue
GNB_TX_HOST=${GNB_TX_HOST:-10.53.1.3}
GNB_TX_PORT=${GNB_TX_PORT:-2000}
GNB_RX_HOST=${GNB_RX_HOST:-10.53.1.6}
GNB_RX_PORT=${GNB_RX_PORT:-2001}
UE_ID=${UE_ID:-0}
OPEN5GS_AMF=${OPEN5GS_AMF:-10.53.1.2}
UE_IMSI=${UE_IMSI:-}

CONF_DIR=/srsran/config
UE_CONF=${CONF_DIR}/ue0.conf

# ensure config exists
if [ ! -f "${UE_CONF}" ]; then
  echo "ERROR: ${UE_CONF} not found (mount ./config into /srsran/config)" >&2
  exec bash
fi

# update device_args in ue0.conf to point to gNB (UE tx -> gNB rx, UE rx -> gNB tx)

# export vars for scripts
export GNB_ZMQ_ENDPOINT="tcp://${GNB_RX_HOST}:${GNB_RX_PORT}"
export GNB_RX_HOST GNB_RX_PORT GNB_TX_HOST GNB_TX_PORT

# NOTE: avoid editing the mounted config directly (may be read-only).
# Edits will be applied to a writable copy in /tmp below.
export OPEN5GS_AMF

# generate final conf and start UE using the project's script
TMP_CONF="/tmp/ue_${UE_ID}.conf"

# If we can, copy mounted config to /tmp and edit the copy (mounted config may be read-only)
cp "${UE_CONF}" "${TMP_CONF}" || true

# If copy failed (missing), try generate_ue_conf.py to create TMP_CONF
if [ ! -f "${TMP_CONF}" ] && [ -x "${CONF_DIR}/generate_ue_conf.py" ]; then
  python3 "${CONF_DIR}/generate_ue_conf.py" "${UE_ID}" /tmp/
  TMP_CONF="/tmp/ue_${UE_ID}.conf"
fi

if [ -f "${TMP_CONF}" ]; then
  # edit the writable copy
  sed -E -i "s#device_args\s*=.*#device_args = tx_port=tcp://${GNB_RX_HOST}:${GNB_RX_PORT},rx_port=tcp://${GNB_TX_HOST}:${GNB_TX_PORT},base_srate=23.04e6#" "${TMP_CONF}" || true
  if [ -n "${UE_IMSI}" ]; then
    sed -E -i "s#(imsi\s*=\s*).*#\1${UE_IMSI}#" "${TMP_CONF}" || true
  fi

  # create netns if needed
  ip netns add ue${UE_ID} || true

  # Run srsue on the modified config if binary exists
  if [ -x "/opt/srsRAN_4G/build/srsue/src/srsue" ]; then
    /opt/srsRAN_4G/build/srsue/src/srsue "${TMP_CONF}"
  else
    echo "srsue binary not found — build may have failed. See Docker build logs." >&2
    exec bash
  fi
else
  echo "No config available to run srsue (tried ${TMP_CONF} and ${UE_CONF})." >&2
  exec bash
fi

# keep container running if the UE process exits
sleep infinity
