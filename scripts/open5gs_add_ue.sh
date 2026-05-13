#!/usr/bin/env bash
set -euo pipefail

# Adds one or more subscribers to the Open5GS MongoDB running in the container.
# Wraps the add_users.py script shipped in the Open5GS Docker image.
#
# Usage:
#   # Add a single subscriber via string arguments
#   ./scripts/open5gs_add_ue.sh --imsi 001010123456780
#
#   # With custom options
#   ./scripts/open5gs_add_ue.sh --imsi 222011234567890 --key aabbccdd11223344 --opc 63bfa50ee6523365ff14c1f45f88737d --ip 10.45.5.100
#
#   # Batch add from CSV file
#   ./scripts/open5gs_add_ue.sh --csv subscriber_db.csv

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="${OPEN5GS_CONTAINER:-open5gs_5gc}"

# Defaults matching add_users.py
IMSI=""
UE_KEY="00112233445566778899aabbccddeeff"
OP_TYPE="opc"          # "opc" | "op"
OP_VALUE="63bfa50ee6523365ff14c1f45f88737d"
AMF="9001"
QCI="9"
APN="internet"
IP_ALLOC=""
CSV_FILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --imsi <imsi> [options]
   or: $(basename "$0") --csv <file>

Single subscriber mode (requires --imsi):
  --imsi     IMSI of the subscriber (required)
  --key      UE security key in hex (default: 00112233445566778899aabbccddeeff)
  --opc      Cyphered Operator Code in hex (mutually exclusive with --op)
  --op       Operator Code in hex (mutually exclusive with --opc)
  --amf      AMF value in hex (default: 9001)
  --qci      QCI value (default: 9)
  --apn      APN name (default: internet)
  --ip       Static IP allocation (default: dynamic)

Batch CSV mode:
  --csv      Path to CSV file (format: name,imsi,key,op_type,op/opc,amf,qci,ip[,apn])

Common:
  --container, -c  Open5GS container name (default: ${CONTAINER_NAME})
  --help, -h       Show this help message

Examples:
  $(basename "$0") --imsi 001010123456780
  $(basename "$0") --imsi 222011234567890 --opc 63bfa50ee6523365ff14c1f45f88737d --ip 10.45.5.100
  $(basename "$0") --imsi 222011234567891 --op 12345678901234567890123456789012
  $(basename "$0") --csv subscriber_db.csv
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --imsi)
      [[ -z "${2:-}" ]] && { echo "Error: --imsi requires a value." >&2; exit 1; }
      IMSI="$2"
      shift 2
      ;;
    --key)
      [[ -z "${2:-}" ]] && { echo "Error: --key requires a value." >&2; exit 1; }
      UE_KEY="$2"
      shift 2
      ;;
    --opc)
      [[ -z "${2:-}" ]] && { echo "Error: --opc requires a value." >&2; exit 1; }
      OP_TYPE="opc"
      OP_VALUE="$2"
      shift 2
      ;;
    --op)
      [[ -z "${2:-}" ]] && { echo "Error: --op requires a value." >&2; exit 1; }
      OP_TYPE="op"
      OP_VALUE="$2"
      shift 2
      ;;
    --amf)
      [[ -z "${2:-}" ]] && { echo "Error: --amf requires a value." >&2; exit 1; }
      AMF="$2"
      shift 2
      ;;
    --qci)
      [[ -z "${2:-}" ]] && { echo "Error: --qci requires a value." >&2; exit 1; }
      QCI="$2"
      shift 2
      ;;
    --apn)
      [[ -z "${2:-}" ]] && { echo "Error: --apn requires a value." >&2; exit 1; }
      APN="$2"
      shift 2
      ;;
    --ip)
      [[ -z "${2:-}" ]] && { echo "Error: --ip requires a value." >&2; exit 1; }
      if [[ "$2" != "dynamic" ]]; then
        IP_ALLOC="$2"
      else
        IP_ALLOC=""
      fi
      shift 2
      ;;
    --csv)
      [[ -z "${2:-}" ]] && { echo "Error: --csv requires a value." >&2; exit 1; }
      CSV_FILE="$2"
      shift 2
      ;;
    --container|-c)
      [[ -z "${2:-}" ]] && { echo "Error: --container requires a value." >&2; exit 1; }
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

# Validate input mode
if [[ -n "$IMSI" && -n "$CSV_FILE" ]]; then
  echo "Error: --imsi and --csv are mutually exclusive." >&2
  exit 1
fi

if [[ -z "$IMSI" && -z "$CSV_FILE" ]]; then
  echo "Error: either --imsi or --csv is required." >&2
  exit 1
fi

# Check container exists
if ! docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "Error: Open5GS container '${CONTAINER_NAME}' is not running or not found." >&2
  exit 1
fi

# ── CSV mode: copy file into container and run ────────────────────────────────
if [[ -n "$CSV_FILE" ]]; then
  # Resolve path relative to current dir if not absolute
  if [[ "$CSV_FILE" != /* ]]; then
    CSV_FILE="$(pwd)/$CSV_FILE"
  fi
  if [[ ! -f "$CSV_FILE" ]]; then
    echo "Error: CSV file not found: $CSV_FILE" >&2
    exit 1
  fi

  # Copy to /tmp/ on the container
  csv_basename="$(basename "$CSV_FILE")"
  docker cp "$CSV_FILE" "${CONTAINER_NAME}:/tmp/${csv_basename}"

  # Run add_users.py pointing to the CSV inside the container
  docker exec "${CONTAINER_NAME}" python3 "/open5gs/add_users.py" \
    --mongodb "127.0.0.1" \
    --subscriber_data "/tmp/${csv_basename}"

  # Clean up temp file in container
  docker exec "${CONTAINER_NAME}" rm -f "/tmp/${csv_basename}"

  exit 0
fi

# ── Single subscriber mode: build string and pass via docker exec ─────────────
# Format: imsi,key,op_type,op/opc,amf,qci,ip[,apn]
SUB_STRING="${IMSI},${UE_KEY},${OP_TYPE},${OP_VALUE},${AMF},${QCI},${IP_ALLOC}"
if [[ -n "$APN" && "$APN" != "internet" ]]; then
  SUB_STRING="${SUB_STRING},${APN}"
fi

echo "Adding subscriber IMSI=${IMSI}..."
docker exec "${CONTAINER_NAME}" python3 "/open5gs/add_users.py" \
  --mongodb "127.0.0.1" \
  --subscriber_data "${SUB_STRING}"
