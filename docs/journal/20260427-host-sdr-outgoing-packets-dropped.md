# 20260427 — Host SDR: outgoing packets dropped + RF late/underflow (B210)

- **Date:** 2026-04-27 (approx — track is undated; placed in the late-Apr SDR window)
- **Area:** SDR / real-time
- **Status:** Open (RF late/underflow cleared by tuning; 20 egress drops + no UE internet persist)
- **Components:** USRP B210 (NI2901, USB-3), host NIC enp2s0, Linux kernel/sysctl, srsRAN gNB

> Source: `tracks/outgoinging_packets_dropped/README.md`.

## Summary
- Running a real-time srsRAN gNB on a B210, two symptoms: **RF "Late"/"Underflow"**
  during transmission, and **20 outgoing packets dropped** at the host NIC `enp2s0` — and
  the UE still couldn't browse the internet.
- The `srsRAN_Project/scripts/srsran_performance` tuning + NIC tuning cleared the
  Late/Underflow errors, but the 20 egress drops and the UE-no-internet remained.

## Context / setup
- B210 over USB-3 (radio/IQ plane); `enp2s0` (Intel Ethernet, `141.24.211.31/24`) for the
  core/internet plane. Original NIC state: ring buffers 256, MTU 1500.

## Investigation / what was determined
- Mechanism (egress drops): outgoing samples arrive at the publish interface **after**
  their scheduled transmit window — "the time window it is requesting to be published on
  is in the past" — so the kernel/NIC drops them.
- Evidence:
  ```
  $ watch -d "netstat -s | grep -i 'buffer errors\|drop'"
      20 outgoing packets dropped
      0 receive buffer errors
      0 send buffer errors
  ```
- The two planes are distinct: the radio plane (USB → B210) and the core plane
  (`enp2s0` → Open5GS/internet). Egress drops on `enp2s0` break UE↔core even when the
  radio link is fine.

## Root cause
- **Real-time timing/buffering pressure**: the host can't deliver TX samples/packets
  within the radio's strict deadlines, so late packets get dropped (radio side = Late/
  Underflow; NIC side = egress drops). A latency problem, not a throughput problem.

## Resolution / workaround
- Applied tuning (cleared Late/Underflow):
  - **NIC `enp2s0`:** ring buffers RX/TX 256 → **4096**; `txqueuelen` → **10000**;
    disable `gro`/`gso`/`tso`; disable rx/tx pause frames.
  - **Kernel/system:** CPU governor `performance`; disable `usbcore` autosuspend;
    `rmem_max`/`wmem_max` → **32 MB**; `vm.swappiness=10`; disable DRM KMS polling.
  - **UHD/B210:** raise `num_recv_frames`/`num_send_frames` to **128**; set
    `master_clock_rate` 23.04 MHz to match 5G NR sampling.
- Still open: 20 egress drops persist and the UE has no internet — NIC lacks interrupt
  coalescing (`ethtool -C` errors), worked around via `txqueuelen`/offloads. Next step in
  the track: **CPU core isolation** to protect radio threads.

## Lessons / gotchas
- "Outgoing packets dropped" on the SDR host is a **real-time deadline** symptom — late
  samples are dropped because you "can't transmit in the past."
- A perfect radio link still gives the UE a dead connection if `enp2s0` (gNB↔core) drops
  egress packets — check both planes.
- This is the bare-metal cousin of the ZMQ "host can't keep up" failure — see the
  host-CPU-starvation entry for the same class of problem under virtual RF.

## References
- `tracks/outgoinging_packets_dropped/README.md`; `srsRAN_Project/scripts/srsran_performance`.
- Related: [20260427-uhd-b210-on-host-working-rf-underflow-ue-context-mod.md](./20260427-uhd-b210-on-host-working-rf-underflow-ue-context-mod.md),
  [20260428-uhd-in-vm-rf-underflow-pcore-scheduling.md](./20260428-uhd-in-vm-rf-underflow-pcore-scheduling.md),
  [20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md](./20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md).
