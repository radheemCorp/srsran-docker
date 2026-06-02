#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# manage.sh – start / stop components of the srsRAN 5G testbed
#
# Usage:
#   ./scripts/manage.sh start|stop ric        # ORAN RIC
#   ./scripts/manage.sh start|stop gnb         # gNB + 5GC
#   ./scripts/manage.sh start|stop ue          # bridge + UE1 + UE2  (ZMQ only)
#   ./scripts/manage.sh start|stop monitoring # monitoring stack (telegraf, influxdb, grafana)
#   ./scripts/manage.sh start|stop all         # everything
#
# DEPLOY_TYPE (zmq|uhd) is read from the project root .env (default: zmq).
# ZMQ uses the bridge + UE containers. UHD runs the gNB on host SDR.
# ---------------------------------------------------------------------------

MANAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MANAGE_DIR/.." && pwd)"

# ── load optional .env override (root project .env) ──────────────────────────
if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a; source "$ROOT_DIR/.env"; set +a
fi

DEPLOY_TYPE="${DEPLOY_TYPE:-uhd}"                       # zmq | uhd
RIC_DIR="$ROOT_DIR/oran-sc-ric"
ZMQ_DIR="$ROOT_DIR/srsRAN_Project/gnb-zmq"
UHD_DIR="$ROOT_DIR/srsRAN_Project/gnb-uhd"
MONITOR_DIR="$ROOT_DIR/srsRAN_Project/docker"
MONITOR_WORKDIR="$ROOT_DIR/srsRAN_Project"
BRIDGE_DIR="$ROOT_DIR/ue/bridge"
UE1_DIR="$ROOT_DIR/ue/ue1"
UE2_DIR="$ROOT_DIR/ue/ue2"

# ── colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()   { printf "${GREEN}[manage]  %s${NC}\n" "$*"; }
warn()  { printf "${YELLOW}[manage!] %s${NC}\n" "$*"; }
err()   { printf "${RED}[manage!] %s${NC}\n" "$*"; }

# ── action: compose up / down ────────────────────────────────────────────────
compose() {
    # Wrapper: prefers "docker compose" (v2 plugin), falls back to "docker-compose" (standalone)
    if command -v docker compose &>/dev/null; then
        docker compose "$@"
    elif command -v docker-compose &>/dev/null; then
        docker-compose "$@"
    else
        err "Neither 'docker compose' nor 'docker-compose' found."
        return 1
    fi
}

_up() {
    local dir="$1" label="$2"
    local compose_file=""

    # Priority: .yaml > .yml
    if [[ -f "$dir/docker-compose.yaml" ]]; then
        compose_file="$dir/docker-compose.yaml"
    elif [[ -f "$dir/docker-compose.yml" ]]; then
        compose_file="$dir/docker-compose.yml"
    elif [[ -f "$dir/docker-compose.ui.yml" ]]; then
        compose_file="$dir/docker-compose.ui.yml"
    else
        err "No docker-compose file in $dir"
        return 1
    fi

    log "Starting $label  ($dir)"
    compose -f "$compose_file" up -d
    log "$label started."
}

_down() {
    local dir="$1" label="$2"
    local compose_file=""

    if [[ -f "$dir/docker-compose.yaml" ]]; then
        compose_file="$dir/docker-compose.yaml"
    elif [[ -f "$dir/docker-compose.yml" ]]; then
        compose_file="$dir/docker-compose.yml"
    elif [[ -f "$dir/docker-compose.ui.yml" ]]; then
        compose_file="$dir/docker-compose.ui.yml"
    else
        warn "No docker-compose file in $dir, skipping."
        return 0
    fi

    log "Stopping $label  ($dir)"
    compose -f "$compose_file" down 2>/dev/null || true
    log "$label stopped."
}

# ── component routers ────────────────────────────────────────────────────────
_do_ric() {
    local action="$1"; shift
    case "$action" in
        up)   _up   "$RIC_DIR" "RIC";;
        down) _down "$RIC_DIR" "RIC";;
        *)    err "Unknown action: $action";;
    esac
}

_do_gnb() {
    local action="$1"
    case "$action" in
        up)
            if [[ "$DEPLOY_TYPE" == "uhd" ]]; then
                _up "$UHD_DIR" "gNB (UHD)"
            else
                # gnb-zmq compose has 5gc + gnb
                _up "$ZMQ_DIR" "gNB (ZMQ) + 5GC"
            fi
            ;;
        down)
            if [[ "$DEPLOY_TYPE" == "uhd" ]]; then
                _down "$UHD_DIR" "gNB (UHD)"
            else
                _down "$ZMQ_DIR" "gNB (ZMQ) + 5GC"
            fi
            ;;
        *)    err "Unknown action: $action";;
    esac
}

_do_ue() {
    local action="$1"
    if [[ "$DEPLOY_TYPE" != "zmq" ]]; then
        warn "UE bridge/containers are only available for DEPLOY_TYPE=zmq (current=$DEPLOY_TYPE). Skipping."
        return 0
    fi
    case "$action" in
        up)
            _up "$BRIDGE_DIR" "ZMQ Bridge"
            _up "$UE1_DIR" "UE1"
            _up "$UE2_DIR" "UE2"
            ;;
        down)
            # Down in reverse dependency order
            # Stop UE runnners first (they may have exec'd processes)
            _down "$UE2_DIR" "UE2"
            _down "$UE1_DIR" "UE1"
            _down "$BRIDGE_DIR" "ZMQ Bridge"
            ;;
        *)    err "Unknown action: $action";;
    esac
}

_do_monitoring() {
    local action="$1"
    local compose_file="$MONITOR_DIR/docker-compose.ui.yml"

    if [[ ! -f "$compose_file" ]]; then
        err "No docker-compose.ui.yml found in $MONITOR_DIR"
        return 1
    fi

    case "$action" in
        up)
            log "Starting monitoring stack (telegraf, influxdb, grafana)"
            compose -f "$compose_file" up -d
            log "Monitoring started."
            ;;
        down)
            log "Stopping monitoring stack (telegraf, influxdb, grafana)"
            compose -f "$compose_file" down 2>/dev/null || true
            log "Monitoring stopped."
            ;;
        *)    err "Unknown action: $action";;
    esac
}

_do_all() {
    local action="$1"
    case "$action" in
        up)
            _do_ric        up
            _do_gnb        up
            _do_ue         up
            _do_monitoring up
            ;;
        down)
            # Stop in reverse dependency order
            _do_monitoring down
            _do_ue         down
            _do_gnb        down
            _do_ric        down
            ;;
        *)    err "Unknown action: $action";;
    esac
}

# ── main ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") <start|stop> <component>

Components:
  ric     ORAN-SC Near-RT RIC
  gnb     srsRAN gNB (+ 5GC Open5GS)
  ue      ZMQ bridge + UE1 + UE2  (DEPLOY_TYPE=zmq only, does not run the ues just the containers)
  monitoring  telegraf, influxdb, grafana
  all     ric + gnb + ue + monitoring

DEPLOY_TYPE is set in the project root .env (default: zmq).
Override by adding DEPLOY_TYPE=<zmq|uhd> to $ROOT_DIR/.env
EOF
    exit 1
}

[[ $# -lt 2 ]] && usage

ACTION="$1"; shift
COMPONENT="$1"

case "$ACTION" in
    start) _ACTION="up"   ;;
    stop)  _ACTION="down" ;;
    *)     err "Unknown action: $ACTION (use start|stop)"; usage ;;
esac

case "$COMPONENT" in
    ric) _do_ric       "$_ACTION" ;;
    gnb) _do_gnb       "$_ACTION" ;;
    ue)  _do_ue        "$_ACTION" ;;
    monitoring) _do_monitoring "$_ACTION" ;;
    all) _do_all       "$_ACTION" ;;
    *)   err "Unknown component: $COMPONENT"; usage ;;
esac
