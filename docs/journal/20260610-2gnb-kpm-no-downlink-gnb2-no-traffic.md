# 20260610 — 2 gNB KPM capture: gNB1 uplink-only (no DL), gNB2 no traffic, UE3/UE4 unrouted

- **Date:** 2026-06-10
- **Area:** E2 / KPM
- **Status:** Explained (each observation tracked to a known cause; see References)
- **Components:** oran-sc-ric (kpm_mon_xapp), srsran_gnb, srsran_gnb2, multi_ue, open5gs_5gc

> Distilled from a raw KPM xApp + ping capture taken ~01:05–01:08 on 2026-06-10
> (original file `100620206-2gnb-setup.md`). The full per-indication dump is trimmed to
> representative samples below.

## Summary
- Running the KPM xApp per DU node surfaced three things at once:
  1. **gNB1 (`gnbd_001_001_000001_0`): healthy uplink, zero downlink** — `DRB.UEThpUl`
     steady ~2500–3500 kbps, `DRB.UEThpDl` ≈ 0.
  2. **gNB2 (`gnbd_001_001_000002_0`): no traffic at all** — every indication
     `DRB.UEThpDl=0, DRB.UEThpUl=0`.
  3. **UE3/UE4 had no route** (`ping: connect: Network is unreachable`); UE1/UE2 reached
     the cell but showed 100% loss to `10.45.0.1` during the capture.
- These are not three unrelated bugs — each maps to a known cause (see Root cause).

## Context / setup
- Two-cell ZMQ topology (gNB1 slice 1 / UE1,UE2; gNB2 slice 2 / UE3,UE4), one `multi_ue`
  container, oran-sc-ric KPM xApp run sequentially per DU node (report style 1,
  `DRB.UEThpDl,DRB.UEThpUl`).

## Investigation / what was determined
- **gNB1 — uplink only.** Representative indications:
  ```
  --Metric: DRB.UEThpDl, Value: [0.0]
  --Metric: DRB.UEThpUl, Value: [3183.0]      # ... steady ~2500-3500, DL stays ~0
  ```
  Uplink is real and healthy; downlink is flat zero because the traffic generator only
  ever sent UE→server (uplink).
- **gNB2 — all zeros.** Every indication for `gnbd_001_001_000002_0` read
  `DRB.UEThpDl=0, DRB.UEThpUl=0` — cell 2's UEs were not passing data.
- **UE routing.** From the UE netns:
  ```
  ue4 ping 10.45.0.1  -> connect: Network is unreachable      # no default route
  ue3 ping 10.45.0.1  -> connect: Network is unreachable
  ue1 ping 10.45.0.1  -> 15 packets, 100% packet loss          # reached link, no data
  ue2 ping 10.45.0.1  -> 100% packet loss
  ue4 ping 8.8.8.8 / google.com -> Network unreachable / name resolution failure
  ```

## Root cause
- **No downlink (gNB1 DL=0):** the UE traffic wrapper was **uplink-only** — every
  scenario ran iperf3 client UE→server with no `-R`/`--bidir`, so the DU never scheduled
  PDSCH and `DRB.UEThpDl` was always ~0. (Fixed later that day — see References.)
- **gNB2 no traffic + UE3/UE4 unreachable:** cell-2 UEs were not attached/routed — at
  this point their PDU session/route was not up (the slice-2 provisioning + per-UE route
  path), so no DRB traffic reached gNB2.
- **UE1/UE2 100% loss under load:** consistent with bufferbloat/over-load on the cell
  during the uplink saturation, later tied to the RLC-wedge / host-CPU findings.

## Resolution / workaround
- Downlink: added `--reverse` / `--bidir` to `run_scenario.sh` + `ue_export.py` so the
  test drives DL as well as UL.
- gNB2/UE routing: tracked under the slice-provisioning + reattach work in the stability
  entry; once UE3/UE4 are correctly attached to slice 2 they ping the gateway 0% loss
  when idle.

## Lessons / gotchas
- `DRB.UEThpDl = 0` with healthy `DRB.UEThpUl` usually means the **traffic is uplink-only**,
  not a KPM fault — check the iperf3 direction before suspecting E2/KPM.
- `DRB.UEThpUl = 0` on a whole DU node almost always means that cell's UEs aren't passing
  data (unattached, unrouted, or RLC-wedged) — not a subscription problem.
- "Network is unreachable" from a UE netns = no default route (attach/route not up);
  distinct from 100% packet loss (link reached, data not flowing).

## References
- Follow-on / fixes: [20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md](./20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md)
  (bidir traffic support, slice-2 SST fix, ZMQ reattach, host-CPU root cause).
- KPM measurement-provider caveats: [20260606-e2sm-kpm-per-ue-cqi-rsrp-rsrq-zero.md](./20260606-e2sm-kpm-per-ue-cqi-rsrp-rsrq-zero.md).
- Runbook: [../RUNBOOK_2GNB_2SLICE.md](../RUNBOOK_2GNB_2SLICE.md) (KPM xApp, per-gNB sequential).
