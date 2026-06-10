# 20260610 — Single-cell standalone (dir-based, no RIC): low-load bidir still wedges on a CPU-starved host

- **Date:** 2026-06-10
- **Area:** traffic / stability
- **Status:** Open (data-plane works; sustained bidir wedges — host CPU bound)
- **Components:** srsRAN_Project/gnb-zmq-single-cell, multi_ue-single-cell, open5gs_5gc, monitoring

> Source: single-cell experiment built as side-by-side dirs (not a branch). Runbook:
> [../RUNBOOK_SINGLE_CELL_DIRS.md](../RUNBOOK_SINGLE_CELL_DIRS.md).

## Summary
- Built a standalone single-cell stack as **copied directories** (`gnb-zmq-single-cell`,
  `multi_ue-single-cell`) instead of a git branch, with **E2/RIC disabled** and
  **bidirectional** (`--bidir`) traffic. 2 UEs attach and have full connectivity (DNS +
  ping google.com, 0% loss idle).
- But **even low-load bidirectional traffic wedges the RLC** on this host: `1M` bidir on
  just 2 UEs / 1 gNB / no RIC drove ping RTT to **~18 s** (bufferbloat) and wedged both
  UEs within ~2 min. Root cause is the same **host CPU starvation** as the 2-cell run —
  here at load ~16 on 8 cores, gNB alone ~237% CPU.
- Two reusable gotchas surfaced: the `CELL2_UES` empty-string default, and that **UDP
  bidir floods** because UDP doesn't back off to the (CPU-limited) link capacity.

## Context / setup
- `gnb-zmq-single-cell/`: copy of `gnb-zmq` with gnb2/cell2 removed, **E2 disabled**
  (`e2.enable_*: false`, `e2sm_*: false`, `e2ap` pcap off) and the gNB **not** attached
  to the `oran-sc-ric` network → no RIC dependency, no E2-setup segfault risk, less CPU.
- `multi_ue-single-cell/`: copy of `multi_ue` with `CELL2_UES=` (single bridge),
  `NUM_UES=2`, and `--bidir`/`--reverse` in `run_scenario.sh` + `ue_export.py`.
- Launched directly with `docker compose -f <dir>/...` (manage.sh hardcodes the original
  dirs). External nets `n2/n3/metrics/ue_n3` already exist; `oran-sc-ric` not needed.

## Investigation / what was determined
- Connectivity (idle) is healthy on both UEs:
  ```
  UE1 10.45.0.2 / UE2 10.45.0.3 : ping 10.45.0.1 0% ; ping google.com 0% (~80-100 ms)
  ```
- Load test — `1M` bidir, 2 UEs:
  ```
  ue_traffic: ue1/ue2 ~1.0 Mbps then stop
  ue_latency: avg_rtt ue1 = 18252 ms, ue2 = 4723 ms        # bufferbloat, not loss
  wedge:      UE1 +8459, UE2 +8140  'invalid length=-' / 'Current SO larger' lines
  idle ping after stream: both 100% loss (wedged)
  ```
- Host at the time: `/proc/loadavg` ~16 (8 cores); `srsran_gnb` ~237% CPU,
  `multi_ue` ~199%. Dropping RIC + gNB2 + going to 2 UEs lowered load from the 2-cell
  run's ~27–32, but it is still ~2× oversubscribed.

## Root cause
- **Host CPU starvation** (same class as the 2-cell run). Under-provisioned real-time ZMQ
  can't carry the offered bidirectional rate; with **UDP** (no congestion control) iperf
  keeps sending at the target rate, buffers grow without bound (RTT → seconds), and the
  RLC AM retransmission state corrupts → DRB wedge. Adding downlink makes it worse
  (PDSCH cost). This is an environment/capacity limit, not a RAN/config fault.

## Resolution / workaround
- Functionally correct; left running for hand-off to a better machine. To get a stable
  sustained run:
  - **Keep the rate well under effective capacity.** UDP `256k` bidir was selected as a
    lower floor (its smoke test was interrupted, so not confirmed stable here). Raise on a
    less-loaded host. Consider **TCP** for a self-limiting stream (no unbounded flood),
    accepting the runbook's RLF caveat for *unlimited* TCP.
  - Provision real-time headroom (isolated/pinned cores, lower baseline load).
- Gotchas fixed/noted:
  - **`CELL2_UES` empty default:** original `start_all.sh` uses `${CELL2_UES:-3,4}`, and
    `:-` substitutes the default for an *empty* value too — so `CELL2_UES=` still routed
    UE3/UE4 to a (nonexistent) cell-2 gNB (only `bridge_cell2.log` betrayed it). The
    single-cell copy uses `${CELL2_UES:-}` so empty ⇒ one bridge.
  - **iperf3 servers die with the 5GC** on any gNB compose cycle — restart them.

## Lessons / gotchas
- **UDP load tests on a capacity-limited link are deceptive:** throughput looks fine for a
  bit, then RTT explodes into the seconds and the DRB wedges — because UDP never backs
  off. Read the *idle* ping (after the stream) as the connectivity gate; mid-stream 100%
  loss with multi-second RTT is bufferbloat, not a dead link.
- **Decoupling from the RIC** (E2 off + drop the `oran-sc-ric` network) makes a clean,
  lighter standalone single-cell stack and removes the E2-setup segfault footgun.
- Bash `${VAR:-default}` fires on empty *and* unset; use `${VAR-default}` (no colon) or an
  explicit empty default when an empty value must mean "off".

## References
- `srsRAN_Project/gnb-zmq-single-cell/{docker-compose.yml,project-config/gnb/gnb_zmq.yml}`,
  `multi_ue-single-cell/{.env,config/start_all.sh,config/run_scenario.sh,config/ue_export.py}`,
  `checkpoint_sc.sh`, [../RUNBOOK_SINGLE_CELL_DIRS.md](../RUNBOOK_SINGLE_CELL_DIRS.md).
- Same host-CPU root cause (2-cell): [20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md](./20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md).
- ~2-UE bridge limit: [20260610-prach-preamble0-collision-2ue-bridge-limit.md](./20260610-prach-preamble0-collision-2ue-bridge-limit.md).
