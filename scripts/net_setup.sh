#!/usr/bin/env bash
set -euo pipefail

# net_setup.sh
# Idempotent creation of OVS bridges, Docker macvlan/bridge networks,
# enable IP forwarding and add MASQUERADE rules for outbound internet.

OUT_IF=${OUT_IF:-eth3}
if [ -z "$OUT_IF" ]; then
  OUT_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}') || true
  OUT_IF=${OUT_IF:-eth0}
fi

echo "Using external interface: $OUT_IF"

echo "Cleaning old networks (non-fatal)..."
docker network rm ran metrics n3br oran-sc-ric_ric_network n2network n3network n2br n3br n4br n6br >/dev/null 2>&1 || true

# # 2. OVS & MACVLAN NETWORKS (Physical/Infrastructure Layer)
# # Format: "BridgeName|Subnet|Gateway|MTU"
# OVS_NETS=(
#     "ran|10.53.1.0/24|10.53.1.254|1450"
# )

# echo "Setting up OVS Bridges and Macvlan..."
# for NET in "${OVS_NETS[@]}"; do
#     IFS='|' read -r BR SUBNET GW MTU <<< "$NET"

#     # Create OVS Bridge if missing
#     sudo ovs-vsctl --may-exist add-br "$BR"
#     sudo ip link set "$BR" mtu "$MTU" || true

#     # Add address only if missing
#     if ! ip -4 addr show dev "$BR" | grep -q "${GW}"; then
#         sudo ip addr add "$GW/24" dev "$BR" || true
#     fi
#     sudo ip link set "$BR" up

#     # Create Macvlan network riding on the OVS bridge (idempotent)
#     if ! docker network inspect "$BR" >/dev/null 2>&1; then
#         docker network create -d macvlan --subnet="$SUBNET" --gateway="$GW" -o parent="$BR" "$BR"
#     fi
# done

# 3. DOCKER INTERNAL BRIDGES (Service Layer)
# Format: "NetName|Subnet|Gateway"
BRIDGE_NETS=(
    "metrics|172.19.1.0/24|172.19.1.254"
    "ran|10.53.1.0/24|10.53.1.254"
)
echo "Setting up Docker Internal Bridges..."
for NET in "${BRIDGE_NETS[@]}"; do
    IFS='|' read -r NAME SUBNET GW <<< "$NET"
    if ! docker network inspect "$NAME" >/dev/null 2>&1; then
        docker network create -d bridge --subnet="$SUBNET" --gateway="$GW" "$NAME"
    fi
done

# 4. FINAL TOUCHES
# Enable IPv4 forwarding
echo "Enabling IPv4 forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo mkdir -p /etc/sysctl.d
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-srsran.conf >/dev/null

# Add MASQUERADE rules for each OVS subnet so containers on macvlan can reach internet
echo "Installing MASQUERADE rules (via $OUT_IF)..."
for NET in "${OVS_NETS[@]}"; do
    IFS='|' read -r BR SUBNET GW MTU <<< "$NET"
    if ! sudo iptables -t nat -C POSTROUTING -s "$SUBNET" -o "$OUT_IF" -j MASQUERADE >/dev/null 2>&1; then
        sudo iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$OUT_IF" -j MASQUERADE
    fi
done

echo "Done. Subnets organized and isolated."
docker network ls --format "table {{.Name}}\t{{.Driver}}" | grep -E 'ran|metrics|ric|network' || true