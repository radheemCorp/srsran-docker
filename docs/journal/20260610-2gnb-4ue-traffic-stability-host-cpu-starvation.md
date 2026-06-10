# 20260610 — 2 gNB / 2 slice / 4 UE traffic run: UEs wedge under load (host CPU starvation), + bidirectional traffic support

Date: 2026-06-10

> Paths below are relative to the repo root `/home/radr/pers/srsran-docker/`.
> Branch: `approach-a-two-cell-slicing`. Procedure followed:
> `docs/RUNBOOK_2GNB_2SLICE.md`.

## Summary
- Goal: with the rest of the stack already up (RIC, `gnb`+`gnb2`+5GC, monitoring),
  start `multi_ue`, confirm all 4 UEs ping `10.45.0.1` + `google.com`, then run
  bidirectional traffic for 30 min checking ping + the internal video test every
  5 min, watching the monitoring stack and KPM xApp for stability.
- **Connectivity is fine.** All 4 UEs attach to the correct slice/cell and ping
  both the gateway and the internet with 0% loss **when idle**.
- **The data plane is not stable under sustained multi-UE load.** On essentially
  every full-load traffic run, **one or more UEs wedge their RLC DRB** (the runbook's
  "RLC DRB wedge") and stop passing data until the gNB is cycled and the UEs re-attach.
- **Root cause is host CPU starvation, not a RAN/config bug.** The host is an 8-core
  box running at **load average ~27–32**. srsRAN ZMQ is hard real-time; when the host
  can't feed samples on time you get `Completed 0 of 23040 samples` underruns, and
  those sample slips corrupt uplink RLC AM segmentation → the DRB wedge. Reducing the
  bitrate but **adding** downlink made it *worse* (downlink adds PDSCH CPU cost).
- **Two side fixes landed this session:**
  1. Slice-2 provisioning was stale (UE3/UE4 were on `sst:1`, rejected with NAS
     cause 62). Re-running `open5gs_add_ue.sh` with the slice-2 CSV restored `sst:2`.
  2. The traffic wrapper was **uplink-only**, so downlink KPM was always ~0. Added
     `--reverse` / `--bidir` passthrough to `run_scenario.sh` + `ue_export.py` so the
     video test can drive uplink **and** downlink (`iperf3 -R` / `--bidir`).
- **The 30-min run was not completed** — see the decision at the end. The experiment
  as specified (4 UEs, bidirectional, 30 min) is not sustainable at the current host load.

## Context / setup
- Topology per the runbook: `gnb` (PCI 1, slice `sst:1`, UE1/UE2 = `10.45.0.2/.3`)
  and `gnb2` (PCI 2, slice `sst:2`, UE3/UE4 = `10.45.0.5/.6`). All 4 srsUEs run in one
  `multi_ue` container; two co-located bridges split them across the two gNBs.
- iperf3 servers live in `open5gs_5gc` on the UE gateway `10.45.0.1`, ports 5201–5204.
- KPM xApp (`kpm_mon_xapp.py`, report style 1, `DRB.UEThpDl,DRB.UEThpUl`) run against
  one DU node at a time (RIC static routing only delivers to the default RMR port).

## Timeline / what was determined

### 1. Slice-2 UEs rejected — stale SST (NAS cause 62)
On the first `multi_ue` start, UE1/UE2 attached but **UE3/UE4 completed RA + RRC then
got `Received RRC Release`** (no PDU session). 5GC logs:
```
amf  ERROR: Default S_NSSAI[SST:1 SD:0xffffff]
amf  ERROR: S_NSSAI[SST:2 SD:0xffffff]
amf  WARNING: Registration reject [62]   # cause 62 = no network slice available
gmm  ERROR: amf_nudm_sdm_handle_provisioned(am-data) failed
```
The slice-2 subscribers existed in mongo but with **`slice.sst = 1`** (only the IP
alloc `10.45.0.5/.6` from the slice-2 CSV had been applied; the SST override had not
stuck from a prior boot). Re-running the documented step fixed it:
```bash
./scripts/open5gs_add_ue.sh --csv srsRAN_Project/gnb-zmq/project-config/subscriber_db_slice2.csv
# -> UE3/UE4 now slice.sst = 2
```
This is exactly the runbook's warning ("Re-run after ANY gnb cycle…"). After this the
UEs still would not re-attach on the same ZMQ ports — see next.

### 2. ZMQ reattach limitation — a UE that attached once needs a fresh gNB
Once a srsUE has attached over a ZMQ port, recreating `multi_ue` alone does **not**
let it re-attach (the gNB-side ZMQ port won't re-handshake). The reliable recovery is
to **cycle the gNB** so both sides start the sample exchange in lockstep again:
```bash
docker compose -f multi_ue/docker-compose.yaml down
./scripts/manage.sh stop gnb && ./scripts/manage.sh start gnb     # also cycles 5GC
# wait both: grep -ac "Cell was activated" /tmp/gnb.log == 1 on each, E2 setup OK
./scripts/open5gs_add_ue.sh --csv .../subscriber_db_slice2.csv    # 5GC mongo reset
for p in 5201 5202 5203 5204; do docker exec -d open5gs_5gc iperf3 -s -p $p; done  # servers die with 5GC
# restart the KPM xApp (its E2 subscription dies with the gNB)
./scripts/manage.sh start multi_ue
```
E2 setup came up clean on every gNB cycle (no stale-E2 / `E2setupFailure`).

### 3. Connectivity gate — PASS (idle)
With all 4 UEs attached to the correct slice/cell (verified: UE1/2 → `SST:1` on
`gnb`, UE3/4 → `SST:2` on `gnb2`; each gNB scheduling RNTIs `0x4601/0x4602`):

| UE | IP | ping 10.45.0.1 | ping google.com |
|----|----|----------------|-----------------|
| UE1 | 10.45.0.2 | 0% loss (~205 ms) | 0% loss (~237 ms) |
| UE2 | 10.45.0.3 | 0% loss | 0% loss |
| UE3 | 10.45.0.5 | 0% loss | 0% loss |
| UE4 | 10.45.0.6 | 0% loss | 0% loss |

Internal + external (NAT) reachability is healthy. RTT ~200 ms is normal for ZMQ
virtual RF.

### 4. Traffic runs — a UE wedges on essentially every full-load run

| Run | Profile | Result |
|-----|---------|--------|
| A | 2M UDP **uplink** ×4 | all 4 flowed ~2.0–2.5 Mbps; **UE3+UE4 (cell2) wedged** at end of run. gNB1 KPM `DRB.UEThpUl ≈ 3347 kbps`, DL ≈ 0 (uplink-only). |
| B | 2M UDP **uplink** ×4 (after recovery) | **UE1 wedged** (`+6609` RLC error lines). UE2/3/4 fine. |
| C | 1M **bidir** ×4 (reduced + downlink) | **UE4 then UE1 wedged**; UE2/UE3 recovered once the stream stopped. gNB1 KPM collapsed to ~0. Host load climbed 27 → 32. |

Wedge signature (in `/tmp/ue<N>.log`), per the runbook:
```
[RLC-NR][E] DRB1: Current SO larger or equal to SDU size when creating SDU segment ...
[RLC-NR][E] DRB1: buffer state - retx - invalid length=-NNN for SN=...
```
A wedged UE: ping = 100% loss **even when idle**, no `ue_traffic` rows, and that cell's
`DRB.UEThpUl` KPM = 0 while the gNB still schedules its RNTIs (PHY/MAC fine — only the
DRB is corrupt). The wedge is **not** cell-specific — it hit cell2 (run A), cell1
(run B), and both (run C) — which points away from a per-gNB config issue.

> Note on ping during load: a **mid-stream** ping shows 100% loss on *all* UEs even
> when data is clearly flowing — that is **bufferbloat** (RTT exceeds the 2 s ping
> timeout under a saturated uplink), not loss. The **idle** ping (after the stream
> stops) is the real connectivity gate: bufferbloat recovers to 0%, a genuine wedge
> stays at 100%.

### 5. Root cause — host CPU starvation
```
$ cat /proc/loadavg
32.09 28.02 25.14 ...        # 8-core host (nproc=8); 3–4× oversubscribed
$ docker stats --no-stream
srsran_gnb   ~187%   srsran_gnb2 ~186%   multi_ue ~164%   python_xapp_runner ~61%
$ grep -ac "Completed 0 of" /tmp/gnb.log   # ZMQ sample underruns
srsran_gnb: 64–86   srsran_gnb2: 64–92
```
The two gNBs alone want ~3.7 cores; with `multi_ue` (~1.6) and the xApp (~0.6) the
real-time stack needs ~6 cores of *guaranteed* headroom, but the host baseline load is
already ~25. Under that contention the ZMQ sample clock slips (`Completed 0 of 23040
samples`), which is precisely what corrupts uplink RLC AM and wedges the DRB. Adding
downlink (run C) increased CPU and made it worse, confirming the mechanism.

**Conclusion: this is a host-capacity ceiling, not a RAN/slicing/config fault.** The
RAN, slicing, E2/KPM, and NAT data path are all correct; they just cannot be driven at
4-UE bidirectional load in real time on this host.

## Changes made this session
- `multi_ue/config/ue_export.py` — added `--reverse` (`iperf3 -R`, downlink) and
  `--bidir` (`iperf3 --bidir`, simultaneous UL+DL) flags; appended to the iperf3
  client argv. Previously the wrapper was uplink-only, so downlink KPM was always ~0.
- `multi_ue/config/run_scenario.sh` — pass `--reverse` / `--bidir` through to
  `ue_export.py`. (`./config` is bind-mounted into `multi_ue`, so edits are live on
  the next container start — no rebuild.)
- `checkpoint.sh` (repo root) — helper used to drive each 5-min checkpoint: launches
  the bidir video test on all 4 UEs, pings the gateway mid-stream and idle, samples
  InfluxDB `ue_traffic` + `kpm`, and flags new RLC-wedge log lines / xApp liveness.

Smoke test confirming downlink now flows (UE1, 1M bidir):
```
+ ip netns exec ue1 iperf3 -c 10.45.0.1 -p 5201 -t 15 -i 1 --forceflush -u -b 1M -l 1450 --bidir
  [summary] 1.000 Mbps ... sender      # uplink
  [summary] 0.476 Mbps ... receiver    # downlink (server -> UE)
```

## Recommendation / open decision
To get a stable 30-min bidirectional run on this host, reduce the real-time CPU demand
or free host CPU. Options (in rough order of likelihood to succeed):
1. **Fewer concurrent UEs** — 1 UE per cell (UE1 + UE3) at 1M bidir keeps both slices
   and both directions while halving UE/PHY CPU.
2. **All 4 UEs at a much lower rate** (e.g. 512k bidir) and pause the KPM xApp during
   traffic to free ~0.6 core (sample KPM only between runs).
3. **Free host CPU first** — the baseline load (~25) is largely external to this stack;
   reducing it would let the full 4-UE/1M-bidir profile run.
4. Run the full profile and accept frequent ~4-min gNB-cycle recoveries (choppy).

The experiment was paused here pending that decision; no 30-min run was completed.
