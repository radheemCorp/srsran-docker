# 20260414 — ZMQ UE released right after RRC Connect (new gNB config)

- **Date:** 2026-04-14
- **Area:** RAN / ZMQ
- **Status:** Investigating
- **Components:** srsran_gnb, srsue (ZMQ bridge), open5gs_5gc

> Source: `tracks/zmq_ue_drop/` (gnb.log, ue.log, old `zmq_sample.yaml`, new `gnb_zmq.yml`).

## Summary
- gNB starts, the ZMQ bridge connects, both UEs start and attach — then the gNB
  **releases the UE immediately after RRC Connect**, before a PDU session/`tun_srsue`
  exists. The README framed it as "dropped due to inactivity"; the logs show a release
  right after connect, not an idle timeout.
- The old gNB config (`zmq_sample.yaml`) worked; the new one (`gnb_zmq.yml`) does not.
- Not yet root-caused — most likely a core/NAS or config-restructure issue introduced
  with the new `cu_cp` block, not inactivity.

## Context / setup
- ZMQ virtual RF, two UEs over the bridge, Open5GS 5GC. Networks (from the track):
  `ran` 10.53.1.0/24, `n3br` 10.10.3.0/24 (ZMQ RF), `n6br` 10.55.1.0/24,
  `n2network` 10.53.2.0/24, plus `metrics`, `oran-sc-ric_ric_network`.

## Investigation / what was determined
- UE side (`ue.log`): RA succeeds, then release, then no data interface:
  ```
  Random Access Complete.  c-rnti=0x4604, ta=0
  RRC Connected
  Received RRC Release
  Warning: tun_srsue did not appear within 120s
  ```
- gNB side (`gnb.log`): the UE context is torn down right after setup:
  ```
  DU-F1 / CU-CP-F1 / NGAP : UEContextReleaseComplete
  MAC : rnti=0x4604: Discarding UCI PDU. Cause: No UE with provided RNTI exists.
  ```
- Config delta (old `zmq_sample.yaml` → new `gnb_zmq.yml`), key changes:
  - Top-level `amf:` block replaced by a **`cu_cp:`** block:
    `amf.addr 10.10.3.200 → 10.53.1.2`, `bind_addr 10.10.3.231 → 10.53.1.3`,
    added `supported_tracking_areas` (`tac: 7`, `sst: 1`) and `inactivity_timer: 7200`.
  - `cell_cfg` search-space / PRACH stanza reordered (`ss0_index`/`coreset0_index`
    moved under `common`); ZMQ `device_args` and RF rates unchanged.

## Root cause
- **Undetermined in the track.** Evidence points to the UE being released before a PDU
  session is established (NAS/registration or AMF reachability under the new
  `cu_cp.amf` address), rather than the `inactivity_timer` (7200 s is far too long to
  explain an immediate release). The working-vs-broken delta is the new `cu_cp`
  restructure + AMF address change.

## Resolution / workaround
- Open. Next steps: diff the two configs line-by-line and bisect the `cu_cp` block;
  confirm the gNB can reach `amf.addr 10.53.1.2:38412` and that the UE's requested
  S-NSSAI matches `tai_slice_support_list` (`sst: 1`); check 5GC logs for a NAS reject
  at the moment of release (cf. the cause-62 slice-mismatch pattern seen later).

## Lessons / gotchas
- "RRC Release immediately after RRC Connect + `tun_srsue` never appears" is a
  **registration/session** failure, not an inactivity drop — read the 5GC NAS logs, not
  just the gNB scheduler.
- When a config rewrite changes connectivity, bisect the structural delta (here the
  `amf:` → `cu_cp:` move + address change) before chasing radio parameters.

## References
- `tracks/zmq_ue_drop/{gnb.log,ue.log,zmq_sample.yaml,gnb_zmq.yml}`.
- Related slice/NAS-reject pattern: [20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md](./20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md)
  (cause-62 on SST mismatch), [20260420-multi-ue-ogstun-subnet-mismatch.md](./20260420-multi-ue-ogstun-subnet-mismatch.md).
