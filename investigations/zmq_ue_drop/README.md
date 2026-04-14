# Problem 
- the gnb starts successfully 
- the bridge connect 
- both the ue1 and ue2 start
- the ues connect to the gnb 
- the gnb drops the ue due to inactivity 

the old functuioning gnb config ./zmq_sample.yaml
the new zmq config ./gnb_zmqq.yaml
ue logs ./ue.log
gnb logs ./gnb.log

the network
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
| ue1_default | bridge | local | false | 172.18.0.0/16 (gw: 172.18.0.1) | - |
| ue2_default | bridge | local | false | 172.20.0.0/16 (gw: 172.20.0.1) | - |
