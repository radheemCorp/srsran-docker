# Scientific and Technical Internship Report

**Building a Containerized End-to-End 5G Standalone Testbed (RAN + Core + RIC) with
ZMQ and SDR Radio Variants**

---

## Cover Sheet

| | |
|---|---|
| **Student name** | _[TO FILL: your full name]_ |
| **Degree programme** | M.Sc. Research in Computer & Systems Engineering (RCSE) |
| **Matriculation number** | _[TO FILL]_ |
| **University** | Technische Universität Ilmenau — Integrated Communication Systems (ICS) Group |
| **Host company** | Aivader _[TO FILL: legal entity / GmbH]_ |
| **Company address** | _[TO FILL: street, postal code, city, country]_ |
| **Company supervisor** | Dr.-Ing. Ali Diab |
| **Supervisor contact** | _[TO FILL: email / phone]_ |
| **Internship period** | _[TO FILL: start – end dates]_ (project activity in the repository spans 13 Apr 2026 – 08 Jun 2026) |

> Placeholders marked _[TO FILL]_ are personal/administrative details to be completed
> by the author; all technical content below reflects the work actually carried out.

---

## 1. General Information about the Company

Aivader is _[TO FILL: short company description — founding year, location, legal form]_,
active in the field of _[TO FILL: e.g. wireless/5G systems, AI-driven network
automation, software engineering]_. Its business focus relevant to this internship is
**private 5G networks and Open RAN**, an area that combines mobile-network software
(RAN, core network), cloud-native deployment (containers/Docker), and the O-RAN
architecture for programmable, vendor-neutral radio access.

_[TO FILL: company history, size, organisational structure, main products/services,
key customers or research partners.]_

The work was supervised by **Dr.-Ing. Ali Diab**, whose guidance shaped the technical
direction (choice of open-source stack, the two-variant strategy, and the slicing /
RIC experiments described below).

---

## 2. Integration into the Company

- **Department / team:** _[TO FILL: e.g. R&D / 5G systems team]_.
- **Team size and hierarchy:** _[TO FILL: number of colleagues, reporting line to
  Dr.-Ing. Ali Diab]_.
- **Working mode:** _[TO FILL: on-site / hybrid / remote; tools used for collaboration
  — e.g. Git, issue tracker, regular sync meetings with the supervisor]_.
- **Activities besides the core task:** _[TO FILL: e.g. literature review of O-RAN
  specifications, internal demos, documentation, knowledge-sharing sessions]_.

The project was tracked in a Git repository with **124 commits** over the internship,
accompanied by living documentation (setup guides, runbooks, troubleshooting notes,
and investigation "tracks"), so progress and design decisions are auditable.

---

## 3. The Task

**Goal:** stand up a *complete, reproducible 5G Standalone (SA) testbed* on a single
Linux host and use it to run mobile-network experiments — without depending on
commercial RAN equipment or licensed spectrum.

A complete testbed requires all four layers of a real mobile network, plus
observability:

1. **UE** — the user equipment (the "phone").
2. **gNB** — the 5G base station (RAN).
3. **5G Core (5GC)** — the network brain (authentication, session/mobility management,
   user-plane routing).
4. **RIC** — the O-RAN *near-real-time RAN Intelligent Controller*, which makes the RAN
   programmable through the E2 interface and **xApps**.
5. **Monitoring/visualization** — to measure and observe the system end to end.

To make the testbed both **hardware-free for development** and **realistic for radio
work**, two RF variants were built:

- **Variant A — ZMQ (virtual RF):** the gNB and UE exchange baseband IQ samples over
  ZeroMQ TCP sockets instead of a real antenna. Runs entirely in software on one host.
- **Variant B — UHD (physical SDR):** the gNB drives a USRP **B210** software radio
  over USB and serves a **real COTS smartphone** with a programmed USIM.

These were exercised in **three deployed configurations**, each with its own
experiments:

1. **ZMQ single-cell** — one gNB + srsUE; base development and the throughput /
   connectivity / VoIP / multi-UE experiments.
2. **ZMQ two-cell, two-slice** — two gNBs, each advertising a different slice, with two
   UEs per slice (the slicing study; documented in `docs/RUNBOOK_2GNB_2SLICE.md`).
3. **UHD single-cell (USRP B210)** — one gNB over the SDR serving a real phone; the
   over-the-air validation and video-streaming experiment.

Everything is packaged with **Docker / Docker Compose** so each configuration can be
created, torn down, and reproduced deterministically.

---

## 4. Concepts, Architecture and Technology Choices

### 4.1 Component selection

| Layer | Software chosen | Why |
|---|---|---|
| RAN (gNB) | **srsRAN Project** | open-source, production-grade 5G gNB; supports both ZMQ and UHD RF |
| UE | **srsUE** (ZMQ) / **COTS phone + USIM** (UHD) | srsUE for hardware-free testing; real phone to validate the radio path |
| 5G Core | **Open5GS** (AMF, SMF, UPF, UDM/UDR, NRF, PCF, …) | complete 5G SA SBA core, scriptable subscriber DB (MongoDB) |
| RIC | **O-RAN SC near-RT RIC** (e2term, e2mgr, submgr, dbaas/Redis, appmgr, rtmgr) | O-RAN-compliant, lightweight (no Kubernetes), supports E2SM-KPM/RC/CCC |
| Observability | **Telegraf → InfluxDB → Grafana** | gNB JSON metrics + xApp KPIs into time-series dashboards |

### 4.2 Network architecture

The 3GPP reference points were realised as isolated Docker networks, mapping directly
to concepts from the *Communication Networks* and *Advanced Mobile Communication
Networks* courses:

| Interface | Purpose | Transport |
|---|---|---|
| **N2** | gNB ↔ AMF signalling (NGAP) | SCTP / IP |
| **N3** | gNB ↔ UPF user plane | GTP-U over UDP/IP |
| **N6** | UPF ↔ data network (Internet) | IP routing / NAT |
| **E2** | gNB ↔ RIC | SCTP (RMR routing inside the RIC) |
| **metrics** | gNB metrics → Telegraf | WebSocket/HTTP |

Networks are created and validated by a single script (`scripts/net_manage.sh init`),
which also configures host-side macvlan interfaces and NAT so UE traffic can reach an
external data network. This is, concretely, the *IP subnetting, routing, switching and
gateway/NAT* material from the Communication Networks course applied to a live system.

### 4.3 The two RF variants

**ZMQ (virtual RF).** The gNB's `ru_sdr` frontend is set to `device_driver: zmq`; gNB
TX/RX are TCP ports wired to the UE's RX/TX. Sample exchange is **lockstep** — gNB and
UE must step their baseband together — which removes the need for any radio hardware
and makes the data plane fully deterministic. This variant is ideal for developing
xApps, network slicing, and multi-UE scenarios.

**UHD (physical SDR).** The gNB's frontend is `device_driver: uhd` driving a USRP
**B210** (UHD device `type=b200`) over USB, on **band n78, TDD, 20 MHz, SCS 30 kHz**. A
real smartphone with a programmed USIM attaches over the air. This variant validates
the actual PHY/RF path and exposes real-world issues (USIM sequence numbers, IMS/DNN
behaviour) that the virtual variant cannot show.

---

## 5. Problem Solving — Work Carried Out and Decisions Made

The internship progressed in stages, each adding a capability and surfacing problems
that had to be diagnosed and resolved. Decisions were taken in consultation with the
supervisor, Dr.-Ing. Ali Diab.

### 5.1 Bring-up of the base testbed (Core + gNB + UE)

Built the shared Docker images (one Dockerfile produces both gNB and Open5GS),
established the network layout, and brought up Open5GS + a single srsRAN gNB + srsUE
over ZMQ. Achieved UE registration and a PDU session with an assigned IP, then
validated the **N3 user plane** with `ping` and `iperf3` throughput tests
(`experiments/zmq/iperf_defaults`, `simple_ping_google`), and a **VoIP** scenario
(`experiments/zmq/voip`).

### 5.2 Observability stack

Added a **Telegraf → InfluxDB → Grafana** pipeline. Telegraf ingests the gNB's JSON
metrics (exposed over a WebSocket) and writes per-UE radio KPIs to InfluxDB; Grafana
dashboards visualise MCS, BLER, and per-UE throughput. This turned the testbed from
"it connects" into "we can measure it."

### 5.3 Multi-UE and network slicing

- **Multi-UE:** packaged *N* srsUEs inside one container with per-UE traffic export, so
  several UEs could be driven and measured independently.
- **Network slicing (S-NSSAI):** introduced two slices (SST/SD). Two strategies were
  implemented and compared: (i) **two S-NSSAIs on a single cell**, with subscribers
  provisioned to a slice at runtime in the core; and (ii) **"Approach A": two cells,
  two slices, two UEs per slice** — two independent gNBs, each advertising a different
  slice, with UEs split across them. A dedicated runbook documents Approach A
  (`docs/RUNBOOK_2GNB_2SLICE.md`).

### 5.4 O-RAN RIC and xApps

Integrated the O-RAN SC near-RT RIC over the **E2** interface and ran the
**`kpm_mon_xapp`** to collect per-gNB **E2SM-KPM** metrics (`DRB.UEThpDl/Ul`). Several
non-obvious platform problems were diagnosed and fixed:

- **e2mgr/Redis startup race:** `e2mgr` gives up on Redis after a few retries and
  exits; `e2term` then cannot route E2, and the gNB's E2 setup could **crash the gNB**.
  Resolved with a self-healing start sequence (restart `e2mgr`, then re-init `e2term`)
  plus a compose `restart: on-failure` policy.
- **E2SM-CCC vs. KPM:** with `e2sm_ccc_enabled: true` the srsRAN DU never completes E2
  setup, so no DU node registers and KPM subscriptions fail. Decision: ship the gNB
  configs with `e2sm_ccc_enabled: false` for KPM work.
- **Per-gNB xApp routing:** because the RIC's static routing delivers indications to a
  single RMR port, per-gNB xApps must be run **sequentially**; this constraint was
  documented rather than worked around.

### 5.5 Two-gNB / two-slice stability

Running two gNBs over ZMQ surfaced data-plane subtleties — co-located UE bridges
**sum** uplinks, bounding the practical number of UEs per cell to ~2, and an unclean
teardown can **wedge** the ZMQ lockstep — both of which were characterised and given
documented recovery procedures.

### 5.6 SDR (UHD) variant and a slice-configuration root cause

On the UHD variant a real phone would **register and then drop after a few seconds
with no data**. By cross-referencing the gNB and core configurations the root cause was
isolated to **network-slice (S-NSSAI) misconfiguration**, with a subtle twist that is a
good engineering lesson:

> **Open5GS parses the Slice Differentiator (`sd`) as hexadecimal, while srsRAN parses
> it as decimal.** The value `0x111111` (what the core expects) equals `1118481` in
> decimal (what the gNB must be given). Writing the "same-looking" digits `111111` in
> the gNB selects a *different* slice (`0x01B207`), so NG Setup is rejected with
> `slice-not-supported`.

Because this fault is in the **configuration/core layer and independent of the radio**,
it was **reproduced deterministically on the hardware-free ZMQ stack**, which produced
the exact errors seen on the testbed:

- A stray YAML hyphen splitting the PLMN profile → AMF aborts at boot
  (`No amf.plmn_support … FATAL`).
- The decimal/hex `sd` mismatch → gNB `"NG Setup Procedure" failed … "slice-not-supported"`
  and AMF `Cannot find S_NSSAI`.

The fixes were then applied back to the UHD configuration, including a previously
**missing `cell_cfg.slicing` block** (the gNB advertised the slice to the AMF but the
cell never declared it, which blocked the PDU session). The analysis, reproduction,
and verification are recorded in `docs/UHD_SLICE_REPORT.md` and
`docs/UHD_SLICE_TROUBLESHOOTING.md`. Items that genuinely require the live phone (IMS
PCO options, USIM sequence-number re-synchronisation) were separated out with explicit
verification procedures for the testbed.

---

## 6. Final Result

A **complete, reproducible, single-host 5G SA testbed** was delivered, comprising:

- **End-to-end data path:** srsUE/COTS UE → srsRAN gNB → Open5GS 5GC → data network,
  with UE registration, PDU-session establishment, and validated throughput/latency.
- **Two RF variants in three deployed configurations:** ZMQ single-cell, ZMQ two-cell
  / two-slice, and UHD single-cell on a USRP B210 with a real phone — all selectable
  via Docker Compose.
- **Network slicing:** two S-NSSAIs, realised both as two slices on one cell and as a
  two-cell / two-slice / two-UE-per-slice deployment.
- **O-RAN RIC + xApps:** E2 connectivity with per-gNB **E2SM-KPM** monitoring, plus
  characterised E2SM-RC/CCC behaviour.
- **Observability:** Telegraf → InfluxDB → Grafana dashboards (per-UE traffic, per-gNB
  KPM).
- **Experiment suite:** ZMQ — iperf throughput, connectivity, VoIP, multi-UE; UHD —
  video streaming over the air.
- **Engineering documentation:** setup guide, a 2-gNB/2-slice runbook, and
  reproducible troubleshooting reports — so the testbed is maintainable and the
  failures are not "tribal knowledge."

The testbed is now usable as a foundation for further private-5G / Open RAN
experimentation (rate-control xApps, handover, QoS/slicing studies).

_[Optional: insert screenshots from `experiments/uhd/video_streaming/` and the Grafana
dashboards as figures here.]_

---

## 7. Personal Summary

**What I could apply from my studies.** The internship was a direct, hands-on
application of two courses:

- *Communication Networks* — protocol layering and the OSI/IP model became concrete in
  the N2/N3/N6 interfaces; **SCTP** (N2 signalling) and **GTP-U over UDP** (N3 user
  plane) are exactly the transport-layer protocols from the course; IP subnetting,
  routing, switching, gateways and NAT were what I configured to connect the UE to an
  external network; and the GSM→UMTS→LTE→5G evolution gave the context for the 5G core.
- *Advanced Mobile Communication Networks* — the 5G SA / service-based architecture,
  **Open RAN** and the RIC/E2 programmability model, **network slicing** (S-NSSAI,
  SST/SD), QoS, mobility/handover, and self-organization were no longer slides but
  components I deployed, broke, and fixed.

**What I learned.** Beyond the theory: how a 5G control plane and user plane actually
fit together; how to debug across layers (NGAP/E2 signalling, GTP-U data plane, core
session management) using logs and packet captures; the discipline of
**reproducibility** (containerising the whole stack, writing runbooks, reproducing a
hardware bug in software); and that many "radio" failures are really
**configuration/core** failures — the decimal-vs-hex slice bug being the clearest
example.

**What was missing from my studies (and would have helped).** _[TO FILL — suggestions:
more practical lab work with real RAN/core software; exposure to O-RAN
specifications and the E2 service models; cloud-native/DevOps tooling (Docker,
Compose, CI) which proved essential; and time-series observability for network KPIs.]_

**Overall.** _[TO FILL: 2–3 sentences of personal reflection on the internship, the
team at Aivader, and the supervision by Dr.-Ing. Ali Diab.]_

---

## 8. Supervisor Confirmation

Confirmed by the company supervisor:

**Dr.-Ing. Ali Diab**, Aivader

Signature: ______________________   Date: ______________

---

### Appendix — Repository artefacts referenced

- `README.md`, `SETUP.md` — testbed overview and deployment guide.
- `docs/RUNBOOK_2GNB_2SLICE.md` — two-gNB / two-slice deployment runbook.
- `docs/UHD_SLICE_REPORT.md`, `docs/UHD_SLICE_TROUBLESHOOTING.md` — slice root-cause
  analysis, reproduction, and fixes.
- `srsRAN_Project/gnb-zmq/`, `srsRAN_Project/gnb-uhd/` — the two RF-variant deployments.
- `oran-sc-ric/` — RIC platform and xApps (`kpm_mon_xapp.py`, `simple_rc_xapp.py`,
  `simple_rc_ho_xapp.py`, …).
- `experiments/zmq/`, `experiments/uhd/` — experiment configurations and captures.
