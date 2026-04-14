#!/bin/bash

# --- Configuration ---
# Must match the BridgeNames used in the setup script
BR_NAMES=("n2br" "n3br" "n4br" "n6br")

# Docker networks created for services in net_setup.sh
# Format: same as in net_setup: "NetName"
DOCKER_NETWORKS=(
    "ran"
    "metrics"
    "ue_n3"
    "oran-sc-ric_ric_network"
    "n2network"
    "n3network"
)

echo "Starting OVS and Docker Network Cleanup..."

for BR in "${BR_NAMES[@]}"; do
    echo "------------------------------------------------"
    echo "Cleaning up: $BR"

    # 1. Remove Docker Network
    if docker network inspect "$BR" >/dev/null 2>&1; then
        echo "[..] Removing Docker network: $BR"
        docker network rm "$BR"
        echo "[OK] Docker network $BR removed."
    else
        echo "[!] Docker network $BR not found."
    fi

    # 2. Remove OVS Bridge
    if sudo ovs-vsctl br-exists "$BR"; then
        echo "[..] Deleting OVS Bridge: $BR"
        sudo ovs-vsctl del-br "$BR"
        echo "[OK] OVS Bridge $BR deleted."
    else
        echo "[!] OVS Bridge $BR not found on host."
    fi
done

echo "------------------------------------------------"
echo "Removing service Docker networks..."
for N in "${DOCKER_NETWORKS[@]}"; do
    if docker network inspect "$N" >/dev/null 2>&1; then
        echo "[..] Removing Docker network: $N"
        docker network rm "$N"
        echo "[OK] Docker network $N removed."
    else
        echo "[!] Docker network $N not found."
    fi
done

echo "------------------------------------------------"
echo "Cleanup Complete."
# Optional: Show remaining bridges to ensure it's clean
sudo ovs-vsctl list-br