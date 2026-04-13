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

## Image build configuration in this repo

This repo builds two runtime images for this flow:

1. gNB image
- Source Dockerfile: `srsRAN_Project/docker/Dockerfile`
- Compose service: `gnb` in `srsRAN_Project/docker/docker-compose.yml`
- Override/build profile: `srsRAN_Project/docker/docker-compose.external-ue-zmq.yml`

Current build intent for external UE + bridge flow:
- `ENABLE_ZEROMQ=On`
- `ENABLE_UHD=On`
- `ENABLE_EXPORT=On`
- `ENABLE_MKL=False`
- `ENABLE_DPDK=Off` (override build arg)

Runtime notes:
- Dockerfile installs runtime libraries needed by this branch (including ZMQ + DPDK-linked dependencies required by the built binary).
- gNB runs with config `configs/gnb_zmq_external_ue.yml` and uses ZMQ endpoints:
  - `tx_port=tcp://10.10.3.231:2000`
  - `rx_port=tcp://10.10.3.236:2001`

2. Open5GS 5GC image
- Source Dockerfile context: `srsRAN_Project/docker/open5gs`
- Compose service: `5gc` in `srsRAN_Project/docker/docker-compose.yml`

Published image tags from this repo state:
- `rptestbed/srsran-gnb:2026.04.13-zmq-uhd-extue`
- `rptestbed/open5gs-5gc:2026.04.13-open5gs-v2.7.0`

## How to use these images

### Option A: Build locally from repo (default)

```bash
cd /home/radr/tuilm/srsran-build/srsRAN_Project/docker
docker compose -f docker-compose.yml -f docker-compose.external-ue-zmq.yml build gnb
docker compose -f docker-compose.yml -f docker-compose.external-ue-zmq.yml up -d 5gc gnb
```

### Option B: Use pushed `rptestbed/*` images directly

Pull images:

```bash
docker pull rptestbed/srsran-gnb:2026.04.13-zmq-uhd-extue
docker pull rptestbed/open5gs-5gc:2026.04.13-open5gs-v2.7.0
```

Then set images in compose before `up` (example with env vars):

```bash
export GNB_IMAGE=rptestbed/srsran-gnb:2026.04.13-zmq-uhd-extue
export OPEN5GS_IMAGE=rptestbed/open5gs-5gc:2026.04.13-open5gs-v2.7.0
```

If you want compose to consume these variables directly, add image substitutions in your compose files (recommended for reproducibility):
- gNB service image: `${GNB_IMAGE:-srsran/gnb}`
- 5gc service image: `${OPEN5GS_IMAGE:-docker-5gc}`

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
