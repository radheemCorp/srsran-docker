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
- setup n3br first time 
```bash
sudo ip link add n3br type bridge
sudo ip link set n3br up
sudo ip addr add 10.10.3.254/24 dev n3br
```
- bring up existing n3br and configure 
```bash
sudo ip link set n3br up
sudo ip addr del 10.10.3.1/24 dev n3br || true
sudo ip addr add 10.10.3.254/24 dev n3br

docker network create -d macvlan \
  --subnet=10.10.3.0/24 \
  --gateway=10.10.3.254 \
  -o parent=n3br \
  n3br
```

If `n3br` already exists, Docker will report it. That is fine.

Note:
- `host_ue1` and `host_ue2` are configured to use static IPs on this external network:
  - UE1 container: `10.10.3.234`
  - UE2 container: `10.10.3.235`
- Bridge uses `10.10.3.236` on `n3br`.

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

# commands 
- check logs for connectivity
```
docker compose -f docker-compose.open5g.yml -f docker-compose.external-ue-zmq.yml logs 5gc --no-color --tail=500 | grep -Ei "10\.53\.1\.3|10\.10\.3\.231|gnb|srsran|ngap" -n || true
```


```bash
docker compose logs -f 5gc
docker compose exec 5gc cat /open5gs/open5gs-5gc.yml
```

# check if ue is connected 
```bash
# Show subscriber file on host and inside container
cat project-config/subscriber_db.csv
docker compose exec -T 5gc cat /open5gs/subscriber_db.csv

# Follow core logs and grep for IMSI/registration/attach events
docker compose logs -f 5gc | grep --line-buffered -i -E '001010000000101|001010000000102|imsi|registration|attach'

# Follow gNB logs
docker compose logs -f gnb

```

08:54:30.277366 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406418484:1406426676, ack 39632, win 503, options [nop,nop,TS val 2454899230 ecr 1087482787], length 8192
08:54:30.277403 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1406426676, win 22716, options [nop,nop,TS val 1087482787 ecr 2454899230], length 0
08:54:30.277426 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406426676:1406490984, ack 39632, win 503, options [nop,nop,TS val 2454899230 ecr 1087482787], length 64308
08:54:30.277446 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406490984:1406555292, ack 39632, win 503, options [nop,nop,TS val 2454899230 ecr 1087482787], length 64308
08:54:30.277452 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1406490984, win 22273, options [nop,nop,TS val 1087482787 ecr 2454899230], length 0
08:54:30.277482 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406555292:1406619600, ack 39632, win 503, options [nop,nop,TS val 2454899230 ecr 1087482787], length 64308
08:54:30.277484 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1406555292, win 22716, options [nop,nop,TS val 1087482787 ecr 2454899230], length 0
08:54:30.277495 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1406619600, win 22716, options [nop,nop,TS val 1087482787 ecr 2454899230], length 0
08:54:30.277506 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406619600:1406683908, ack 39632, win 503, options [nop,nop,TS val 2454899230 ecr 1087482787], length 64308
08:54:30.277536 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406683908:1406748216, ack 39632, win 503, options [nop,nop,TS val 2454899230 ecr 1087482787], length 64308
08:54:30.277550 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406748216:1406787135, ack 39632, win 503, options [nop,nop,TS val 2454899230 ecr 1087482787], length 38919
08:54:30.277621 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1406787135, win 22716, options [nop,nop,TS val 1087482787 ecr 2454899230], length 0
08:54:30.279419 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [P.], seq 39632:39640, ack 1406787135, win 22716, options [nop,nop,TS val 1087482789 ecr 2454899230], length 8
08:54:30.279625 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406787135:1406795327, ack 39640, win 503, options [nop,nop,TS val 2454899232 ecr 1087482789], length 8192
08:54:30.279648 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1406795327, win 22716, options [nop,nop,TS val 1087482789 ecr 2454899232], length 0
08:54:30.279740 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406795327:1406859635, ack 39640, win 503, options [nop,nop,TS val 2454899233 ecr 1087482789], length 64308
08:54:30.279760 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406859635:1406923943, ack 39640, win 503, options [nop,nop,TS val 2454899233 ecr 1087482789], length 64308
08:54:30.279782 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406923943:1406988251, ack 39640, win 503, options [nop,nop,TS val 2454899233 ecr 1087482789], length 64308
08:54:30.279785 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1406923943, win 22716, options [nop,nop,TS val 1087482790 ecr 2454899233], length 0
08:54:30.279799 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1406988251:1407052559, ack 39640, win 503, options [nop,nop,TS val 2454899233 ecr 1087482789], length 64308
08:54:30.279816 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407052559:1407116867, ack 39640, win 503, options [nop,nop,TS val 2454899233 ecr 1087482789], length 64308
08:54:30.279827 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407116867:1407155786, ack 39640, win 503, options [nop,nop,TS val 2454899233 ecr 1087482789], length 38919
08:54:30.279831 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1406988251, win 22214, options [nop,nop,TS val 1087482790 ecr 2454899233], length 0
08:54:30.279869 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1407155786, win 22716, options [nop,nop,TS val 1087482790 ecr 2454899233], length 0
08:54:30.283237 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [P.], seq 39640:39648, ack 1407155786, win 22716, options [nop,nop,TS val 1087482793 ecr 2454899233], length 8
08:54:30.283430 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407155786:1407163978, ack 39648, win 503, options [nop,nop,TS val 2454899236 ecr 1087482793], length 8192
08:54:30.283447 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1407163978, win 22716, options [nop,nop,TS val 1087482793 ecr 2454899236], length 0
08:54:30.283495 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407163978:1407228286, ack 39648, win 503, options [nop,nop,TS val 2454899236 ecr 1087482793], length 64308
08:54:30.283513 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407228286:1407292594, ack 39648, win 503, options [nop,nop,TS val 2454899236 ecr 1087482793], length 64308
08:54:30.283532 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407292594:1407356902, ack 39648, win 503, options [nop,nop,TS val 2454899236 ecr 1087482793], length 64308
08:54:30.283556 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407356902:1407421210, ack 39648, win 503, options [nop,nop,TS val 2454899236 ecr 1087482793], length 64308
08:54:30.283576 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407421210:1407485518, ack 39648, win 503, options [nop,nop,TS val 2454899236 ecr 1087482793], length 64308
08:54:30.283591 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407485518:1407524437, ack 39648, win 503, options [nop,nop,TS val 2454899236 ecr 1087482793], length 38919
08:54:30.283661 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1407524437, win 22716, options [nop,nop,TS val 1087482794 ecr 2454899236], length 0
08:54:30.287357 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [P.], seq 39648:39656, ack 1407524437, win 22716, options [nop,nop,TS val 1087482797 ecr 2454899236], length 8
08:54:30.287511 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407524437:1407532629, ack 39656, win 503, options [nop,nop,TS val 2454899240 ecr 1087482797], length 8192
08:54:30.287537 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1407532629, win 22716, options [nop,nop,TS val 1087482797 ecr 2454899240], length 0
08:54:30.287669 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407532629:1407596937, ack 39656, win 503, options [nop,nop,TS val 2454899241 ecr 1087482797], length 64308
08:54:30.287706 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407596937:1407661245, ack 39656, win 503, options [nop,nop,TS val 2454899241 ecr 1087482797], length 64308
08:54:30.287724 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407661245:1407725553, ack 39656, win 503, options [nop,nop,TS val 2454899241 ecr 1087482797], length 64308
08:54:30.287740 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407725553:1407789861, ack 39656, win 503, options [nop,nop,TS val 2454899241 ecr 1087482797], length 64308
08:54:30.287757 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407789861:1407854169, ack 39656, win 503, options [nop,nop,TS val 2454899241 ecr 1087482797], length 64308
08:54:30.287767 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407854169:1407893088, ack 39656, win 503, options [nop,nop,TS val 2454899241 ecr 1087482797], length 38919
08:54:30.288062 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1407893088, win 22716, options [nop,nop,TS val 1087482798 ecr 2454899241], length 0
08:54:30.291206 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [P.], seq 39656:39664, ack 1407893088, win 22716, options [nop,nop,TS val 1087482801 ecr 2454899241], length 8
08:54:30.291536 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407893088:1407901280, ack 39664, win 503, options [nop,nop,TS val 2454899244 ecr 1087482801], length 8192
08:54:30.291606 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1407901280, win 22716, options [nop,nop,TS val 1087482801 ecr 2454899244], length 0
08:54:30.291682 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407901280:1407965588, ack 39664, win 503, options [nop,nop,TS val 2454899245 ecr 1087482801], length 64308
08:54:30.291722 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1407965588:1408029896, ack 39664, win 503, options [nop,nop,TS val 2454899245 ecr 1087482801], length 64308
08:54:30.291757 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408029896:1408094204, ack 39664, win 503, options [nop,nop,TS val 2454899245 ecr 1087482801], length 64308
08:54:30.291792 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408094204:1408158512, ack 39664, win 503, options [nop,nop,TS val 2454899245 ecr 1087482801], length 64308
08:54:30.291826 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408158512:1408222820, ack 39664, win 503, options [nop,nop,TS val 2454899245 ecr 1087482801], length 64308
08:54:30.291847 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408222820:1408261739, ack 39664, win 503, options [nop,nop,TS val 2454899245 ecr 1087482801], length 38919
08:54:30.291868 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1408261739, win 20224, options [nop,nop,TS val 1087482802 ecr 2454899245], length 0
08:54:30.294705 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [P.], seq 39664:39672, ack 1408261739, win 22716, options [nop,nop,TS val 1087482805 ecr 2454899245], length 8
08:54:30.294927 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408261739:1408269931, ack 39672, win 503, options [nop,nop,TS val 2454899248 ecr 1087482805], length 8192
08:54:30.294948 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1408269931, win 22716, options [nop,nop,TS val 1087482805 ecr 2454899248], length 0
08:54:30.294970 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408269931:1408334239, ack 39672, win 503, options [nop,nop,TS val 2454899248 ecr 1087482805], length 64308
08:54:30.294990 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408334239:1408398547, ack 39672, win 503, options [nop,nop,TS val 2454899248 ecr 1087482805], length 64308
08:54:30.295009 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408398547:1408462855, ack 39672, win 503, options [nop,nop,TS val 2454899248 ecr 1087482805], length 64308
08:54:30.295028 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408462855:1408527163, ack 39672, win 503, options [nop,nop,TS val 2454899248 ecr 1087482805], length 64308
08:54:30.295047 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408527163:1408591471, ack 39672, win 503, options [nop,nop,TS val 2454899248 ecr 1087482805], length 64308
08:54:30.295058 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408591471:1408630390, ack 39672, win 503, options [nop,nop,TS val 2454899248 ecr 1087482805], length 38919
08:54:30.298317 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [P.], seq 39672:39680, ack 1408630390, win 22716, options [nop,nop,TS val 1087482808 ecr 2454899248], length 8
08:54:30.298560 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408630390:1408638582, ack 39680, win 503, options [nop,nop,TS val 2454899251 ecr 1087482808], length 8192
08:54:30.298581 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1408638582, win 22716, options [nop,nop,TS val 1087482808 ecr 2454899251], length 0
08:54:30.298655 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408638582:1408702890, ack 39680, win 503, options [nop,nop,TS val 2454899252 ecr 1087482808], length 64308
08:54:30.298690 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408702890:1408767198, ack 39680, win 503, options [nop,nop,TS val 2454899252 ecr 1087482808], length 64308
08:54:30.298704 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408767198:1408831506, ack 39680, win 503, options [nop,nop,TS val 2454899252 ecr 1087482808], length 64308
08:54:30.298718 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408831506:1408895814, ack 39680, win 503, options [nop,nop,TS val 2454899252 ecr 1087482808], length 64308
08:54:30.298720 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1408767198, win 22329, options [nop,nop,TS val 1087482809 ecr 2454899252], length 0
08:54:30.298732 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408895814:1408960122, ack 39680, win 503, options [nop,nop,TS val 2454899252 ecr 1087482808], length 64308
08:54:30.298741 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408960122:1408999041, ack 39680, win 503, options [nop,nop,TS val 2454899252 ecr 1087482808], length 38919
08:54:30.298760 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1408960122, win 22505, options [nop,nop,TS val 1087482809 ecr 2454899252], length 0
08:54:30.298807 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1408999041, win 22716, options [nop,nop,TS val 1087482809 ecr 2454899252], length 0
08:54:30.302325 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [P.], seq 39680:39688, ack 1408999041, win 22716, options [nop,nop,TS val 1087482812 ecr 2454899252], length 8
08:54:30.302523 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1408999041:1409007233, ack 39688, win 503, options [nop,nop,TS val 2454899255 ecr 1087482812], length 8192
08:54:30.302532 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1409007233, win 22716, options [nop,nop,TS val 1087482812 ecr 2454899255], length 0
08:54:30.302560 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1409007233:1409071541, ack 39688, win 503, options [nop,nop,TS val 2454899255 ecr 1087482812], length 64308
08:54:30.302595 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1409071541:1409135849, ack 39688, win 503, options [nop,nop,TS val 2454899255 ecr 1087482812], length 64308
08:54:30.302613 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1409135849:1409200157, ack 39688, win 503, options [nop,nop,TS val 2454899255 ecr 1087482812], length 64308
08:54:30.302636 IP 53c74a269ac2.59764 > srsran_gnb.n3br.cisco-sccp: Flags [.], ack 1409200157, win 21386, options [nop,nop,TS val 1087482812 ecr 2454899255], length 0
08:54:30.302647 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flags [P.], seq 1409200157:1409264465, ack 39688, win 503, options [nop,nop,TS val 2454899255 ecr 1087482812], length 64308
08:54:30.302666 IP srsran_gnb.n3br.cisco-sccp > 53c74a269ac2.59764: Flag