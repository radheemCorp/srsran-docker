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

This stage was dominated by **L2/L3 plumbing** problems that are themselves good
networking lessons:

- **macvlan-on-OVS broke ARP.** Docker `macvlan` networks parented on Open vSwitch
  bridges could not ARP their gateway, so containers had an IP but no egress. Mitigation:
  give Open5GS a normal Docker-NAT path via a dedicated `internet` bridge (and, properly,
  parent macvlan on the physical NIC). A container with an IP that cannot reach its
  gateway is an **L2/ARP** problem before it is a NAT problem.
- **UE-pool vs `ogstun` subnet mismatch.** The UE was assigned `10.41.0.x` while the UPF's
  `ogstun` was on `10.45.x.x`, so the UE and UPF were on different L3 subnets and the UE
  could not reach its gateway. Fix: pin the SMF/UPF `session` subnet+gateway to match the
  UE pool. Invariant: the UE IP pool and `ogstun` subnet **must** match for the user plane.
- **Per-UE network namespaces.** Routing failed ("Nexthop has invalid gateway") when a
  pre-created `ueN` namespace had no interface on the PDN subnet. The chosen model is
  **netns-per-UE**: srsUE creates `tun_srsue` inside `ueN`, and the default route is added
  only once that interface appears — the model the multi-UE container uses today.

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
  documented rather than worked around. (Killing a detached xApp also needs care: the
  `python_xapp_runner` container has no `ps`/`kill`/`pkill`, so a stale `kpm_mon_xapp.py`
  must be killed via `/proc/<pid>/cmdline` + the shell `kill` builtin, or the next xApp
  dies with `Address already in use`.)
- **Per-UE KPM measurement-provider bug (upstream srsRAN):** in E2SM-KPM report style 4,
  `CQI`, `RSRP` and `RSRQ` read **0 for every UE except the one at index 0** — the srsRAN
  getters hardcode `last_ue_metrics[0]` and emit a single record. Throughput, PRB, delay
  and volume are correct for *all* UEs. A second finding: in this build `RSRP`/`RSRQ` are
  not real RSRP/RSRQ at all — both getters return `(int)pusch_snr_db`. Engineering
  decision: trust the throughput/PRB/delay/volume metrics and treat the per-UE
  CQI/RSRP/RSRQ as unreliable (recorded in the journal for whoever revisits the xApp).
- **"No downlink KPM" was a traffic-generator gap, not a KPM fault.** `DRB.UEThpDl` read
  ~0 under load while `DRB.UEThpUl` was healthy (~3000 kbps). The cause was that the UE
  traffic runner (`run_scenario.sh` → `ue_export.py`) only ran the iperf3 client
  **uplink** (UE→server), so the DU never scheduled downlink. The scripts were extended
  with `--reverse` (iperf3 `-R`, downlink) and `--bidir` (simultaneous UL+DL); with
  bidirectional traffic the downlink KPM becomes non-zero. Lesson: a KPI that reads zero
  is often a *workload* gap, not an instrumentation bug — check what traffic is actually
  being offered before suspecting the measurement.

### 5.5 Two-gNB / two-slice stability

Running two gNBs over ZMQ (Approach A: two cells, two slices, two UEs per slice) and
driving traffic on all four UEs surfaced several data-plane subtleties, each
characterised and given a documented recovery procedure:

- **RLC DRB wedge.** Under sustained multi-UE traffic a UE's RLC acknowledged-mode
  segmentation state corrupts — `ue<N>.log` spams `DRB1: buffer state - retx - invalid
  length=-NNN` and `Current SO larger or equal to SDU size`. The UE then stops passing
  data (ping = 100% loss even when idle) and that cell's `DRB.UEThpUl` KPM reads 0,
  although the gNB still schedules its RNTIs — i.e. PHY/MAC are fine, only the DRB is
  wedged. Recovery is to cycle the gNB and re-attach the UEs.
- **Root cause is host CPU starvation, not a RAN bug.** The wedge reproduced on
  essentially every full-load run, on whichever UE/cell hit a timing slip first. The
  common factor was an **oversubscribed host** — load average ~27–32 on an 8-core
  machine — driving ZMQ sample underruns (`Completed 0 of 23040 samples`). srsRAN ZMQ is
  hard real-time; when the host cannot feed samples on time the slip corrupts uplink RLC.
  This is the **same real-time-headroom lesson** as the SDR "Late/Underflow" failures
  (§5.6): latency, not throughput, is the binding constraint. Reducing the bitrate but
  adding downlink made it *worse* (downlink adds PDSCH CPU cost), confirming the mechanism.
- **Slice-2 provisioning is ephemeral.** The in-container Open5GS subscriber database
  (MongoDB) is not persisted, so after any gNB/5GC cycle the slice-2 SST override is lost
  and UE3/UE4 revert to `sst:1`. They then request `SST:2` but the subscriber only allows
  `SST:1`, and the AMF returns **NAS Registration reject cause 62 ("no network slice
  available")** — visible as `RRC Connected` immediately followed by `RRC Release` with no
  PDU session. Fix: re-run the slice-2 provisioning script **after every gNB cycle**.
- **ZMQ reattach limitation.** A srsUE that has attached once cannot reattach on the same
  ZMQ ports; the gNB-side socket will not re-handshake. Recovering a wedged UE therefore
  requires cycling the **gNB** (not just recreating the UE container) so the gNB and UEs
  restart their lockstep sample exchange together.
- **Monitoring blind spot (single-gNB scrape).** Telegraf scrapes exactly one gNB metrics
  WebSocket, so the PCI-based srsRAN dashboards only ever see cell 1 ("Cells with Active
  UEs" reads 1 even with both cells serving UEs). Two-cell visibility comes from the
  per-`e2_node_id` xApp-KPM and per-`ue_id` traffic dashboards instead.

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

**SDR real-time and hardware lessons.** The B210/UHD path repeatedly hit the same class
of problem — the CPU missing the radio's real-time deadlines:

- **RF "Late"/"Underflow".** A *Late* sample arrives after its transmit window ("you
  can't transmit in the past") and is dropped; an *Underflow* means the SDR's buffer ran
  dry. Both cause sudden throughput drops and, downstream, **session loss**: dropped RRC
  Reconfiguration / keep-alive messages make the core assume the link is gone and send a
  `PDUSessionResourceReleaseCommand` — so a "the phone keeps disconnecting" symptom is
  really an RF-timing fault, not a core fault. srsRAN's `scripts/srsran_performance`
  (CPU governor `performance`, disable KMS polling, enlarge socket buffers, disable USB
  autosuspend) helped but did not fully cure it on the test hosts.
- **The host NIC drops egress too.** Even with the radio fixed, `enp2s0` showed "20
  outgoing packets dropped"; NIC tuning (ring buffers 256→4096, large `txqueuelen`,
  disable GRO/GSO/TSO and pause frames) was needed because the gNB↔core plane has its own
  real-time pressure.
- **Virtualisation makes it worse.** Inside a KVM VM on an i9-13900K, underflows persisted
  despite all tuning, with `PRACH buffer pool depleted`. Root cause: hypervisor jitter
  plus Intel **hybrid-core scheduling** — if the gNB PHY threads land on an **E-core** they
  miss deadlines regardless of the governor. The durable fixes are host-side **vCPU
  pinning to P-cores**, `mitigations=off`, and a low-latency kernel — i.e. *guaranteed
  CPU*, the same conclusion as the ZMQ stability work.
- **Hardware gotcha.** The B210 (NI2901) was enumerated by `uhd_find_devices`, then
  reported "No UHD Devices Found" after a host reboot — a USB power-save / firmware-reload
  issue (re-plug, `uhd_usrp_probe`, ensure UHD images, disable USB autosuspend), not a
  dead radio.

### 5.7 ZMQ single-cell standalone variant and the multi-UE bridge limit

To get a lean, RIC-free configuration for low-load bidirectional traffic testing, a
**standalone single-cell** variant was built as **side-by-side directories** rather than
a git branch (`srsRAN_Project/gnb-zmq-single-cell/` and `multi_ue-single-cell/`), so it
can coexist with the two-cell setup. Two design choices and two findings are worth
recording:

- **Decoupled from the RIC.** E2 was disabled in the gNB config (`e2.enable_* : false`,
  `e2sm_* : false`) and the gNB was detached from the `oran-sc-ric` network. This removes
  the E2-setup-vs-RIC startup dependency (and its segfault footgun) and lowers CPU — a
  cleaner standalone stack when KPM is not needed.
- **The co-located bridge caps at ~2 UEs — root cause found.** The bridge sums every UE
  uplink with a single GNU Radio `add_vcc` block, and every srsUE transmits PRACH
  **`preamble_index=0`**. With 2 UEs a msg3 collision resolves by capture effect (one UE
  wins, the other retries alone and attaches). With **4 UEs all four answer the same RAR
  and their msg3 collide on every attempt** (`crc=KO`, zero attaches), after which the gNB
  ZMQ sample loop stalls. This is the precise mechanism behind the earlier "~2 UEs per
  cell" rule of thumb; scaling past it needs **split bridges** (the two-cell approach) or
  **per-UE diversity** (different preambles, or unequal per-input gain so capture effect
  lets UEs attach in a rolling fashion). The variant was set to `NUM_UES=2`.
- **Low-load bidirectional traffic still wedges on a CPU-starved host.** With 2 UEs
  attached and full connectivity (DNS + ping to `google.com`, 0% loss idle), even **1 Mbps
  bidirectional** UDP drove the ping RTT to **~18 s** (bufferbloat) and wedged both UEs'
  RLC within ~2 minutes, at host load ~16 on 8 cores. Because **UDP has no congestion
  control**, iperf keeps sending above the CPU-limited link capacity and the buffers grow
  without bound. The methodological lesson: read the *idle* ping (after the stream stops)
  as the connectivity gate — multi-second mid-stream RTT is bufferbloat, not a dead link —
  and keep UDP well under capacity (or use TCP, which self-limits). A standalone runbook
  (`docs/RUNBOOK_SINGLE_CELL_DIRS.md`) documents the variant for a better-provisioned host.
- **A Bash gotcha worth one line.** Single-cell mode is "no cell-2 UEs", but the original
  orchestrator used `${CELL2_UES:-3,4}`, and `:-` substitutes the default for an *empty*
  value too — so `CELL2_UES=` still routed UEs to a non-existent second gNB. Use
  `${CELL2_UES:-}` (or `${VAR-default}` without the colon) when an empty value must mean
  "off".

### 5.8 Catalogue of diagnosed issues (engineering learnings)

The recurring engineering theme across the whole internship is that **most "radio"
failures were really configuration, networking, or host-capacity failures**, and that
**real-time RAN needs guaranteed CPU**. The diagnosed issues are catalogued below; each
has a self-contained post-mortem in the engineering journal (`docs/journal/`).

| Symptom | Root cause | Fix / status |
|---|---|---|
| Open5GS/UE no internet | macvlan parented on OVS → broken ARP | `internet` bridge for 5GC egress; (proper: macvlan on NIC) |
| UE can't reach gateway | UE pool ≠ `ogstun` subnet | pin SMF/UPF `session` subnet+gateway to UE pool |
| Per-UE routing fails | empty `ueN` netns, no PDN iface | netns-per-UE model; add route after `tun_srsue` appears |
| gNB crashes at E2 setup | e2mgr/Redis startup race → e2term can't route | self-healing RIC start (restart e2mgr, re-init e2term) |
| No `gnbd_` DU node / KPM fails | `e2sm_ccc_enabled: true` blocks E2 setup | ship configs with CCC off for KPM work |
| Per-UE CQI/RSRP/RSRQ = 0 | srsRAN E2SM-KPM hardcodes `last_ue_metrics[0]` | trust thp/PRB/delay/volume; CQI/RSRP/RSRQ unreliable |
| `DRB.UEThpDl` ≈ 0 | traffic was uplink-only | add `--reverse`/`--bidir` (iperf3 `-R`/`--bidir`) |
| Slice-2 UE rejected (NAS cause 62) | ephemeral mongo lost SST override | re-provision slice-2 after every gNB cycle |
| UE `RRC Release` after connect | release before PDU session (NAS/slice/AMF reach) | check 5GC NAS logs; bisect config restructure |
| RLC DRB wedge (UL KPM=0, ping loss) | host CPU starvation → ZMQ sample underruns | guaranteed CPU; cycle gNB + re-attach to recover |
| UE can't reattach | ZMQ ports won't re-handshake | cycle the gNB (lockstep restart) |
| 4 UEs won't attach on one bridge | all use PRACH preamble 0 → msg3 collide | ≤2 UEs/summed bridge; split bridges or add diversity |
| Low-load bidir wedges | UDP floods CPU-limited link (no backoff) | keep rate under capacity; use TCP; more host CPU |
| RF Late/Underflow → session drop | host misses radio deadlines | `srsran_performance`; CPU pinning; (VM: P-cores) |
| B210 "No UHD Devices Found" after reboot | USB power-save / firmware reload | re-plug, `uhd_usrp_probe`, disable USB autosuspend |
| docker build fails on `apt` | transient Ubuntu mirror sync, not the Dockerfile | retry; pin mirror / `Acquire::Retries` |
| SD slice "mismatch" | Open5GS SD = hex, srsRAN SD = decimal | `0x111111` ⇒ `1118481`; add `cell_cfg.slicing` |

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
- **Experiment suite:** ZMQ — iperf throughput, connectivity, VoIP, multi-UE, and
  **bidirectional (UL+DL)** low-load streaming with per-UE export; UHD — video streaming
  over the air. A reusable checkpoint driver runs a timed stability test (e.g. 30 min,
  5-minute checkpoints) with ping + throughput + RLC-wedge checks.
- **Engineering documentation:** a setup guide, runbooks for the 2-gNB/2-slice and the
  standalone single-cell variants, and an **engineering journal** (`docs/journal/`, ~16
  template-structured post-mortems indexed by a README) — so the testbed is maintainable
  and the failures are documented learnings, not "tribal knowledge."

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
**reproducibility** (containerising the whole stack, writing runbooks, keeping an
engineering journal, reproducing a hardware bug in software). Three cross-cutting
engineering lessons stand out:

- **Many "radio" failures are really configuration/core failures** — the decimal-vs-hex
  slice bug is the clearest example, but the NAS-cause-62 slice rejection, the
  uplink-only "no downlink KPM", and the macvlan/ARP and subnet-mismatch networking
  faults all fit the pattern. Always check the config and the core logs before blaming
  the air interface.
- **Real-time RAN needs guaranteed CPU, not just enough CPU.** The single most recurrent
  failure class — RF Late/Underflow on the SDR, RLC DRB wedges under ZMQ, PRACH-pool
  depletion in a VM — all traced to the host missing microsecond-scale deadlines under
  load or under hybrid-core/hypervisor scheduling. The durable fixes are about
  *isolation* (CPU pinning, P-cores, headroom), and it is a latency problem, not a
  throughput problem.
- **Be careful how you load-test.** UDP has no congestion control, so an offered rate
  above the (CPU-limited) link capacity silently produces multi-second bufferbloat and
  then corrupts state — the throughput number looks fine right up until it wedges. Read
  the *idle* recovery as the real health gate, and prefer self-limiting traffic (TCP) or
  rates safely under capacity.

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
- `docs/journal/` — **engineering journal**: template-structured post-mortems for every
  diagnosed issue, indexed (newest-first) by `docs/journal/README.md`. The primary record
  of the learnings summarised in §5.8.
- `docs/RUNBOOK_2GNB_2SLICE.md` — two-gNB / two-slice deployment runbook.
- `docs/RUNBOOK_SINGLE_CELL_DIRS.md` — standalone single-cell (directory-based, no RIC,
  bidirectional traffic) runbook.
- `docs/UHD_SLICE_REPORT.md`, `docs/UHD_SLICE_TROUBLESHOOTING.md` — slice root-cause
  analysis, reproduction, and fixes.
- `srsRAN_Project/gnb-zmq/`, `srsRAN_Project/gnb-zmq-single-cell/`,
  `srsRAN_Project/gnb-uhd/` — the RF-variant / topology deployments.
- `multi_ue/`, `multi_ue-single-cell/` — multi-UE containers (co-located ZMQ bridge,
  per-UE netns, `--bidir`/`--reverse` traffic), plus `checkpoint_sc.sh` for timed tests.
- `oran-sc-ric/` — RIC platform and xApps (`kpm_mon_xapp.py`, `simple_rc_xapp.py`,
  `simple_rc_ho_xapp.py`, …).
- `experiments/zmq/`, `experiments/uhd/` — experiment configurations and captures.
- `tracks/` — raw investigation artefacts (logs, configs) behind several journal entries.
