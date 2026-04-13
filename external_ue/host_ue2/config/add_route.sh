#!/bin/bash

# Robustly add default route inside each UE namespace using the tun_srsue device
# Falls back to via 10.41.0.1 only if device-based route fails

for i in 0 1 2 3 4 5 6 7 8 9 10; do
    NS="ue$i"

    # Skip missing namespaces
    if ! ip netns list | grep -qw "${NS}"; then
        echo "Skipping ${NS}: namespace not present"
        continue
    fi

    # Remove any existing default route
    ip netns exec ${NS} ip route del default 2>/dev/null || true

    # Prefer adding default via the tunnel device (no gateway needed)
    if ip netns exec ${NS} ip link show tun_srsue >/dev/null 2>&1; then
        echo "Configuring ${NS}: setting default dev tun_srsue"
        ip netns exec ${NS} ip route add default dev tun_srsue || \
            echo "Failed to add default dev route in ${NS}"
    else
        echo "${NS} has no tun_srsue device, attempting via gateway"
        ip netns exec ${NS} ip route add default via 10.41.0.1 2>/dev/null || \
            echo "Failed to add default via gateway in ${NS} (no tun device)"
    fi

done
