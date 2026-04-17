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