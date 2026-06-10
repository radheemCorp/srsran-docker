# Network structure

This file summarizes the networks used in this workspace and why they exist.

| Network | Subnet | Purpose (short reason) | Current containers (from `cip`) |
| --- | --- | --- | --- |
| n2 | 10.53.1.0/24 | 5GC control-plane (AMF/NGAP) between gNB and Open5GS | `srsran_gnb`, `open5gs_5gc` |
| n3 | 10.10.3.0/24 | User-plane network for gNB N3 interface | `srsran_gnb` |
| ue_n3 | 10.10.4.0/24 | UE/bridge-side ZMQ network to avoid macvlan hairpin limits | `ue1`, `ue2`, `zmq_bridge` |
| metrics | 172.19.1.0/24 | Telemetry stack (InfluxDB/Telegraf/Grafana) | `srsran_gnb`, `grafana`, `telegraf`, `influxdb` |
| oran-sc-ric | 10.0.2.0/24 | ORAN-SC Near-RT RIC services | `srsran_gnb`, `ric_submgr`, `python_xapp_runner`, `ric_rtmgr_sim`, `ric_e2term`, `ric_appmgr`, `ric_dbaas`, `ric_e2mgr` |
| gnb-zmq_default | 172.18.0.0/16 | Default docker-compose network for gNB/5GC stack | `open5gs_5gc` |
| host | host | Host network for metrics agent | `ue1-ue_metrics_agent-1` |

Notes:
- The gNB attaches to multiple networks: `n2` for control-plane, `n3` for user-plane, `metrics` for telemetry, and `oran-sc-ric` for RIC.
- The UE/bridge ZMQ path uses `ue_n3` (10.10.4.0/24), and routing/NAT is used to reach the gNB on `n3` (10.10.3.0/24).
