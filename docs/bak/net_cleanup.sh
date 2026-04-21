#!/usr/bin/env bash
set -euo pipefail

# net_cleanup.sh
# Remove docker networks, OVS bridges and iptables rules created by net_setup.sh

OUT_IF=${OUT_IF:-}
if [ -z "$OUT_IF" ]; then
  OUT_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}') || true
  OUT_IF=${OUT_IF:-eth0}
fi

echo "Using external interface: $OUT_IF"

# Names of Docker networks and OVS bridges to remove
DOCKER_NETS=("ran" "metrics" "n3br" "oran-sc-ric_ric_network" "n2network" "n3network")
OVS_BRS=("ran" "n3br" "n4br" "n6br")

echo "Starting Unified Network Cleanup..."

# 1. Remove Docker Networks first (releases interfaces)
for NET in "${DOCKER_NETS[@]}"; do
    if docker network inspect "$NET" >/dev/null 2>&1; then
        echo "[..] Removing Docker network: $NET"
        docker network rm "$NET" >/dev/null || true
    fi
done

# 2. Remove OVS Bridges and their Docker Macvlan counterparts
for BR in "${OVS_BRS[@]}"; do
    # Remove the docker macvlan network tied to the bridge
    if docker network inspect "$BR" >/dev/null 2>&1; then
        docker network rm "$BR" >/dev/null || true
    fi

    # Delete the OVS Bridge from the host
    if sudo ovs-vsctl br-exists "$BR" >/dev/null 2>&1; then
        echo "[..] Deleting OVS Bridge: $BR"
        sudo ovs-vsctl del-br "$BR" || true
    fi
done

# 3. Clean up NAT rules for the same subnets net_setup created
echo "[..] Cleaning up IPtables MASQUERADE rules..."
SUBNETS=("10.53.1.0/24" "10.10.3.0/24" "10.54.1.0/24" "10.55.1.0/24")
for S in "${SUBNETS[@]}"; do
    if sudo iptables -t nat -C POSTROUTING -s "$S" -o "$OUT_IF" -j MASQUERADE >/dev/null 2>&1; then
        sudo iptables -t nat -D POSTROUTING -s "$S" -o "$OUT_IF" -j MASQUERADE || true
    fi
done

# Remove sysctl file if we created it
if [ -f /etc/sysctl.d/99-srsran.conf ]; then
    sudo rm -f /etc/sysctl.d/99-srsran.conf || true
fi

echo "------------------------------------------------"
echo "Cleanup Complete. Remaining Docker Networks:"
docker network ls --format '{{.Name}}' | grep -E "ran|metrics|ric|network" || echo "None found."