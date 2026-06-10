# Engineering journal

Chronological log of problems hit while bringing up and running the srsRAN /
Open5GS / O-RAN SC RIC ZMQ testbed, and how they were diagnosed and resolved.
Each entry is a self-contained post-mortem; this page is the entrypoint.

- **New entry:** copy [TEMPLATE.md](./TEMPLATE.md) to `YYYYMMDD-kebab-slug.md`, fill in
  the header block (Date / Area / Status / Components), and add a row to the index below.
- **Conventions:** filename `YYYYMMDD-<slug>.md`; keep the header block so this index
  stays mechanical; newest first.
- **Status legend:** `Resolved` (fixed) · `Mitigated` (worked around, proper fix
  deferred) · `Open` (unresolved / external limit) · `Investigating` · `Superseded`
  (overtaken by a later setup) · `Explained` (understood, no code change needed).

## Index (newest first)

| Date | Entry | Area | Status |
|------|-------|------|--------|
| 2026-06-10 | [Single summed ZMQ bridge caps at ~2 UEs (PRACH preamble-0 collision)](./20260610-prach-preamble0-collision-2ue-bridge-limit.md) | RAN / ZMQ | Explained |
| 2026-06-10 | [Single-cell standalone (dir-based, no RIC): low-load bidir still wedges on a CPU-starved host](./20260610-single-cell-dirs-bidir-wedge-cpu.md) | traffic / stability | Open |
| 2026-06-10 | [2 gNB / 4 UE traffic run — UEs wedge under load (host CPU starvation) + bidirectional traffic support](./20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md) | traffic / stability | Open |
| 2026-06-10 | [2 gNB KPM capture — gNB1 uplink-only, gNB2 no traffic, UE3/UE4 unrouted](./20260610-2gnb-kpm-no-downlink-gnb2-no-traffic.md) | E2 / KPM | Explained |
| 2026-06-06 | [E2SM-KPM reports CQI/RSRP/RSRQ = 0 for all UEs except the first](./20260606-e2sm-kpm-per-ue-cqi-rsrp-rsrq-zero.md) | E2 / KPM | Open |
| 2026-04-28 | [srsRAN in a VM — persistent RF underflow/late (P-core vs E-core scheduling)](./20260428-uhd-in-vm-rf-underflow-pcore-scheduling.md) | SDR / real-time | Open |
| 2026-04-27 | [UHD B210 on host — working setup; RF underflow → repeated UE context release](./20260427-uhd-b210-on-host-working-rf-underflow-ue-context-mod.md) | SDR / RAN | Mitigated |
| 2026-04-27 | [Host SDR — outgoing packets dropped + RF late/underflow (B210)](./20260427-host-sdr-outgoing-packets-dropped.md) | SDR / real-time | Open |
| 2026-04-26 | [USRP B210 disappears after PC restart (No UHD Devices Found)](./20260426-usrp-b210-lost-after-restart.md) | SDR / hardware | Investigating |
| 2026-04-21 | [Bring-up status — per-UE namespace routing fails](./20260421-network-status.md) | bring-up | Superseded |
| 2026-04-20 | [UE can't reach gateway — ogstun subnet mismatch](./20260420-multi-ue-ogstun-subnet-mismatch.md) | networking | Resolved |
| 2026-04-20 | [Open5GS / UEs have no internet — macvlan-on-OVS ARP failure](./20260420-open5gs-no-internet-macvlan-ovs.md) | networking | Mitigated |
| 2026-04-17 | [srsRAN docker build fails on apt (mirror sync), updated Dockerfile reverted](./20260417-srsran-docker-build-apt-mirror-sync-fail.md) | build / infra | Explained |
| 2026-04-14 | [ZMQ UE released right after RRC Connect (new gNB config)](./20260414-zmq-ue-released-after-rrc-connect.md) | RAN / ZMQ | Investigating |

## Themes

- **Networking (Apr 2026):** early bring-up was dominated by L2/L3 plumbing —
  macvlan-on-OVS breaking ARP, UE-pool vs `ogstun` subnet mismatch, and per-UE netns
  routing. The current setup uses the netns-per-UE model and a Docker `internet` bridge
  for 5GC egress.
- **SDR / real-time (Apr 2026):** the recurring B210/UHD theme is **real-time deadline
  misses** — RF "Late"/"Underflow", egress packet drops, and (downstream) UE context /
  PDU-session releases. Latency, not throughput: tuning helps but the durable fixes are
  CPU isolation/pinning (and, in a VM, pinning gNB threads to P-cores). Plus hardware
  gotchas (B210 lost after reboot) and the Open5GS-hex / srsRAN-decimal SD encoding.
- **E2 / KPM (Jun 2026):** per-UE KPM has an upstream srsRAN bug (CQI/RSRP/RSRQ hardcode
  UE index 0); throughput/PRB/delay/volume are trustworthy. Downlink KPM reads ~0 unless
  the traffic generator actually drives DL.
- **Traffic / stability (Jun 2026):** the 2-cell data plane is correct, but sustained
  4-UE traffic wedges UE RLC DRBs — root-caused to host CPU starvation (real-time ZMQ
  needs headroom), not a RAN/config fault. Same real-time-headroom lesson as the SDR work.
  The single-cell standalone variant confirms it: even low-load **bidirectional** UDP on
  2 UEs / 1 gNB / no RIC wedges on a CPU-starved host (UDP floods because it never backs
  off). And the co-located **summed ZMQ bridge caps at ~2 UEs** — all srsUEs send PRACH
  preamble 0, so 4-way msg3 collisions never resolve; split bridges or add per-UE diversity.

## See also

- [../RUNBOOK_2GNB_2SLICE.md](../RUNBOOK_2GNB_2SLICE.md) — deploy/verify/traffic runbook for the 2 gNB / 2 slice setup.
