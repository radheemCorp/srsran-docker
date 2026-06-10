# Runbook — Single-Cell Multi-UE (ZMQ)

Deploy a single-cell gNB with one 5GC, with multiple UEs camped on it, plus per-UE traffic export.

- **Branch:** `zmq_single_cell`
- **Design notes:** [../multi_ue/README.md](../multi_ue/README.md)
- **Scope:** ZMQ (virtual RF), `DEPLOY_TYPE=zmq`. No SDR hardware.

## Topology

| | Cell 1 (`gnb`) |
|---|---|
| gNB id / PCI | 1 / 1 |
| `dl_arfcn` (band 3) | 368500 |
| Slice | `sst:1` |
| N3 / N2 IP | 10.10.3.231 / 10.53.1.3 |
| metrics | 172.19.1.3 |
| ZMQ gNB tx / rx | 10.10.3.231:2000 / 10.10.4.237:2001 |
| UEs (IMSI) | UE1 …001, UE2 …002, UE3 …003, UE4 …004 |
| UE IP | 10.45.0.2, 10.45.0.3, 10.45.0.5, 10.45.0.6 |
| UE ZMQ ul/dl ports | 2101/2201, 2102/2202, 2103/2203, 2104/2204 |

All UEs run in **one** `multi_ue` container at `10.10.4.237`. A single co-located bridge connects all of them to the gNB.

## Prerequisites

```bash
cd ~/pers/srsran-docker
git checkout zmq_single_cell
# Images already built/pulled: gnb, open5gs, srsran/grafana, srsran/telegraf,
# influxdb, srsue. Verify:
docker images | grep -E "gnb|open5gs|grafana|influxdb|srsue"
# Build the grafana image once so dashboards (Multi-UE Traffic) exist:
docker compose -f srsRAN_Project/docker/docker-compose.ui.yml build grafana
```

## Deploy

Run the components **one at a time, in order**.

```bash
# 1. Host + docker networks (needs sudo for host macvlan/NAT). Idempotent.
sudo ./scripts/net_manage.sh init

# 2. gNB + 5GC. Wait until the gNB logs "Cell was activated".
./scripts/manage.sh start gnb
sleep 15

# 3. Monitoring (InfluxDB + Grafana + Telegraf)
./scripts/manage.sh start monitoring

# 4. The 4 UEs in one container (NUM_UES=4)
./scripts/manage.sh start multi_ue
sleep 50   # staggered attach of 4 UEs
```

## Verify

```bash
# UEs attached (each gets a 10.45.0.x IP):
for n in 1 2 3 4; do
  echo -n "UE$n: "; docker exec multi_ue sh -c "grep -aE 'PDU Session' /tmp/ue$n.log | tail -1"
done

# Cell assignment (gNB serves its UEs; RNTIs 0x4601/0x4602/etc):
docker exec srsran_gnb  sh -c 'grep -ao "rnti=0x46[0-9a-f]*" /tmp/gnb.log | sort -u'

# Data plane:
docker exec multi_ue ip netns exec ue1 ping -c2 10.45.0.1
```

## Generate traffic

iperf3 servers live in the `open5gs_5gc` container on the UE gateway `10.45.0.1`.
One server per UE (a single `iperf3 -s` serves one test at a time).

```bash
for p in 5201 5202 5203 5204; do docker exec -d open5gs_5gc iperf3 -s -p $p; done

# Bounded UDP on all 4 UEs (avoid unlimited TCP: --file-client can cause RLF).
# Let a run FINISH before starting another — overlapping/back-to-back runs can
# wedge a UE's RLC.
for n in 1 2 3 4; do
  docker exec -d multi_ue /srsran/config/run_scenario.sh \
    --video-client --bitrate 2M --server-ip 10.45.0.1 --port $((5200+n)) --ue $n --duration 120
done

# Per-UE throughput/latency in InfluxDB (measurement ue_traffic / ue_latency):
docker exec influxdb sh -c "curl -s -G 'http://localhost:8081/api/v3/query_sql' \
  --data-urlencode 'db=srsran' \
  --data-urlencode 'q=SELECT ue_id, count(*) AS n, round(max(throughput_mbps),3) AS max_mbps FROM ue_traffic GROUP BY ue_id ORDER BY ue_id'"
```

Grafana (http://localhost:3300) → **Multi-UE Traffic** dashboard.

## Teardown

```bash
docker compose -f multi_ue/docker-compose.yaml down
./scripts/manage.sh stop monitoring
./scripts/manage.sh stop gnb        # stops 5gc + gnb
# Networks (optional): sudo ./scripts/net_manage.sh remove
```

## Known issues & gotchas

- **RLC DRB wedge (cell goes silent).** Overlapping or
  back-to-back traffic runs (starting a new `run_scenario.sh` before the previous
  one ends) can corrupt a UE's RLC state. Symptoms: `ue<N>.log` spams
  `DRB1: buffer state - retx - invalid length=-NNN` and `Current SO larger or equal
  to SDU size`, the UE stops passing data (ping = 100% loss). Recover by re-attaching the
  UEs (recreate `multi_ue`); if the gNB ZMQ also wedged, use the full recovery
  below. **Prevention:** let one traffic run finish before starting the next.

- **ZMQ lockstep — clean restart order.** srsRAN ZMQ needs the gNB and UEs to
  start their sample exchange in lockstep. After an **unclean** teardown a gNB's
  ZMQ can wedge (`gnb.log` shows `Completed 0 of 23040 samples`); a plain
  `docker restart` does **not** clear it. Recover with:
  ```bash
  docker compose -f multi_ue/docker-compose.yaml down
  ./scripts/manage.sh stop gnb
  ./scripts/manage.sh start gnb
  # wait until gNB is "Waiting for request", then:
  ./scripts/manage.sh start multi_ue
  ```

- **iperf3 servers die with the gNB.** `manage.sh stop gnb` also stops
  `open5gs_5gc`, killing the iperf3 servers — restart them after any gNB cycle.
