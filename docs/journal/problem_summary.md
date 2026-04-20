# Problem summary — container networking (Open5GS / UE / gNB)

Date: 2026-04-20

## Short summary
- Symptoms: `open5gs` container initially could not reach the internet (ping to 8.8.8.8 returned "Destination Host Unreachable"). UE network namespaces could reach their local gateway (10.41.0.1) but not the wider internet.
- Goal: preserve existing `ran` and `n3br` connectivity (gNB <-> core and gNB <-> UE bridge) while restoring internet access for `open5gs` and UEs.

## Key findings
- The environment uses a mix of Docker `macvlan` networks (ran, n3br, n4br, n6br) and Docker `bridge` networks (metrics, oran-sc-ric_ric_network, n2network).
- `macvlan` networks were created using OVS bridges as the macvlan parent. Using macvlan on an OVS bridge caused L2/ARP issues: containers on `n6br` (10.55.1.0/24) could not ARP to their gateway, so traffic never left the container.
- Host-side checks: `net.ipv4.ip_forward=1` was enabled and many MASQUERADE rules existed. The host could ping the internet and the gateways. Some NAT rules were missing/needed for UE subnet (10.41.0.0/24).
- Reverse-path filtering (rp_filter) and OVS/macvlan parent configuration were identified as likely causes for packets being dropped in the kernel before NAT.

## Actions taken
- Added idempotent `scripts/net_setup.sh` and `scripts/net_cleanup.sh` improvements to detect external interface, enable IP forwarding, and (idempotently) install MASQUERADE rules for OVS subnets.
- Short-term mitigation: added a new Docker `internet` bridge and attached it (first) to the `5gc` service in `srsRAN_Project/gnb-zmq/docker-compose.yml`. This gives `open5gs` a Docker-NAT default route (172.30.0.0/24) while preserving `ran`/`n6br`/`n3br` macvlan attachments.
- Verified: `open5gs` now shows `default via 172.30.0.1 dev eth0` and can ping 8.8.8.8. gNB and UE connectivity over `ran`/`n3br` remain unchanged.

## Recommended next steps (options)
- Keep the `internet` bridge (recommended minimal-change fix). Optionally remove the hardcoded `ipv4_address` so Docker assigns the IP automatically.
- Or fix the macvlan/OVS setup: use the physical NIC as macvlan parent (e.g., `-o parent=eth4`) or connect OVS to the NIC with proper patch ports so ARP/forwarding works. This requires OVS network changes and careful testing.
- Ensure `iptables` MASQUERADE and `FORWARD` rules exist for the UE subnet (10.41.0.0/24). Persist them in `scripts/net_setup.sh`.
- For troubleshooting: run `tcpdump` on the host (`n6br`, `eth4`) and check `conntrack` when reproducing failure to see where packets are lost.

## Useful verification commands
- From host:
  - `ip addr show ran n6br n3br`
  - `sysctl net.ipv4.ip_forward`
  - `sudo iptables -t nat -L POSTROUTING -n -v`
  - `sudo iptables -L FORWARD -n -v`
  - `sudo tcpdump -n -i n6br icmp or arp`
- From `open5gs` container:
  - `ip route; ip addr; ping -c3 8.8.8.8`
- From UE netns:
  - `ip netns exec ue1 ping -c3 8.8.8.8`

## Files changed / created during investigation
- `srsRAN_Project/gnb-zmq/docker-compose.yml` — added `internet` bridge for `5gc` (quick mitigation)
- `scripts/net_setup.sh` / `scripts/net_cleanup.sh` — made idempotent; add ip_forward and MASQUERADE handling

If you want, I can: (A) revert the compose `internet` change and instead rework macvlan parents, or (B) keep the bridge and remove static IPs, or (C) add persistent firewall rules to `net_setup.sh`. Tell me which and I will implement it.
