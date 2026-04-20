radr@devred:~/tuilm/srsran-docker$ cip
------------------------------------------------------
CONTAINER              ┊ IP                              ┊ PORT        ┊ EXT_PORT ┊ NETWORKS           ┊ WORKDIR                                               ┊ DEPENDS_ON
ue2-ue_metrics_agent-1 ┊ 172.20.0.2                      ┊  "9100/tcp" ┊          ┊ ue2_default        ┊ /home/radr/tuilm/srsran-docker/external_ue/ue2        ┊ 
srsran_ue_host2        ┊ 10.54.1.235                     ┊             ┊          ┊ ue-net             ┊ /home/radr/tuilm/srsran-docker/external_ue/ue2        ┊ 
ue1-ue_metrics_agent-1 ┊ 172.18.0.2                      ┊  "9100/tcp" ┊          ┊ ue1_default        ┊ /home/radr/tuilm/srsran-docker/external_ue/ue1        ┊ 
srsran_ue_host         ┊ 10.54.1.234                     ┊             ┊          ┊ ue-net             ┊ /home/radr/tuilm/srsran-docker/external_ue/ue1        ┊ 
srsran_zmq_bridge      ┊ 172.19.1.6 10.53.1.6 10.54.1.6  ┊             ┊          ┊ metrics ran ue-net ┊ /home/radr/tuilm/srsran-docker/external_ue/zmq_bridge ┊ 
srsran_gnb             ┊ 172.19.1.3 10.53.1.3            ┊             ┊          ┊ metrics ran        ┊ /home/radr/tuilm/srsran-docker/srsRAN_Project/gnb-zmq ┊ 5gc
open5gs_5gc            ┊ 10.53.1.2                       ┊  "9999/tcp" ┊ 9999     ┊ ran                ┊ /home/radr/tuilm/srsran-docker/srsRAN_Project/gnb-zmq ┊ 
------------------------------------------------------
radr@devred:~/tuilm/srsran-docker$ 


# srsRAN Docker Networks
radr@devred:~/tuilm/srsran-docker$ dnet
NETWORK                        IPv4 SUBNETS                   IPv6 SUBNETS                            
-------                        ------------                   ------------                            
bridge                         172.17.0.0/16                  -                                       
host                           -                              -                                       
metrics                        172.19.1.0/24                  -                                       
none                           -                              -                                       
ran                            10.53.1.0/24                   -                                       
ue1_default                    172.18.0.0/16                  -                                       
ue2_default                    172.20.0.0/16                  -                                       
ue-net                         10.54.1.0/24                   -                                       
radr@devred:~/tuilm/srsran-docker$ 

# Bridge 
radr@devred:~/tuilm/srsran-docker/srsRAN_Project/gnb-zmq$ docker exec srsran_zmq_bridge ss -tnp
State    Recv-Q    Send-Q       Local Address:Port        Peer Address:Port     Process                                                                         
ESTAB    0         0                10.53.1.6:2001           10.53.1.3:53350     users:(("python3",pid=8,fd=45))                                                
ESTAB    0         0                10.54.1.6:42536        10.54.1.235:2102      users:(("python3",pid=8,fd=38))                                                
ESTAB    0         0                10.53.1.6:43580          10.53.1.3:2000      users:(("python3",pid=8,fd=9))                                                 
ESTAB    0         0                10.54.1.6:50854        10.54.1.234:2101      users:(("python3",pid=8,fd=28))   

# UE1 
## logs 
radr@devred:~/tuilm/srsran-docker/external_ue$ docker compose --project-directory "/home/radr/tuilm/srsran-docker/external_ue/ue1" -f "/home/radr/tuilm/srsran-docker/external_ue/ue1/docker-compose.yaml" exec -it srsran_ue_host bash -lc '/srsran/config/start_ue.sh 1'
Waiting for tun_srsue to appear...
Configuration for UE1 written to /tmp/ue_1.conf
Active RF plugins: libsrsran_rf_zmq.so
Inactive RF plugins: 
Reading configuration file /tmp/ue_1.conf...

Built in Release mode using commit ec29b0c1f on branch master.

Opening 1 channels in RF device=zmq with args=tx_port=tcp://*:2101,rx_port=tcp://10.53.1.6:2201,base_srate=23.04e6
Supported RF device list: zmq file
CHx base_srate=23.04e6
Current sample rate is 1.92 MHz with a base rate of 23.04 MHz (x12 decimation)
CH0 rx_port=tcp://10.53.1.6:2201
CH0 tx_port=tcp://*:2101
Current sample rate is 23.04 MHz with a base rate of 23.04 MHz (x1 decimation)
Current sample rate is 23.04 MHz with a base rate of 23.04 MHz (x1 decimation)
Waiting PHY to initialize ... done!
Attaching UE...


## state
radr@devred:~/tuilm/srsran-docker/external_ue$ docker compose --project-directory "/home/radr/tuilm/srsran-docker/external_ue/ue1" -f "/home/radr/tuilm/srsran-docker/external_ue/ue1/docker-compose.yaml" exec -it srsran_ue_host bash
root@50699e22dafd:/# ip netns ls  
ue1
root@50699e22dafd:/# ip netns exec ue1 ip a 
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
root@50699e22dafd:/# ip netns exec ue1 ping 10.54.1.6 
ping: connect: Network is unreachable
root@50699e22dafd:/# ip netns exec ue1 ping 10.53.1.6 
ping: connect: Network is unreachable
root@50699e22dafd:/# ip netns exec ue1 ping 10.53.1.3 
ping: connect: Network is unreachable
root@50699e22dafd:/# ping 10.53.1.3
PING 10.53.1.3 (10.53.1.3) 56(84) bytes of data.
^C
--- 10.53.1.3 ping statistics ---
4 packets transmitted, 0 received, 100% packet loss, time 3062ms

root@50699e22dafd:/# ping 10.54.1.6
PING 10.54.1.6 (10.54.1.6) 56(84) bytes of data.
64 bytes from 10.54.1.6: icmp_seq=1 ttl=64 time=0.412 ms
64 bytes from 10.54.1.6: icmp_seq=2 ttl=64 time=0.074 ms
64 bytes from 10.54.1.6: icmp_seq=3 ttl=64 time=0.049 ms
64 bytes from 10.54.1.6: icmp_seq=4 ttl=64 time=0.052 ms
^C
--- 10.54.1.6 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3057ms
rtt min/avg/max/mdev = 0.049/0.146/0.412/0.153 ms

## Configuration checklist and expected values

### Networks
- `ran` network
  - Significance: RAN/OAM control plane network for gNB and Open5GS signaling.
  - Expected value: `10.53.1.0/24`
  - Current use: `srsran_gnb` `10.53.1.3`, `open5gs_5gc` `10.53.1.2`, `srsran_zmq_bridge` `10.53.1.6`
- `ue-net` network
  - Significance: ZMQ transport network between UE containers and the bridge.
  - Expected value: `10.54.1.0/24`
  - Current use: `srsran_ue_host` `10.54.1.234`, `srsran_ue_host2` `10.54.1.235`, `srsran_zmq_bridge` `10.54.1.6`
- `metrics` network
  - Significance: Monitoring/metrics traffic only.
  - Expected value: `172.19.1.0/24`
  - Current use: `srsran_gnb`, `srsran_zmq_bridge`

### gNB configuration
- `gNB N3 IP`
  - Significance: source address for gNB ZMQ TX and RX control.
  - Expected value: `10.53.1.3`
- `gNB ZMQ TX endpoint` (`tx_port`)
  - Significance: where gNB publishes downlink samples for the bridge to receive.
  - Expected value: `tcp://10.53.1.3:2000`
- `gNB ZMQ RX endpoint` (`rx_port`)
  - Significance: where gNB receives uplink samples from the bridge.
  - Expected value: `tcp://10.53.1.6:2001`

### Bridge configuration
- `GNB_IP`
  - Significance: gNB listen address for bridge-side ZMQ forwarding.
  - Expected value: `10.53.1.3`
- `BRIDGE_IP`
  - Significance: bridge address on the `ran` network and the endpoint UEs use for `rx_port`?
  - Expected value: `10.53.1.6` on `ran` for gNB-facing RX, and `10.54.1.6` on `ue-net` for UE-facing RX.
- `UE_IP_PREFIX`
  - Significance: compute UE container ZMQ host IPs for the bridge.
  - Expected value: `10.54.1.`
- `UE_IP_BASE`
  - Significance: base offset for UE host IP mapping.
  - Expected value: `233` → UE1 `10.54.1.234`, UE2 `10.54.1.235`
- `BIND_ALL=1`
  - Significance: ensure bridge reply sockets accept connections on all attached interfaces.

### UE configuration
- `GNB_IP`
  - Significance: gNB ZMQ address the UE uses in bridge mode.
  - Expected value: `10.53.1.3`
- `ZMQ_BRIDGE_IP`
  - Significance: bridge address the UE uses for its ZMQ `rx_port`.
  - Expected value: `10.54.1.6`
- `UE_ZMQ_MODE=bridge`
  - Significance: enables bridge mode instead of direct UE<->gNB ZMQ.
- `UE_USE_NETNS=true`
  - Significance: create `tun_srsue` inside a private namespace and route traffic through it.

### Open5GS / UE subscriber configuration
- `OPEN5GS_IP`
  - Significance: core control-plane IP on `ran`.
  - Expected value: `10.53.1.2`
- `UE_IP_BASE`
  - Significance: base for the UE PDN subnet assigned to subscribers.
  - Expected value: `10.41.0`
- `UE_IP_RANGE`
  - Significance: subnet used by Open5GS for UE PDN addresses.
  - Expected value: `10.41.0.0/24`
- `UE_GATEWAY_IP`
  - Significance: UPF gateway for UE PDN traffic inside Open5GS.
  - Expected value: `10.41.0.1`
- Subscriber `ip_alloc`
  - Significance: the actual UE PDN IP assigned during attach.
  - Expected values:
    - IMSI `001010000000001` → `10.41.0.2`
    - IMSI `001010000000002` → `10.41.0.3`

### Current mismatch risk
- The UE transport network (`ue-net`) and the UE PDN subnet (`10.41.0.0/24`) must remain separate.
- The UE container ZMQ host IPs `10.54.1.234` / `10.54.1.235` are only for ZMQ transport, not for subscriber `ip_alloc`.
- The current configuration matches that principle.

### Significance summary
- `ran`: gNB + core signaling path; must carry N2/N3 control traffic.
- `ue-net`: ZMQ bridge transport path for UE RF samples; must not be reused as UE subscriber IP space.
- `10.41.0.0/24`: UE PDN subnet managed by Open5GS; must be reachable from UPF and not overlap `ue-net`.
- `10.54.1.6`: bridge address on `ue-net`; the UE must use this for ZMQ `rx_port`.
- `10.53.1.6`: bridge address on `ran`; gNB uses this for ZMQ uplink.

root@50699e22dafd:/# 