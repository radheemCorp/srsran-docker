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
| 2026-06-10 | [2 gNB / 4 UE traffic run — UEs wedge under load (host CPU starvation) + bidirectional traffic support](./20260610-2gnb-4ue-traffic-stability-host-cpu-starvation.md) | traffic / stability | Open |
| 2026-06-10 | [2 gNB KPM capture — gNB1 uplink-only, gNB2 no traffic, UE3/UE4 unrouted](./20260610-2gnb-kpm-no-downlink-gnb2-no-traffic.md) | E2 / KPM | Explained |
| 2026-06-06 | [E2SM-KPM reports CQI/RSRP/RSRQ = 0 for all UEs except the first](./20260606-e2sm-kpm-per-ue-cqi-rsrp-rsrq-zero.md) | E2 / KPM | Open |
| 2026-04-21 | [Bring-up status — per-UE namespace routing fails](./20260421-network-status.md) | bring-up | Superseded |
| 2026-04-20 | [UE can't reach gateway — ogstun subnet mismatch](./20260420-multi-ue-ogstun-subnet-mismatch.md) | networking | Resolved |
| 2026-04-20 | [Open5GS / UEs have no internet — macvlan-on-OVS ARP failure](./20260420-open5gs-no-internet-macvlan-ovs.md) | networking | Mitigated |

## Themes

- **Networking (Apr 2026):** early bring-up was dominated by L2/L3 plumbing —
  macvlan-on-OVS breaking ARP, UE-pool vs `ogstun` subnet mismatch, and per-UE netns
  routing. The current setup uses the netns-per-UE model and a Docker `internet` bridge
  for 5GC egress.
- **E2 / KPM (Jun 2026):** per-UE KPM has an upstream srsRAN bug (CQI/RSRP/RSRQ hardcode
  UE index 0); throughput/PRB/delay/volume are trustworthy. Downlink KPM reads ~0 unless
  the traffic generator actually drives DL.
- **Traffic / stability (Jun 2026):** the 2-cell data plane is correct, but sustained
  4-UE traffic wedges UE RLC DRBs — root-caused to host CPU starvation (real-time ZMQ
  needs headroom), not a RAN/config fault.

## See also

- [../RUNBOOK_2GNB_2SLICE.md](../RUNBOOK_2GNB_2SLICE.md) — deploy/verify/traffic runbook for the 2 gNB / 2 slice setup.
