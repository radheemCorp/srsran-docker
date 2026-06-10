# 20260428 — srsRAN in a VM: persistent RF underflow/late (P-core vs E-core scheduling)

- **Date:** 2026-04-28
- **Area:** SDR / real-time
- **Status:** Open (underflows persist in the VM; mitigations recommended, not yet applied)
- **Components:** srsran_gnb in KVM guest, i9-13900K host, UHD/SDR

> Source: `tracks/uhd_in_vm/README.md` (+ gnb.log, 5gc.log, .env).

## Summary
- Running the gNB inside a **KVM VM** on a strong i9-13900K (24 vCPUs) still produces
  constant **RF underflow/late** and `PRACH buffer pool depleted` — the PHY can't meet
  real-time deadlines.
- Standard tuning (governor `performance`, KMS polling off, 32 MB socket buffers) did
  **not** fix it: this is a **latency** problem, and the VM/hybrid-core scheduling is the
  bottleneck, not throughput or buffer size.

## Context / setup
- Guest: 24 vCPUs, full virtualization (VT-x), AVX2/AVX_VNNI present. Host CPU is an Intel
  **i9-13900K** (hybrid: P-cores + E-cores). Telegraf `WS_URL=192.168.122.235:8001`
  (the VM's IP).

## Investigation / what was determined
- Recurring `[RF] [W] Real-time failure in RF: underflow/late`, plus
  `PRACH buffer pool depleted` (PHY so far behind it can't even init buffers for incoming
  RA from UEs).
- Tuning status table from the track: governor `performance` (all 24 vCPUs), KMS polling
  disabled, `net.core.wmem_max = 33554432` — **Outcome: FAILED**, underflows persist.

## Root cause
- **Hypervisor jitter + Intel hybrid-core scheduling.** Even on an i9-13900K, the KVM
  abstraction adds microsecond-scale latency; if the hypervisor schedules the gNB PHY
  threads onto an **E-core**, they miss real-time deadlines regardless of the governor.
  A few microseconds late = the SDR sees "Late" and drops the sample.

## Resolution / workaround
- Recommended (host-side), not yet applied:
  1. **vCPU pinning to P-cores** (e.g. cores 0–15) and isolate them from host tasks.
  2. **`mitigations=off`** on the VM's GRUB cmdline (Spectre v1/v2 mitigations slow
     syscalls ~15–20%).
  3. **Low-latency / RT kernel** in the guest to shrink the scheduling quantum.

## Lessons / gotchas
- For SDR/real-time, **latency beats raw core count** — a 24-vCPU VM loses to careful core
  pinning. Bigger socket buffers don't help a deadline-miss problem.
- On Intel hybrid CPUs, an unpinned RT workload landing on an E-core is a silent killer —
  pin to P-cores.
- `PRACH buffer pool depleted` is a "PHY is hopelessly behind" signal, not a config knob.
- Same real-time-headroom theme as the ZMQ host-CPU-starvation run — virtual RF or SDR,
  the gNB needs guaranteed CPU.

## References
- `tracks/uhd_in_vm/README.md`, `.../gnb-uhd/gnb-storage/gnb.log`, `.../5gc.log`, `.../.env`.
- Related: [20260427-uhd-b210-on-host-working-rf-underflow-ue-context-mod.md](./20260427-uhd-b210-on-host-working-rf-underflow-ue-context-mod.md),
  [20260427-host-sdr-outgoing-packets-dropped.md](./20260427-host-sdr-outgoing-packets-dropped.md),
  [20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md](./20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md).
