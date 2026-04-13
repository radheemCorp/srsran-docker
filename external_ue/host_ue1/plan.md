# External UE on Host -> gNB in Cluster (N3) Plan

## Goal
Run one UE outside Kubernetes (on the host or host Docker) and make it attach to the gNB pod over the dedicated N3 L2 segment (`10.10.3.0/24`), then pass user-plane traffic end to end via UPF.

## Known topology (target state)
- gNB pod N3 IP: `10.10.3.231/24`
- External UE IP on N3 L2: `10.10.3.234/24` (avoid conflicts with in-cluster UE IPs)
- Host bridge connected to N3: `n3br` with `10.10.3.1/24`
- UPF N3 endpoint (GTP-U): `10.10.3.1:2152`
- UE PDU subnet (through UPF/ogstun): `10.41.0.0/16`

---

## What we discovered so far

- External UE can now reach gNB over N3 and complete attach (RACH, RRC Connected, PDU Session Establishment).
- UE receives a PDU IP (`10.41.0.4` observed), so control-plane path is working.
- ZMQ transport between UE and gNB is established on single-UE ports (`2000/2001`).
- After moving host gateway away from `10.10.3.1`, user-plane path is now working end-to-end for UPF local reachability.
- Verified with captures: GTP-U is bidirectional on gNB/UPF N3 and decapsulated ICMP request/reply appears on UPF `ogstun`.
- UE can now ping `10.41.0.1` successfully.
- Internet path is now confirmed working (`ping 8.8.8.8` success from `ue1`).
- DNS in UE namespace is now confirmed working after resolv.conf override (`ping google.com` success from `ue1`).
- To remove ambiguity, we moved to a single-slice target (`sst=1/sd=000001`) with one SMF/UPF path.

## Problems seen and fixes applied

1. Wrong UE namespace handles (`/run/netns/ueX` stale placeholders)
   - Symptom: `ip netns exec ...` failed with `Invalid argument`.
   - Fix: clean invalid netns files and recreate namespace in `start_ue.sh` flow.

2. Wrong ZMQ endpoint mapping in generated UE config
   - Symptom: UE bound TX socket to gNB IP (`Cannot assign requested address`) or attached never progressed.
   - Fix: corrected `host_ue/config/generate_ue_conf.py` to single-UE mapping:
     - UE TX bind: `tcp://*:2001`
     - UE RX connect: `tcp://<gnb-ip>:2000`

3. IP conflict risk with in-cluster UE endpoint
   - Symptom: ambiguous ARP/session behavior when external UE used same N3 IP as internal UE (`10.10.3.232`).
   - Fix: moved external UE to `10.10.3.234` in `host_ue/docker-compose.yaml` and updated gNB peer in `configs/srsRAN/srsran-gnb/config/srsran-gnb.yaml` to `rx_port=tcp://10.10.3.234:2001`.

4. Missing default route in UE namespace
   - Symptom: `ping 8.8.8.8` returned `Network is unreachable`.
   - Fix: ensure default route is set via `tun_srsue` after successful attach.

5. DNS in UE netns used unreachable container stub
   - Symptom: `Temporary failure in name resolution`.
   - Fix: create `/etc/netns/ue1/resolv.conf` with real resolvers (e.g. `1.1.1.1`, `8.8.8.8`).
   - Note: DNS fix alone does not help until user-plane forwarding works.

6. slice2 resources persisted after kustomize changes
   - Symptom: `open5gs-smf2` and `open5gs-upf2` still running even after removing `slice2` from `slices/kustomization.yaml`.
   - Cause: `kubectl apply -k` does not delete previously-created resources unless prune/delete is used.
   - Fix: explicitly delete legacy slice2 resources (`smf2`, `upf2` deployments/services/configmaps), then re-apply.

7. Open5GS init dependency chain blocked after removing slice2
   - Symptom: `pcf` stuck waiting for `smf2`, then `udm` waiting for `pcf`, then `udr/nssf/bsf` stuck.
   - Cause: stale initContainer dependency in `pcf-deployment.yaml` still referenced `smf2-nsmf`.
   - Additional issue: `udr` waited for `udm`, creating a startup dependency loop (`udm -> pcf -> ... -> nssf -> udr`).
   - Fixes:
     - removed `wait-smf2` initContainer from `configs/open5gs/open5gs/common/pcf/pcf-deployment.yaml`.
     - changed UDR init dependency to MongoDB in `configs/open5gs/open5gs/common/udr/udr-deployment.yaml`.

## Current blocker (brief)

- No functional blocker for single external UE path. Current state is operational end-to-end.
- Remaining work is hardening/automation so route and DNS are set automatically after each attach/container restart.

---

## Phase 1: Baseline checks before starting UE

1. Verify host N3 interface and reachability.
   - `ip -br a show n3br`
   - `ip route | grep 10.10.3.0/24`
   - `ping -c 3 10.10.3.231`
   - Expected: host reaches gNB N3 IP from `n3br` path.

2. Verify gNB pod sees N3 correctly.
   - `kubectl -n open5gs get pod -o wide | grep gnb`
   - `kubectl -n open5gs exec <gnb-pod> -- ip -br a`
   - Expected: N3 interface present with `10.10.3.231/24`.

3. Verify UPF user-plane endpoint.
   - `kubectl -n open5gs exec <upf-pod> -- ip -br a`
   - `kubectl -n open5gs exec <upf-pod> -- ss -lunp | grep 2152`
   - Expected: UPF listens on UDP/2152 and has `10.10.3.1` reachable from gNB.

Debug if failed:
- If host cannot ping `10.10.3.231`, fix L2/L3 path first (Multus attachment, bridge membership, ARP).
- If gNB has wrong N3 IP, fix gNB net-attach definition or pod network annotation.

---

## Phase 2: External UE network namespace/container preparation

4. Create/repair UE network namespace cleanly (important from prior issue).
   - Ensure stale `/run/netns/ueX` placeholders are removed if not `nsfs`.
   - Recreate with `ip netns add ue0` (or use `start_ue.sh` logic that already handles this).
   - Bring loopback up: `ip netns exec ue0 ip link set lo up`.

5. Attach UE namespace/container interface to N3 segment.
   - Assign UE-side N3 IP (`10.10.3.232/24`) on the interface used by srsUE ZMQ transport.
   - Ensure no conflicting IP in `10.10.3.0/24`.
   - Confirm L2 and ARP:
     - `ip netns exec ue0 ip -br a`
     - `ip netns exec ue0 ping -c 3 10.10.3.231`

6. Verify UE config points to gNB N3 IP/ports.
   - In UE config, RF device is ZMQ and points to gNB endpoint (`10.10.3.231`, expected ports `2000/2001` per deployment).
   - Confirm no accidental use of ClusterIP/NodePort for ZMQ path.

Debug if failed:
- If UE cannot ping gNB N3 IP, check ARP in both ends:
  - UE side: `ip netns exec ue0 ip neigh`
  - gNB side: `kubectl -n open5gs exec <gnb-pod> -- ip neigh`
- If ARP incomplete, check bridge/macvlan attachment to `n3br` and MTU alignment.

---

## Phase 3: Bring up UE and validate control-plane attach

7. Start UE inside its namespace (`ip netns exec ue0 ...`) and capture logs.
   - Expected attach sequence includes registration and PDU session establishment.
   - Expected line similar to: `PDU Session Establishment successful. IP: 10.41.x.y`.

8. Validate tunnel interface inside UE namespace.
   - `ip netns exec ue0 ip -br a`
   - Expected: `tun_srsue` present and UP.

9. Set default route via UE tunnel.
   - Run `add_route.sh` (after namespace is valid).
   - Verify: `ip netns exec ue0 ip route` includes `default dev tun_srsue`.

Debug if failed:
- If `ip netns exec` gives `Invalid argument`, namespace handle is broken again (recreate namespace and retry).
- If attach fails, inspect both UE log and gNB log timestamps side-by-side.

---

## Phase 4: Verify user-plane packet flow hop by hop

10. Generate traffic from UE namespace.
    - `ip netns exec ue0 ping -c 3 10.41.0.1`
    - `ip netns exec ue0 ping -c 3 8.8.8.8`

11. Capture on gNB N3 for GTP-U.
    - `kubectl -n open5gs exec <gnb-pod> -- tcpdump -n -i <gnb-n3-if> udp port 2152`
    - Expected when UE pings: uplink/downlink GTP-U packets to/from `10.10.3.1:2152`.

12. Capture on UPF N3 and ogstun.
    - `kubectl -n open5gs exec <upf-pod> -- tcpdump -n -i <upf-n3-if> udp port 2152`
    - `kubectl -n open5gs exec <upf-pod> -- tcpdump -n -i ogstun`
    - Expected: GTP-U arrives on N3 interface and decapsulated ICMP appears on `ogstun`.

13. Validate UPF forwarding/NAT.
    - `kubectl -n open5gs exec <upf-pod> -- sysctl net.ipv4.ip_forward`
    - `kubectl -n open5gs exec <upf-pod> -- iptables -t nat -S`
    - Expected: forwarding enabled and masquerade/SNAT for `10.41.0.0/16` toward external network.

Debug matrix:
- Traffic leaves UE but no GTP-U on gNB -> gNB user-plane not forwarding (config mismatch or session not bound).
- GTP-U on gNB but not on UPF -> N3 routing/firewall/ACL between gNB and UPF.
- GTP-U reaches UPF but no `ogstun` packets -> TEID/session mismatch or UPF session state issue.
- `ogstun` has packets but no Internet reply -> UPF NAT/forwarding or upstream route issue.

---

## Phase 5: DNS and application reachability

14. Fix DNS inside UE namespace (if needed).
    - Prior context shows Docker stub `127.0.0.11` is not reachable from UE netns.
    - Use public/internal resolver inside UE netns (for example `1.1.1.1` or site DNS).

15. End-to-end validation.
    - `ip netns exec ue0 traceroute google.com`
    - `ip netns exec ue0 curl -I https://www.google.com`
    - Expected: first hop via UPF side (`10.41.0.1`) and successful external reachability.

---

## Recommended execution order (quick runbook)

1. Prove L2/L3 on N3 (`10.10.3.232` <-> `10.10.3.231`).
2. Start UE in a valid namespace and confirm PDU session IP assignment.
3. Confirm default route via `tun_srsue`.
4. Run simultaneous tcpdump on gNB N3 + UPF N3 + UPF ogstun while pinging from UE.
5. If decap works but Internet fails, fix UPF NAT/forwarding.
6. Fix DNS only after raw IP ping works.

## Next steps (from current state)

1. Keep only one UPF active for testing (temporarily scale down the second UPF) to remove PFCP/session ambiguity.
2. Restart gNB and UE, then confirm attach and `tun_srsue` route in `ue1`.
3. While pinging `10.41.0.1` from UE, capture simultaneously:
   - gNB `n3`: `udp port 2152`
   - selected UPF `n3`: `udp port 2152`
   - selected UPF `ogstun`: `icmp`
4. Check SMF and selected UPF logs for PFCP session/PDR/FAR install for IMSI `001010000000001` (or UE used in test).
5. On selected UPF, verify `ip_forward=1` and NAT/masquerade for `10.41.0.0/16`.
6. After `ping 10.41.0.1` succeeds, test `ping 8.8.8.8`, then DNS (`google.com`).

## Immediate next actions (after latest logs)

1. Persist route setup in UE workflow:
   - ensure `add_route.sh` (or start script) always sets `default dev tun_srsue` for active UE namespace.

2. Persist DNS setup per UE namespace:
   - ensure `/etc/netns/ueX/resolv.conf` is created automatically with valid resolvers after namespace creation.

3. Add a post-attach smoke test command set:
   - `ping 10.41.0.1`
   - `ping 8.8.8.8`
   - `ping google.com`

4. Optional: document/automate single-UPF operational mode (slice1 only) for reproducible lab bring-up.

## Final validated state (latest)

- UE attach: successful (`PDU Session Establishment successful`, UE IP `10.41.0.3`).
- UE route: `default dev tun_srsue` set and active.
- UPF local reachability: `ping 10.41.0.1` successful.
- Internet reachability: `ping 8.8.8.8` successful.
- DNS resolution in UE netns: successful with `/etc/netns/ue1/resolv.conf` resolvers.
- Application-level hostname test: `ping google.com` successful.

## Automation update applied

Updated `host_ue/config/start_ue.sh` to reduce manual steps after attach:

- Writes per-namespace DNS file automatically:
  - `/etc/netns/ueX/resolv.conf`
  - defaults: `1.1.1.1`, `8.8.8.8`
  - overridable via `UE_DNS1`, `UE_DNS2`

- Starts a background route helper that waits for `tun_srsue` and sets:
  - `default dev tun_srsue scope link`
  - wait timeout default: `120s` (overridable via `ROUTE_WAIT_SECONDS`)

Expected outcome:
- After successful attach, UE namespace gets default route and DNS automatically without manual `ip route` or `resolv.conf` edits.

## Operational note: UE restart may require gNB restart

Observed behavior:
- Restarting UE alone sometimes leaves UE stuck at `Attaching UE...`.
- Restarting gNB then allows immediate UE attach success.

Likely cause:
- ZMQ TCP session/state between gNB and UE (`2000/2001`) can remain stale after abrupt UE process restart.
- gNB may keep old radio/session context and not recover fast enough for the next attach attempt.

Current workaround:
1. Prefer graceful UE stop (`Ctrl+C`) before restarting UE process.
2. If UE remains stuck in `Attaching UE...` for >20s, restart gNB process/pod.

Recommended future hardening:
- Add explicit pre-start cleanup in UE workflow (ensure no old `srsue` process remains).
- Add health check that verifies fresh ZMQ sessions (`ss -tnp` on gNB) before new attach attempts.

## Change log (latest experiment)

Applied to reduce deployment to single SMF/UPF and single slice path:

1. `configs/open5gs/open5gs/slices/kustomization.yaml`
   - Removed `slice2` from `resources`.

2. `configs/open5gs/open5gs/common/amf/amf-configmap.yaml`
   - Removed `s_nssai` entry `sst: 2, sd: 000002`.

3. `configs/open5gs/open5gs/common/nssf/nssf-configmap.yaml`
   - Removed NSI mapping for `sst: 2, sd: 000002`.

4. `configs/srsRAN/srsran-gnb/config/srsran-gnb.yaml`
   - Removed second `slicing` entry (`sst: 2, sd: 000002`).

Why:
- Keep all control/user-plane selection deterministic for `internet` on slice1 (`sst=1/sd=000001`).
- Avoid session steering ambiguity across multiple SMF/UPF instances while debugging UE user-plane.

Additional update (N3 gateway conflict mitigation):

5. `host_ue/docker-compose.yaml`
   - Changed macvlan gateway from `10.10.3.1` to `10.10.3.254`.
   - Reason: avoid overlap with UPF N3 endpoint at `10.10.3.1`.
   - Expected effect: gNB ARP for `10.10.3.1` resolves to UPF MAC only.

## Host network change required (manual)

To match the compose update, move host bridge IP from `10.10.3.1/24` to `10.10.3.254/24`:

- `sudo ip addr del 10.10.3.1/24 dev n3br || true`
- `sudo ip addr add 10.10.3.254/24 dev n3br`
- `ip -br a show n3br`

Then recreate external UE network/container:

- `cd host_ue`
- `docker compose down`
- `docker compose up -d`
- `docker exec -it srsran_ue_external ip route`

Validation after host/compose gateway move:

1. On gNB pod:
   - `ip neigh show 10.10.3.1`
   - Confirm MAC belongs to UPF N3 interface.
2. Re-attach UE and verify `tun_srsue` + default route.
3. Re-run ping `10.41.0.1` with simultaneous tcpdump (gNB n3, UPF n3, UPF ogstun).
4. If successful, test `8.8.8.8` then `google.com`.

## Single SMF/UPF reduction plan (new)

Goal: remove slice2 (`smf2`/`upf2`) and run only slice1 (`smf1`/`upf1`) to eliminate PFCP/session ambiguity.

Open5GS files to update:

1. `configs/open5gs/open5gs/slices/kustomization.yaml`
   - Keep only `slice1` in `resources`.
   - Remove `slice2` from the kustomize deployment graph.

2. `configs/open5gs/open5gs/common/amf/amf-configmap.yaml`
   - In `plmn_support.s_nssai`, keep only `sst: 1, sd: 000001`.
   - Remove `sst: 2, sd: 000002`.

3. `configs/open5gs/open5gs/common/nssf/nssf-configmap.yaml`
   - Keep only NSI mapping for `sst: 1, sd: 000001`.
   - Remove mapping for `sst: 2, sd: 000002`.

Optional hardening:
- Keep `slice2/*` files in repo but not referenced by kustomization (easy rollback).
- Verify subscriber profiles use `internet` and `sst=1/sd=000001` only.

gNB files to update for single-slice mode:

4. `configs/srsRAN/srsran-gnb/config/srsran-gnb.yaml`
   - Keep only one `slicing` entry:
     - `sst: 1`
     - `sd: 000001`
   - Keep `ru_sdr.device_args` aligned to external UE IP (`rx_port=tcp://10.10.3.234:2001`) for single external UE.

5. `configs/srsRAN/srsran-gnb/gnb-deployment.yaml`
   - No mandatory changes for single SMF/UPF.
   - Keep current N3 IP (`10.10.3.231/24`) and restart deployment after configmap change.

Validation after applying single-slice changes:

1. Apply Open5GS + gNB manifests and restart pods.
2. Confirm only one SMF/UPF pod pair exists (`open5gs-smf1`, `open5gs-upf1`).
3. Re-attach UE and confirm PDU session IP in `10.41.0.0/16`.
4. Repeat captures:
   - gNB `n3`: GTP-U present
   - UPF `n3`: GTP-U present
   - UPF `ogstun`: decapsulated ICMP present
5. Then validate route + NAT + DNS to reach `google.com`.

Cleanup commands for persisted slice2 objects:

- `kubectl -n open5gs delete deployment open5gs-smf2 open5gs-upf2 --ignore-not-found`
- `kubectl -n open5gs delete service smf2-nsmf --ignore-not-found`
- `kubectl -n open5gs delete configmap smf2-configmap upf2-configmap --ignore-not-found`
- `kubectl -n open5gs apply -k configs/open5gs/open5gs`
- `kubectl -n open5gs get deploy | egrep 'smf|upf'`
- Expected: only `open5gs-smf1` and `open5gs-upf1` remain.

Recovery commands for dependency-stuck rollout:

- `kubectl -n open5gs apply -k configs/open5gs/open5gs`
- `kubectl -n open5gs rollout restart deploy/open5gs-pcf deploy/open5gs-udr deploy/open5gs-udm deploy/open5gs-nssf deploy/open5gs-bsf`
- `kubectl -n open5gs get pods`
- Expected order: `udr` -> `nssf` -> `bsf`, and `pcf` no longer waits for `smf2`.

## Common pitfalls checklist
- Stale `/run/netns/ueX` files (not `nsfs`) causing `ip netns exec` failures.
- UE ZMQ endpoint targeting wrong address family/interface (must use N3-reachable IP).
- Assuming NodePort is needed for ZMQ (not needed when L2/L3 direct reachability exists).
- Missing UPF masquerade for UE subnet `10.41.0.0/16`.
- DNS resolver inherited from container namespace but unreachable from UE netns.
