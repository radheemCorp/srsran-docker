#!/bin/bash

# --- Configuration ---
# Define the networks to be created
# Format: "BridgeName|Subnet|Gateway|MTU"
NETWORKS=(
    "n2br|10.53.1.0/24|10.53.1.254|1450"
    "n3br|10.10.3.0/24|10.10.3.254|1450"
    "n4br|10.54.1.0/24|10.54.1.254|1450"
    "n6br|10.55.1.0/24|10.55.1.254|1500"
)

echo "Starting OVS and Docker Network Setup..."

for NET in "${NETWORKS[@]}"; do
    IFS='|' read -r BR_NAME SUBNET GW MTU <<< "$NET"

    echo "------------------------------------------------"
    echo "Configuring: $BR_NAME ($SUBNET)"

    # 1. Create OVS Bridge
    if ! sudo ovs-vsctl br-exists "$BR_NAME"; then
        sudo ovs-vsctl add-br "$BR_NAME"
        echo "[OK] OVS Bridge $BR_NAME created."
    else
        echo "[!] OVS Bridge $BR_NAME already exists."
    fi

    # 2. Configure Bridge Interface
    sudo ip link set "$BR_NAME" mtu "$MTU"
    sudo ip addr add "$GW/24" dev "$BR_NAME" 2>/dev/null
    sudo ip link set "$BR_NAME" up
    echo "[OK] Host interface $BR_NAME up with MTU $MTU."

    # 3. Create Docker Network (Macvlan tied to OVS Bridge)
    # Check if docker network exists
    if ! docker network inspect "$BR_NAME" >/dev/null 2>&1; then
        docker network create -d macvlan \
            --subnet="$SUBNET" \
            --gateway="$GW" \
            -o parent="$BR_NAME" \
            "$BR_NAME"
        echo "[OK] Docker network '$BR_NAME' created."
    else
        echo "[!] Docker network '$BR_NAME' already exists."
    fi
done
sudo iptables -t nat -A POSTROUTING -s 10.55.1.0/24 ! -o n6br -j MASQUERADE
echo "------------------------------------------------"
echo "Setup Complete. Current Docker Networks:"
docker network ls | grep br

# --- Additional Docker networks used by docker-compose files ---
# Define docker networks to be created for services:
# Format: "NetName|Driver|Subnet|Gateway|ParentBridge"
# Driver: "bridge" or "macvlan". ParentBridge only used for macvlan.
DOCKER_NETWORKS=(
    "ran|bridge|10.53.1.0/24|10.53.1.254|"
    "metrics|bridge|172.19.1.0/24|172.19.1.254|"
    "ue_n3|bridge|10.10.3.0/24|10.10.3.254|"
    "oran-sc-ric_ric_network|bridge|10.0.2.0/24|10.0.2.254|"
    "n2network|bridge|10.53.2.0/24|10.53.2.254|"
    "n3network|bridge|10.10.3.0/24|10.10.3.254|"
)

echo "------------------------------------------------"
echo "Creating additional Docker networks for services..."

for NET in "${DOCKER_NETWORKS[@]}"; do
    IFS='|' read -r NET_NAME DRIVER SUBNET GW PARENT <<< "$NET"

    if docker network inspect "$NET_NAME" >/dev/null 2>&1; then
        echo "[!] Docker network $NET_NAME already exists."
        continue
    fi

    if [ "$DRIVER" = "macvlan" ] && [ -n "$PARENT" ]; then
        docker network create -d macvlan \
            --subnet="$SUBNET" \
            --gateway="$GW" \
            -o parent="$PARENT" \
            "$NET_NAME"
    else
        docker network create -d bridge \
            --subnet="$SUBNET" \
            --gateway="$GW" \
            "$NET_NAME"
    fi
    echo "[OK] Docker network '$NET_NAME' created."
done

echo "------------------------------------------------"
echo "Setup Complete. Created Docker networks:"
docker network ls --format '{{.Name}}' | grep -E "^(ran|metrics|n2network|n3network|ue_n3|oran-sc-ric_ric_network)$" || true