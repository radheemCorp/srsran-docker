# 20260420 — Open5GS / UEs have no internet (macvlan-on-OVS ARP failure)

- **Date:** 2026-04-20
- **Area:** networking
- **Status:** Mitigated
- **Components:** open5gs_5gc, host networking (OVS / macvlan), scripts/net_setup.sh

## Summary
- `open5gs` could not reach the internet (`ping 8.8.8.8` → "Destination Host
  Unreachable"). UE netns could reach their local gateway but not the wider internet.
- Root cause: Docker `macvlan` networks were parented on **OVS bridges**, which breaks
  L2/ARP — containers on `n6br` (10.55.1.0/24) could not ARP their gateway, so traffic
  never left the container. Missing NAT for the UE subnet compounded it.
- Mitigation: gave `open5gs` a normal Docker-NAT path via a new `internet` bridge and
  made the host NAT setup idempotent. `ran`/`n3br`/`n6br` macvlan attachments preserved.

## Context / setup
- Mixed networking: Docker `macvlan` nets (`ran`, `n3br`, `n4br`, `n6br`) + Docker
  `bridge` nets (`metrics`, `oran-sc-ric_ric_network`, `n2network`).
- Host had `net.ipv4.ip_forward=1` and many MASQUERADE rules; the host itself could
  ping the internet and the gateways.

## Investigation / what was determined
- Containers on `n6br` (10.55.1.0/24) could not ARP their gateway → packets never left.
- `macvlan` was created with an **OVS bridge as the macvlan parent**; macvlan-on-OVS
  does not pass ARP/L2 the way macvlan-on-NIC does.
- Reverse-path filtering (`rp_filter`) and the OVS/macvlan parent config were dropping
  packets in the kernel before NAT.
- Some MASQUERADE rules for the UE subnet (10.41.0.0/24) were missing.

## Root cause
- **macvlan parented on an OVS bridge** → broken ARP/forwarding for container egress,
  plus missing NAT for the UE subnet.

## Resolution / workaround
- Short-term mitigation (applied): added a Docker `internet` bridge and attached it
  **first** to the `5gc` service in `srsRAN_Project/gnb-zmq/docker-compose.yml`, giving
  `open5gs` a Docker-NAT default route (172.30.0.0/24) while keeping the
  `ran`/`n6br`/`n3br` macvlan attachments. Verified `open5gs` then had
  `default via 172.30.0.1 dev eth0` and could ping 8.8.8.8.
- Made `scripts/net_setup.sh` / `scripts/net_cleanup.sh` idempotent: detect the external
  interface, enable IP forwarding, install MASQUERADE rules for the OVS subnets.
- Proper fix (deferred): parent macvlan on the **physical NIC** (`-o parent=eth4`) or
  wire OVS to the NIC with proper patch ports so ARP/forwarding works.

## Lessons / gotchas
- Don't parent Docker macvlan on an OVS bridge — use the physical NIC.
- If a container has an IP but can't reach its gateway, suspect L2/ARP (macvlan parent,
  `rp_filter`) before NAT.
- Ensure MASQUERADE + FORWARD rules exist for the UE subnet and persist them in
  `net_setup.sh`.

## References
- `srsRAN_Project/gnb-zmq/docker-compose.yml` — `internet` bridge for `5gc`.
- `scripts/net_setup.sh`, `scripts/net_cleanup.sh` — idempotent NAT / ip_forward.
- Related: [20260420-multi-ue-ogstun-subnet-mismatch.md](./20260420-multi-ue-ogstun-subnet-mismatch.md),
  [20260421-network-status.md](./20260421-network-status.md).
- Verify: `sudo iptables -t nat -L POSTROUTING -n -v`, `sudo tcpdump -n -i n6br icmp or arp`,
  from `open5gs`: `ip route; ping -c3 8.8.8.8`.
