# Description 
this document lists the networks in use and the configuration for each 

# setup / teardown 
the networks are setup using scripts/net_setup.sh and teardown using scripts/net_cleanup.sh

# Network description
## Configuration and function
|Network Name|Driver|Subnet|Gateway|MTU|Primary Function|
|------------|------|------|-------|---|----------------|
|n3br|Macvlan|10.10.3.0/24|10.10.3.254|1450|N3 Interface: User Plane (GTP-U traffic)|
|n4br|Macvlan|10.54.1.0/24|10.54.1.254|1450|N4 Interface: PFCP (Session Management)|
|n6br|Macvlan|10.55.1.0/24|10.55.1.254|1500|N6 Interface: External Data Network/Internet|
|n2network|Bridge|10.53.2.0/24|10.53.2.254|1500|Secondary signaling / Control Plane isolation|
|ric_network|Bridge|10.0.2.0/24|10.0.2.254|1500|E2 Interface: O-RAN RIC and xApp comms|
|metrics|Bridge|172.19.1.0/24|172.19.1.254|1500|"Prometheus| Grafana| and UE metrics agents"|
|ran|Macvlan|10.53.1.0/24|10.53.1.254|1450|N2 Interface: gNB signaling to AMF|

## gNB / UE config matching
The most important configuration values to match between gNB, UE, bridge, and core are:

- `n3br` is the ZMQ RF transport network.
  - gNB N3 IP: `10.10.3.231`
  - ZMQ bridge IP: `10.10.3.236`
  - gNB ZMQ ports: `2000` (DL TX from gNB -> bridge), `2001` (UL RX to gNB <- bridge)
  - UE1 bind IP: `10.10.3.234`
  - UE2 bind IP: `10.10.3.235`
  - UE ZMQ bridge ports:
    - UE1: `tx_port=tcp://10.10.3.234:2101`, `rx_port=tcp://10.10.3.236:2201`
    - UE2: `tx_port=tcp://10.10.3.235:2102`, `rx_port=tcp://10.10.3.236:2202`

- `ran` is the control plane network used by gNB and Open5GS.
  - gNB on `ran`: `10.53.1.3`
  - AMF on `ran`: `10.53.1.2`
  - gNB N2 connect address: `10.53.1.2:38412`

- `ric_network` is the E2 interface.
  - gNB E2 bind IP: `10.0.2.30`
  - RIC IP: `10.0.2.10`
  - E2 port: `36421`

- Core subscriber settings must match the UE IMSI/APN/slice.
  - UE IMSIs: `001010000000001`, `001010000000002`
  - APN: `internet`
  - slice SST: `1`
  - PLMN: `00101`
  - subscribers are defined in `project-config/subscriber_db.csv`

These values are set in:
- `project-config/gnb/gnb_zmq.yml`
- `project-config/gnb/gnb_compose_config.yml`
- `external_ue/ue1/docker-compose.yaml`
- `external_ue/ue2/docker-compose.yaml`
- `external_ue/ue1/config/generate_ue_conf.py`
- `external_ue/ue2/config/generate_ue_conf.py`
- `docker-compose.yml`
- `project-config/subscriber_db.csv`

## subnet specification
| Name | Driver | Scope | Internal | IPv4 Subnets | IPv6 Subnets |
|---|---|---|---|---|---|
| bridge | bridge | local | false | 172.17.0.0/16 (gw: 172.17.0.1) | - |
| host | host | local | false | - | - |
| metrics | bridge | local | false | 172.19.1.0/24 (gw: 172.19.1.254) | - |
| n2network | bridge | local | false | 10.53.2.0/24 (gw: 10.53.2.254) | - |
| n3br | macvlan | local | false | 10.10.3.0/24 (gw: 10.10.3.254) | - |
| n4br | macvlan | local | false | 10.54.1.0/24 (gw: 10.54.1.254) | - |
| n6br | macvlan | local | false | 10.55.1.0/24 (gw: 10.55.1.254) | - |
| none | null | local | false | - | - |
| oran-sc-ric_ric_network | bridge | local | false | 10.0.2.0/24 (gw: 10.0.2.254) | - |
| ran | bridge | local | false | 10.53.1.0/24 (gw: 10.53.1.254) | - |