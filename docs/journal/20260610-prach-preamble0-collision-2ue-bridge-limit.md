# 20260610 — Single summed ZMQ bridge caps at ~2 UEs (PRACH preamble-0 collision)

- **Date:** 2026-06-10
- **Area:** RAN / ZMQ
- **Status:** Explained (architectural limit; workaround = NUM_UES=2 or split bridges)
- **Components:** multi_ue (multi_ue_scenario.py bridge), srsue, srsran_gnb (single cell)

> Source: single-cell bring-up (`multi_ue-single-cell/`, `srsRAN_Project/gnb-zmq-single-cell/`).

## Summary
- Putting **4 UEs on one co-located ZMQ bridge** (single cell) → **none attach**: every
  RA msg3 fails (`crc=KO`), the gNB cycles tc-RNTIs forever, then its ZMQ stalls
  (`Completed 0 of 23040 samples`). **2 UEs on the same bridge attach reliably.**
- Root cause: all srsUEs send PRACH **`preamble_index=0`**, and the bridge sums all UE
  uplinks equally (`add_vcc`). 2 UEs → a msg3 collision resolves by capture effect; 4 UEs
  all answer the same RAR and their msg3 collide **every** time → no winner, no attach.
- This is why the two-cell design split 4 UEs into 2+2, and why the single-cell runbook
  should use `NUM_UES=2`.

## Context / setup
- One gNB (PCI 1), one 5GC, one `multi_ue` container. The bridge
  (`multi_ue_scenario.py`) sums every UE uplink into the single gNB rx with
  `blocks.add_vcc(1)` and fans the single gNB downlink out to each UE. UE uplinks are
  ZMQ `req_source`s — the add block only produces once **every** UE source has a peer
  (so all srsUEs must be running for any uplink to flow; you can't attach sequentially).

## Investigation / what was determined
- 4-UE attempt: all four UEs use the same preamble, and msg3 never decodes:
  ```
  ue1..ue4:  preamble_index=0   (all four identical)
  ue1..ue4:  Random Access Complete = 0
  gNB:       tc-rnti=0x4601 0x4602 0x4603 0x4604 0x4605 0x4606 0x4607   (RA retries)
  gNB:       crc=OK msg3 = 0     crc=KO msg3 = 30
  gNB:       "Maximum number of reTxs 4 exceeded" then log freezes
             "Waiting for reading samples. Completed 0 of 23040 samples"  (ZMQ stalled)
  ```
- 2-UE attempt (same bridge, `NUM_UES=2`): both attach immediately:
  ```
  UE1 10.45.0.2, UE2 10.45.0.3 ; only bridge_cell1.log ; rnti=0x4601 0x4602 ; crc=OK = 30
  ```
- The differentiator is purely the UE count on the one summed bridge, not slice/IP/config.

## Root cause
- **Deterministic PRACH contention.** srsUE here always transmits **preamble 0**. The gNB
  detects one preamble, sends one RAR with one msg3 grant; on a summed bridge *all* UEs
  that picked that preamble transmit msg3 in that grant and sum on top of each other.
  With 2 UEs the capture effect lets one msg3 win (then the other retries alone and
  attaches). With 4 the four equal-power msg3 always collide → 0 decode. The repeated
  failed RA eventually wedges the gNB ZMQ sample loop.

## Resolution / workaround
- **Use `NUM_UES=2` per single bridge** (reliable). For more UEs, either:
  - **Split bridges** (the two-cell design: 2 UEs per bridge/gNB), or
  - **Add per-UE diversity in the bridge** so capture effect lets UEs attach in a rolling
    fashion — e.g. a `blocks.multiply_const_cc` with a slightly different gain on each
    `add_vcc` input (unequal power), and/or per-UE preamble selection. Not implemented.

## Lessons / gotchas
- The co-located bridge's `add_vcc` makes UE uplinks **share one summed RF stream** with
  no power control — it behaves like every UE at identical power into one antenna. RA
  contention that a real cell shrugs off (different path loss, preamble randomization)
  becomes a hard collision here.
- `crc=KO` on msg3 + cycling tc-RNTIs + all UEs on `preamble_index=0` = RA collision, not
  a radio/config fault. Reduce UEs per bridge or add diversity.
- A summed bridge needs **all** UE ZMQ peers connected to produce any uplink, so you
  cannot "attach one UE, let it idle, then the next" to dodge the collision.

## References
- `multi_ue/config/multi_ue_scenario.py` (`add_vcc` uplink sum, `req_source` per UE).
- Two-cell split rationale: [20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md](./20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md)
  ("~2 UEs per cell" note), runbook [../RUNBOOK_SINGLE_CELL_DIRS.md](../RUNBOOK_SINGLE_CELL_DIRS.md).
- Single-cell setup learnings: [20260610-single-cell-dirs-bidir-wedge-cpu.md](./20260610-single-cell-dirs-bidir-wedge-cpu.md).
