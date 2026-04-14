# Multi-UE Quick Start (host_ue)

This is the shortest run order for 2 UEs in 2 containers plus one bridge container.

## 1) Host network (once)

```bash
sudo ip link set n3br up
sudo ip addr del 10.10.3.1/24 dev n3br || true
sudo ip addr add 10.10.3.254/24 dev n3br

docker network create -d macvlan --subnet=10.10.3.0/24 --gateway=10.10.3.254 -o parent=n3br n3br
```

## 2) Start core and gNB

- Ensure Open5GS is running (single SMF/UPF mode).
- Ensure gNB uses bridge endpoint in `configs/srsRAN/srsran-gnb/config/srsran-gnb.yaml`:
  - `rx_port=tcp://10.10.3.236:2001`
- Start/restart gNB once, then keep it running.

## 3) Start bridge

```bash
cd host_ue/host_ue_bridge
docker compose up -d
docker exec srsran_zmq_bridge ss -tnp
```

Expected:
- ESTAB to gNB on `2000/2001`.
```bash
$ docker exec srsran_zmq_bridge ss -tnp
State      Recv-Q   Send-Q       Local Address:Port        Peer Address:Port    Process                                                                         
SYN-SENT   0        1              10.10.3.236:48082        10.10.3.234:2101     users:(("python3",pid=8,fd=30))                                                
ESTAB      0        0              10.10.3.236:2001         10.10.3.231:56332    users:(("python3",pid=8,fd=45))                                                
ESTAB      0        0              10.10.3.236:54552        10.10.3.231:2000     users:(("python3",pid=8,fd=12))                                                
SYN-SENT   0        1              10.10.3.236:49696        10.10.3.235:2102     users:(("python3",pid=8,fd=38))                   
```

## 4) Start UE1

```bash
cd host_ue/host_ue1
docker compose up -d
docker compose exec -it srsran_ue_host bash
/srsran/config/start_ue.sh 1
```

## 5) Start UE2

```bash
cd host_ue/host_ue2
docker compose up -d
docker compose exec -it srsran_ue_host bash
/srsran/config/start_ue.sh 2
```

## 6) Validate both UEs

Inside UE1 container:

```bash
ip netns exec ue1 ip a
ip netns exec ue1 ip route
ip netns exec ue1 ping -c3 10.41.0.1
ip netns exec ue1 ping -c3 google.com
```

Inside UE2 container:

```bash
ip netns exec ue2 ip a
ip netns exec ue2 ip route
ip netns exec ue2 ping -c3 10.41.0.1
ip netns exec ue2 ping -c3 google.com
```

## Notes

- If UE console stays at `Attaching UE...`, confirm attach via AMF/SMF logs and `tun_srsue` in netns.
- Avoid restarting gNB during UE attach tests.
- If gNB is restarted, restart UE processes afterward.

## Detailed runbooks

- `host_ue/host_ue1/setup.md`
- `host_ue/host_ue2/setup.md`
- `host_ue/host_ue_bridge/setup.md`
- `host_ue/multi_ue_containers_plan.md`
