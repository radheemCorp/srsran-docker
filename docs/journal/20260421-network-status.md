# 20260421 — Bring-up status: per-UE namespace routing fails

- **Date:** 2026-04-21
- **Area:** bring-up
- **Status:** Superseded (the netns-per-UE model below is what `multi_ue` now uses)
- **Components:** srsran_gnb, srsran_srsue, open5gs_5gc, host routing

## Summary
- Container networking up: `n2` (ran), `n3` (ZMQ RF), `n6` (UE PDN), `metrics` exist
  with expected static IPs; gNB↔srsUE ping on N3 works and TCP to `gNB:2101` succeeds.
- Problem: UE namespaces existed but `ue1` had only loopback (no `tun_srsue`/veth), so
  `add_route.sh` failed with "Nexthop has invalid gateway" — per-UE routing broke.
- Root cause: srsUE ran in the container main namespace while an **empty** `ue1`
  namespace was pre-created — a mismatch between where srsUE binds and where routes go.

## Context / setup
- `srsran_srsue` → `10.10.3.232` (n3); `srsran_gnb` → `10.10.3.231` (n3, n2, metrics);
  `open5gs_5gc` → `10.53.1.2` (n2).
- Host uses a macvlan helper (`macvlan_ran`) for L2 access to the macvlan nets and is
  expected to carry a PDN aggregate route (`10.45.0.0/16 via 10.53.1.2`).

## Investigation / what was determined
- `ip netns ls` showed `ue0` and `ue1`, but `ip netns exec ue1 ip addr` showed only
  loopback — no interface in the PDN subnet.
- `add_route.sh` could not add a default route in a namespace with no on-link interface
  → kernel "Nexthop has invalid gateway" (expected for that condition).
- ZMQ TCP connect worked, but message-level bridge operation still needed verifying.

## Root cause
- **Namespace/binding mismatch:** srsUE in the container main namespace + a pre-created
  empty `ueN` namespace. Routes were added to a namespace that had no PDN interface.

## Resolution / workaround
- Adopt one model consistently (Model B was chosen and is what the current `multi_ue`
  setup uses):
  - **Model A (container-level UE):** run srsUE in the container main namespace and
    manage PDN/default routes there.
  - **Model B (netns-per-UE):** let srsUE create `tun_srsue` inside `ueN`
    (`UE_USE_NETNS=true`, container has `NET_ADMIN`), or create a veth and move it into
    `ueN` before starting srsUE. Run `add_route.sh` only after the per-UE interface exists.
- Short-term: stop pre-creating empty namespaces in `start_ue.sh`; ensure the host PDN
  route + macvlan helper:
  ```bash
  sudo ip link add macvlan_ran link eth3 type macvlan mode bridge
  sudo ip addr add 10.53.1.254/24 dev macvlan_ran && sudo ip link set macvlan_ran up
  sudo ip route add 10.45.0.0/16 via 10.53.1.2 dev macvlan_ran
  ```

## Lessons / gotchas
- "Nexthop has invalid gateway" inside a netns means the namespace has no interface on
  the gateway's L2 — create/move an interface in, or add the route in the right namespace.
- Keep `n2` (control), `n3` (ZMQ RF transport), `n6`/PDN (UE data) separate — they carry
  different planes.
- Apply per-UE routes only to namespaces that actually have a PDN interface; log skips.

## References
- `srsue/config/start_ue.sh`, `add_route.sh`.
- Related: [20260420-multi-ue-ogstun-subnet-mismatch.md](./20260420-multi-ue-ogstun-subnet-mismatch.md).
- Verify: `docker inspect srsran_srsue | jq '.[0].NetworkSettings.Networks'`,
  `ip netns exec ue1 ip addr`, `ss -lntp | grep 2101`.
- Original status captured on host `devred`, 2026-04-21.
