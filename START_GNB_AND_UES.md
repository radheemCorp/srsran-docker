# Start gNB Then UEs (External ZMQ Multi-UE)

This guide starts the deployment in the required order:
1. Open5GS + gNB
2. ZMQ bridge
3. UE1 and UE2

It uses these files:
- `srsRAN_Project/docker/docker-compose.yml`
- `srsRAN_Project/docker/docker-compose.external-ue-zmq.yml`
- `srsRAN_Project/configs/gnb_zmq_external_ue.yml`

The gNB image build in this workflow includes required runtime dependencies for UHD/ZMQ and DPDK-linked binaries.

## Prerequisites

- Docker and Docker Compose plugin installed.
- Host interface `n3br` exists and is usable for macvlan.
- External UE folders are present:
  - `external_ue/host_ue_bridge`
  - `external_ue/host_ue1`
  - `external_ue/host_ue2`

## 1) Create/prepare N3 network (one-time)

Run on host:

```bash
sudo ip link set n3br up
sudo ip addr del 10.10.3.1/24 dev n3br || true
sudo ip addr add 10.10.3.254/24 dev n3br

docker network create -d macvlan \
  --subnet=10.10.3.0/24 \
  --gateway=10.10.3.254 \
  -o parent=n3br \
  ue_n3
```

If `ue_n3` already exists, Docker will report it. That is fine.

Note:
- `host_ue1` and `host_ue2` are configured to use static IPs on this external network:
  - UE1 container: `10.10.3.234`
  - UE2 container: `10.10.3.235`
- Bridge uses `10.10.3.236` on `ue_n3`.

## 2) Build and start Core + gNB

```bash
cd /home/radr/tuilm/srsran-build/srsRAN_Project/docker

docker compose -f docker-compose.yml -f docker-compose.external-ue-zmq.yml build gnb

docker compose -f docker-compose.yml -f docker-compose.external-ue-zmq.yml up -d 5gc gnb
```

Check logs:

```bash
docker compose -f docker-compose.yml -f docker-compose.external-ue-zmq.yml logs -f gnb
```

Expected:
- gNB starts with ZMQ config (`gnb_zmq_external_ue.yml`).
- gNB connects to AMF.

## 3) Start ZMQ bridge

```bash
cd /home/radr/tuilm/srsran-build/external_ue/host_ue_bridge
docker compose up -d
```

Check sockets:

```bash
docker exec srsran_zmq_bridge ss -tnp
```

Expected:
- ESTAB between bridge and gNB on ports `2000/2001`.

## 4) Start UE1

```bash
cd /home/radr/tuilm/srsran-build/external_ue/host_ue1
docker compose up -d
docker compose exec -it srsran_ue_host bash
```

Inside container:

```bash
UE_ZMQ_MODE=bridge ZMQ_BRIDGE_IP=10.10.3.236 /srsran/config/start_ue.sh 1
```

## 5) Start UE2

In a second terminal:

```bash
cd /home/radr/tuilm/srsran-build/external_ue/host_ue2
docker compose up -d
docker compose exec -it srsran_ue_host bash
```

Inside container:

```bash
UE_ZMQ_MODE=bridge ZMQ_BRIDGE_IP=10.10.3.236 /srsran/config/start_ue.sh 2
```

## 6) Validate attach and traffic

Check Open5GS and gNB logs for both IMSIs registering and PDU sessions created.

Bridge socket sanity check:

```bash
docker exec srsran_zmq_bridge ss -tnp
```

Expected (all should be `ESTAB`):
- gNB <-> bridge on `2000/2001`
- bridge <-> UE1 on `2101/2201`
- bridge <-> UE2 on `2102/2202`

Inside UE1 container:

```bash
ip netns exec ue1 ip a
ip netns exec ue1 ip route
ip netns exec ue1 ping -c3 10.41.0.1
ip netns exec ue1 ping -c3 8.8.8.8
```

Inside UE2 container:

```bash
ip netns exec ue2 ip a
ip netns exec ue2 ip route
ip netns exec ue2 ping -c3 10.41.0.1
ip netns exec ue2 ping -c3 8.8.8.8
```

## Operational notes

- Keep gNB running while attaching/testing UEs.
- If gNB is restarted, restart UE processes.
- If bridge shows many `SYN-SENT` entries to unused UE IDs, set `UE_IDS` in `external_ue/host_ue_bridge/.env` (for example `UE_IDS=1,2`).

Troubleshooting:
- If UE stays at `Attaching UE...`, first verify bridge sessions with `ss -tnp` as above.
- If bridge is `ESTAB` but gNB log shows repeated lines like `Completed 0 of 23040 samples`, sample flow is not reaching gNB. Restart order should be:
  1. gNB/core already up
  2. restart bridge
  3. restart UE processes
- Use Open5GS logs as authoritative attach signal (`Registration complete` / PDU session events), not UE console text alone.
- UE process exit codes `137/143` usually indicate signal/termination during restarts, not a config parse error.

## Stop all components

```bash
cd /home/radr/tuilm/srsran-build/external_ue/host_ue1 && docker compose down
cd /home/radr/tuilm/srsran-build/external_ue/host_ue2 && docker compose down
cd /home/radr/tuilm/srsran-build/external_ue/host_ue_bridge && docker compose down
cd /home/radr/tuilm/srsran-build/srsRAN_Project/docker

docker compose -f docker-compose.yml -f docker-compose.external-ue-zmq.yml down
```
