#!/bin/bash

# --- Configuration ---
# Names of Docker networks and OVS bridges to remove
DOCKER_NETS=("ran" "metrics" "n3br" "oran-sc-ric_ric_network" "n2network" "n3network")
OVS_BRS=("n3br" "n4br" "n6br")

echo "Starting Unified Network Cleanup..."

# 1. Remove Docker Networks first (releases interfaces)
for NET in "${DOCKER_NETS[@]}"; do
    if docker network inspect "$NET" >/dev/null 2>&1; then
        echo "[..] Removing Docker network: $NET"
        docker network rm "$NET" >/dev/null
    fi
done

# 2. Remove OVS Bridges and their Docker Macvlan counterparts
for BR in "${OVS_BRS[@]}"; do
    # Remove the docker macvlan network tied to the bridge
    if docker network inspect "$BR" >/dev/null 2>&1; then
        docker network rm "$BR" >/dev/null
    fi

    # Delete the OVS Bridge from the host
    if sudo ovs-vsctl br-exists "$BR"; then
        echo "[..] Deleting OVS Bridge: $BR"
        sudo ovs-vsctl del-br "$BR"
    fi
done

# 3. Clean up NAT rules
echo "[..] Cleaning up IPtables rules..."
sudo iptables -t nat -D POSTROUTING -s 10.55.1.0/24 ! -o n6br -j MASQUERADE 2>/dev/null

echo "------------------------------------------------"
echo "Cleanup Complete. Remaining Docker Networks:"
docker network ls --format '{{.Name}}' | grep -E "br|ran|metrics|ric" || echo "None found."