# 20260420 — UE can't reach gateway: ogstun subnet mismatch

- **Date:** 2026-04-20
- **Area:** networking
- **Status:** Resolved
- **Components:** open5gs_5gc (SMF/UPF/ogstun), multi_ue / srsue

## Summary
- UEs attached and got a PDU session + IP (e.g. `10.41.0.3/24`) and `tun_srsue` came up,
  but could not ping their gateway (`10.41.0.1`) or the internet.
- Root cause: the UE address pool and the `ogstun` interface were on **different
  subnets** — UE on `10.41.0.0/24`, `ogstun` on `10.45.x.x/24` — so UE packets had no
  on-link UPF gateway.
- Fix: pin the SMF/UPF session subnet + gateway to match the UE pool.

## Context / setup
- srsRAN multi-UE ZMQ bridge + Open5GS 5GC + gNB + two UEs.
- `tcpdump` on the bridge showed traffic between bridge and gNB, but no end-to-end path.

## Investigation / what was determined
- UE had a default route via `tun_srsue` and an address in `10.41.0.0/24`, expecting
  gateway `10.41.0.1`.
- `ogstun` in the 5GC had `10.45.x.x/24` addresses (`10.45.0.1/24`, `10.45.1.1/24`, …)
  — **not** `10.41.0.1/24`.
- `open5gs-5gc.yml` used variables for the UE pool/gateway that did not resolve to the
  expected `10.41.0.0/24`.

## Root cause
- **Subnet mismatch** between the UE-assigned address (`10.41.0.x/24`, gw `10.41.0.1`)
  and the `ogstun` interface (`10.45.x.x/24`, no `10.41.0.1`). The UE and UPF were on
  different L3 subnets.

## Resolution / workaround
- Set the SMF/UPF session subnet + gateway explicitly to match the UE pool:
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
- After restarting 5GC/gNB/UE, `ogstun` came up as `10.41.0.1/24` and UEs could ping the
  gateway and reach the internet.

> Note: the current two-cell setup uses the `10.45.0.0/24` pool (UE IPs `10.45.0.2`…);
> the lesson is the invariant, not the specific subnet.

## Lessons / gotchas
- The UE IP pool and the `ogstun` subnet/gateway **must** match for user-plane
  connectivity.
- If a UE can't ping its gateway, check `ogstun` (`ip a` in `open5gs_5gc`) against the
  UE's subnet before chasing radio/bridge issues.

## References
- `srsRAN_Project/gnb-zmq/.../open5gs-5gc.yml` — SMF/UPF `session` subnet/gateway.
- Related: [20260420-open5gs-no-internet-macvlan-ovs.md](./20260420-open5gs-no-internet-macvlan-ovs.md).
- Original note authored by GitHub Copilot, 2026-04-20.
