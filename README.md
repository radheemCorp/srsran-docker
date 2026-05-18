# Docker SRS-RAN & ORAN-SC RIC

> End-to-end 5G RAN lab: Dockerized srsRAN gNB (ZMQ / UHD), Open5GS core, and ORAN-SC RIC with xApps — all running on a single host without external RF infrastructure.

## What This Is

This repository packages a **complete 5G standalone testbed** into reproducible Docker containers. It lets you:

- Deploy a real 5G gNB (base station) using the [srsRAN Project](https://github.com/srsran/srsRAN_Project), either **over ZMQ** (virtual RF, single-host) or **UHD** (physical SDR hardware like USRP B210)
- Deploy the [Open5GS](https://open5gs.org/) 5G core network (AMF, SMF, UPF, UDM) as a Docker Compose service

- Deploy the [ORAN-SC Near-Real-time RIC](https://github.com/o-ran-sc) (optional) — a lightweight, K8s-free implementation of the O-RAN RIC platform
- Run and develop **[xApps](oran-sc-ric/xApps/python/)** that monitor and control the gNB in real-time via the E2 interface (KPM metrics, PRB rate control, handover)
- Visualize 5G radio metrics (MCS, BLER, UE throughput) through a Telegraf → InfluxDB → Grafana stack

Everything runs on a single Linux host. No external RF is needed — the ZMQ mode uses virtual radio, and the UHD mode runs on real SDR hardware plugging in via USB.

## Quick Start

The fastest way to get a working lab:

```bash
# 1. Clone and enter the repo
git clone <this-repo>
cd docker-srsran

# 2. Build all Docker images (shared Dockerfile builds both gNB and Open5GS)
cd srsRAN_Project/docker
docker compose build
cd ../..

# 3. Create Docker and host networks
./scripts/net_manage.sh init

# 4. Deploy the core network
cd srsRAN_Project/gnb-zmq        # or gnb-uhd
docker compose up -d 5gc
cd ../../oran-sc-ric              # optional: deploy RIC
docker compose up -d
cd ../gnb-zmq                     # or gnb-uhd

# 5. Deploy the gNB
docker compose up -d gnb
```

For step-by-step instructions, see the setup guides below.

## Where to Go From Here

| What you want to do | Go here |
|---------------------|---------|
| **Set up a ZMQ-based virtual-RF lab** | [`SETUP_GNB_ZMQ.md`](SETUP_GNB_ZMQ.md) |
| **Set up a UHD-based SDR lab** | [`SETUP_GNB_UHD.md`](SETUP_GNB_UHD.md) |
| **Understand the ORAN-SC RIC** | [`oran-sc-ric/README.md`](oran-sc-ric/README.md) |
| **Configure your UE (phone) in Open5GS WebUI** | [Set up section in either guide] |
| **Run xApps (monitoring, rate control, handover)** | `SETUP_GNB_ZMQ.md` §12 / `SETUP_GNB_UHD.md` §10 |
| **Troubleshoot (common issues, KNOWN_ISSUES)** | [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) |

## Project Structure

```
.
├── README.md                 ← You are here
├── SETUP_GNB_ZMQ.md          ← Full ZMQ (virtual RF) deployment guide
├── SETUP_GNB_UHD.md          ← Full UHD (physical SDR) deployment guide
├── TESTING.md                ← iperf and throughput testing procedures
├── KNOWN_ISSUES.md           ← Documented problems and workarounds
├── CHANGELOG.md              ← Build and Docker Compose changelog
├── NOTES.md                  ← Freeform notes and decisions

├── srsRAN_Project/           ← srsRAN 5G RAN source + Docker builds
│   ├── docker/               ← Dockerfile + compose files that build gNB & Open5GS
│   ├── gnb-zmq/              ← ZMQ-based gNB deployment (Docker Compose + configs)
│   ├── gnb-uhd/              ← UHD-based gNB deployment (Docker Compose + configs)
│   ├── apps/                   srsRAN gNB/gNodeB binaries built by Dockerfile
│   ├── lib/                    srsRAN C/C++ libraries
│   ├── include/                Public headers
│   └── docs/                   srsRAN upstream documentation

├── oran-sc-ric/              ← ORAN-SC Near-Real-time RIC (O-RAN compliant)
│   ├── ric/                    RIC platform services (e2term, e2mgr, dbaas, etc.)
│   ├── e2-agents/              E2 agent configs for connecting gNB to RIC
│   ├── xApps/                  Example xApps:
│   │   └── python/               kpm_mon_xapp.py, simple_mon_xapp.py,
│   │                               simple_rc_xapp.py, simple_rc_ho_xapp.py,
│   │                               simple_ccc_xapp.py
│   └── docker-compose.yml


├── ue/                       ← UE containers (Docker-based virtual UEs)
│   ├── ue1/                    UE container configuration (network namespace)
│   ├── ue2/                    Second UE
│   ├── bridge/                 Host bridge for virtual RF (macvlan + child net)
│   ├── iperf-server/           iperf test server UE
│   ├── ue_setup.sh             Create network namespaces
│   ├── ue_stop.sh
│   └── ue_restart.sh


├── scripts/                  
|   ├── docker_cleanup.sh       Clean up all containers/networks
│   ├── dockstatus.sh           Show running containers + IPs
│   ├── net_manage.sh           Docker network lifecycle (create/init/remove/validate)
│   └── get_open5gs_subscribers.sh Query subscribers from Open5GS DB


├── docs/                     ← Supporting documentation & guides
│   ├── FIND_UHD_DEVICE.md      Detect and probe USRP B210 hardware
│   ├── GNB_TUTORIAL.md         gNB configuration tutorial
│   ├── configure_performance.sh        TUNE Linux host for 5G performance
│   ├── networks.md             Network topology overview (n2, n3, n6, ric, etc.)
│   ├── subscribers.md          Subscriber management reference
│   ├── env_setup.md            Host environment setup notes
│   └── journal/                Session logs and debug records

├── tracks/                   ← Investigation logs and experiment tracking
│   ├── sdr-device-lost.md      Tracking: intermittent SDR disconnections
│   ├── zmq_ue_drop              UE drop troubleshooting
│   ├── successful_uhd_on_host  UHD on bare-metal host notes
│   └── ...other experimental branches
```

## Key Concepts

### Two gNB Modes

| Mode | RF | Host Requirements | Best For |
|-------|--------|-------------------------------|
| `gnb-zmq` | Virtual (ZMQ) | Docker only, no hardware | Development, xApp testing, CI |
| `gnb-uhd` | Physical (UHD) | USRP B210/B200 USB + UHD driver | Radio layer debugging, spectrum work |

### ORAN-SC RIC (Optional but Recommended)

The RIC adds an E2 interface to the gNB, enabling real-time O-RAN workflows:

- **xApps** connect to the RIC to subscribe to metrics from the gNB
- **E2SM-KPM** — key performance metrics (throughput, MCS, BLER)
- **E2SM-RC** — resource control (PRB ratio, slice quotas)
- **E2SM-CCC** — cell configuration control
- Handover control via `simple_rc_ho_xapp`


## Tooling at a Glance

| Script | Purpose |
|---------------|----------|
| `scripts/net_manage.sh init` | Create all Docker + host networks in one step |
| `scripts/net_manage.sh remove` | Tear down all managed networks |
| `scripts/dockstatus.sh` | List running containers and their IPs |
| `scripts/docker_cleanup.sh` | Stop and remove all containers and networks |
| `scripts/get_open5gs_subscribers.sh` | Query the Open5GS subscriber DB |

## Prerequisites

- **Linux** (Ubuntu 22.04+ tested) with Docker and Docker Compose v2
- **Kernel**: `5.15+` recommended for DPDK/macvlan support (ZMQ mode)
- **For UHD**: USRP B210/B200 device + UHD drivers (`uhd-host` package)
- **Resources**: 4 vCPU / 8 GB RAM minimum (more for UHD with real RF)

## Licensing

- srsRAN Project components: subject to [srsRAN licensing](srsRAN_Project/)
- ORAN-SC RIC components: ORAN SC [LICENSE](oran-sc-ric/LICENSE)
- This repository's Docker glue code and docs: MIT


# REFERENCE
- [srsran gnb config sample](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/config_ref.html)
- [srsran gnb with ue tutorial](https://docs.srsran.com/projects/project/en/latest/tutorials/source/srsUE/source/index.html)
-   