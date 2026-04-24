# Multi-UE Internet Connectivity Issue: Root Cause and Resolution

## Problem Summary

When running the srsRAN multi-UE ZMQ bridge setup with Open5GS 5GC, gNB, and two UEs, the UEs were able to attach and obtain a PDU session. The `tun_srsue` interface was created, and the UE received an IP address (e.g., 10.41.0.3/24). However, the UE could not ping its gateway (10.41.0.1) or reach the internet (e.g., 8.8.8.8). tcpdump on the bridge showed traffic flowing between the bridge and gNB, but no end-to-end connectivity.

## Investigation

- The UE had a default route via `tun_srsue` and an IP in 10.41.0.0/24.
- The ogstun interface in the Open5GS 5GC container had addresses in the 10.45.x.x range (e.g., 10.45.0.1/24, 10.45.1.1/24, ...), but not 10.41.0.1/24.
- The Open5GS config (`open5gs-5gc.yml`) was using variables for the UE IP range and gateway, which did not resolve to the expected 10.41.0.0/24 subnet.
- As a result, the UE and UPF (ogstun) were on different subnets, so packets from the UE could not reach the UPF gateway.

## Root Cause

**Subnet mismatch between the UE-assigned address and the ogstun interface in Open5GS.**
- UE: 10.41.0.x/24, expects gateway 10.41.0.1
- ogstun: 10.45.x.x/24, does not include 10.41.0.1

## Solution

- The Open5GS config was updated to explicitly set the UE IP pool and gateway to match the expected subnet:
  ```yaml
  smf:
    session:
      - subnet: 10.41.0.0/24
        gateway: 10.41.0.1
  upf:
    session:
      - subnet: 10.41.0.0/24
        gateway: 10.41.0.1
  ```
- After restarting the 5GC, gNB, and UE containers, the ogstun interface was assigned 10.41.0.1/24, matching the UE subnet.
- The UE could then ping its gateway and reach the internet.

## Lessons Learned

- Always ensure the UE IP pool and ogstun interface subnet/gateway match in Open5GS for user-plane connectivity.
- If the UE cannot ping its gateway, check the ogstun interface and Open5GS session config.
- Use tcpdump and ip route/ip a in both UE and 5GC containers to diagnose subnet mismatches.

---

**Author:** GitHub Copilot
**Date:** 2026-04-20
