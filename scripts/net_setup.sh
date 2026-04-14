#!/bin/bash

# 1. CLEANUP: Remove existing networks to prevent subnet overlap errors
echo "Cleaning old networks..."
docker network rm ran metrics n3br oran-sc-ric_ric_network n2network n3network n2br n3br n4br n6br 2>/dev/null

# 2. OVS & MACVLAN NETWORKS (Physical/Infrastructure Layer)
# Format: "BridgeName|Subnet|Gateway|MTU"
OVS_NETS=(
    "ran|10.53.1.0/24|10.53.1.254|1450"
    "n3br|10.10.3.0/24|10.10.3.254|1450"
    "n4br|10.54.1.0/24|10.54.1.254|1450"
    "n6br|10.55.1.0/24|10.55.1.254|1500"
)

echo "Setting up OVS Bridges and Macvlan..."
for NET in "${OVS_NETS[@]}"; do
    IFS='|' read -r BR SUBNET GW MTU <<< "$NET"
    
    # Create OVS Bridge if missing
    sudo ovs-vsctl --may-exist add-br "$BR"
    sudo ip link set "$BR" mtu "$MTU"
    sudo ip addr add "$GW/24" dev "$BR" 2>/dev/null
    sudo ip link set "$BR" up

    # Create Macvlan network riding on the OVS bridge
    docker network inspect "$BR" >/dev/null 2>&1 || \
    docker network create -d macvlan --subnet="$SUBNET" --gateway="$GW" -o parent="$BR" "$BR"
done

# 3. DOCKER INTERNAL BRIDGES (Service Layer)
# Format: "NetName|Subnet|Gateway"
BRIDGE_NETS=(
    "metrics|172.19.1.0/24|172.19.1.254"
    "oran-sc-ric_ric_network|10.0.2.0/24|10.0.2.254"
    "n2network|10.53.2.0/24|10.53.2.254"
)
echo "Setting up Docker Internal Bridges..."
for NET in "${BRIDGE_NETS[@]}"; do
    IFS='|' read -r NAME SUBNET GW <<< "$NET"
    docker network inspect "$NAME" >/dev/null 2>&1 || \
    docker network create -d bridge --subnet="$SUBNET" --gateway="$GW" "$NAME"
done

# 4. FINAL TOUCHES
sudo iptables -t nat -A POSTROUTING -s 10.55.1.0/24 ! -o n6br -j MASQUERADE
echo "Done. Subnets organized and isolated."
docker network ls --format "table {{.Name}}\t{{.Driver}}" | grep -E 'br|ran|metrics|ric|network'