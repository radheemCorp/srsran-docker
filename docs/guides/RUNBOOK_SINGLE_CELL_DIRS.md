# Runbook — Single-Cell Multi-UE (ZMQ), directory-based + bidirectional traffic

Deploy one gNB + one 5GC (no RIC), attach UEs on a single cell, and run **low-load
bidirectional (UL+DL)** traffic with per-UE export to InfluxDB/Grafana.

- **Approach:** side-by-side directories (no dedicated git branch).
  - gNB/5GC: `srsRAN_Project/gnb-zmq-single-cell/`  (copy of `gnb-zmq`, one cell, **E2/RIC off**)
  - UEs:     `multi_ue-single-cell/`                (copy of `multi_ue`, single bridge, **`--bidir`**)
- **Scope:** ZMQ virtual RF, `DEPLOY_TYPE=zmq`. No SDR hardware, no oran-sc-ric RIC.
- **Supersedes** the branch-based [RUNBOOK_SINGLE_CELL.md](./RUNBOOK_SINGLE_CELL.md) for the
  directory layout.

## Topology

| | Cell 1 (`gnb`) |
|---|---|
| gNB id / PCI | 1 / 1 |
| `dl_arfcn` (band 3) / BW / SCS | 368500 / 20 MHz / 15 kHz |
| Slice | `sst:1` (all UEs) |
| N2 / N3 IP | 10.53.1.3 / 10.10.3.231 |
| metrics IP | 172.19.1.3 |
| ZMQ gNB tx / rx | 10.10.3.231:2000 / 10.10.4.237:2001 |
| UE bridge IP (ue_n3) | 10.10.4.237 (shared by all UEs, multiplexed by ZMQ port) |
| UEs (IMSI) | UE1 …001, UE2 …002 |
| UE IP | 10.45.0.2, 10.45.0.3 |
| UE ZMQ ul/dl ports | 2101/2201, 2102/2202 |

All UEs run in **one** `multi_ue` container at `10.10.4.237`; a **single** co-located
GNU Radio bridge sums their uplinks into the one gNB and fans the gNB downlink back out.

> **Why 2 UEs, not 4 — read before scaling up.** The bridge sums all UE uplinks with a
> single `add_vcc` block, and every srsUE here transmits PRACH **preamble 0**. With 2 UEs
> a msg3 collision resolves (capture effect → one attaches, then the other). With **4 UEs
> all four answer the same RAR and their msg3 collide every time** (`crc=KO`, 0 attaches).
> Keep `NUM_UES=2` for reliable attach on this bridge. Scaling past ~2 needs preamble
> diversity or per-UE power offset in the bridge (not implemented). See Known issues.

## Prerequisites

```bash
cd ~/pers/srsran-docker
# Images already built/pulled: gnb, open5gs, srsran/grafana, srsran/telegraf,
# influxdb, srsue. Verify:
docker images | grep -E "gnb|open5gs|grafana|influxdb|srsue"
# Grafana dashboards (Multi-UE Traffic) — build once if not present:
docker compose -f srsRAN_Project/docker/docker-compose.ui.yml build grafana
```

The single-cell stack uses the external host networks `n2`, `n3`, `metrics`, `ue_n3`
(created by `net_manage.sh init`). It does **not** need `oran-sc-ric` (no RIC).

## Deploy

`manage.sh` hardcodes the original `gnb-zmq` / `multi_ue` dirs, so launch the single-cell
dirs with `docker compose -f` directly. Bring components up **one at a time, in order**.

```bash
# 1. Host + docker networks (needs sudo for host macvlan/NAT). Idempotent.
sudo ./scripts/net_manage.sh init

# 2. gNB + 5GC (single cell, no RIC/E2). Wait for "Cell was activated".
docker compose -f srsRAN_Project/gnb-zmq-single-cell/docker-compose.yml up -d
#   wait: docker exec srsran_gnb sh -c 'grep -ac "Cell was activated" /tmp/gnb.log'  == 1

# 3. Monitoring (InfluxDB + Grafana + Telegraf). Scrapes the single cell at 172.19.1.3.
./scripts/manage.sh start monitoring

# 4. iperf3 servers on the UE gateway (one per UE/port). They die with the 5GC,
#    so (re)start them after any gNB cycle.
for p in 5201 5202 5203 5204; do docker exec -d open5gs_5gc iperf3 -s -p $p; done

# 5. The UEs in one container (NUM_UES=2, single bridge).
docker compose -f multi_ue-single-cell/docker-compose.yaml up -d
sleep 30   # staggered attach
```

## Verify

```bash
# UEs attached (each gets a 10.45.0.x IP):
for n in 1 2; do
  echo -n "UE$n: "; docker exec multi_ue sh -c "ip netns exec ue$n ip -4 addr show tun_srsue 2>/dev/null | grep -oE 'inet 10\\.45\\.0\\.[0-9]+'"
done

# Only the single (cell1) bridge should exist:
docker exec multi_ue sh -c 'ls -1 /tmp/bridge_*.log'           # -> bridge_cell1.log only

# gNB serves both UEs (RNTIs 0x4601/0x4602; msg3 decoding):
docker exec srsran_gnb sh -c 'grep -ao "rnti=0x46[0-9a-f]*" /tmp/gnb.log | sort -u'
docker exec srsran_gnb sh -c 'grep -ac "crc=OK" /tmp/gnb.log'  # > 0

# Data plane: gateway + internet (DNS + ICMP) from each UE:
for n in 1 2; do
  docker exec multi_ue ip netns exec ue$n ping -c2 -W2 -I tun_srsue 10.45.0.1
  docker exec multi_ue ip netns exec ue$n ping -c3 -W3 -I tun_srsue google.com
done
```

Expected idle RTT ~80–200 ms (ZMQ virtual RF). 0% loss to both gateway and google.com.

## Generate bidirectional traffic (low load)

The `--bidir` flag (added to `multi_ue-single-cell/config/{run_scenario.sh,ue_export.py}`)
runs `iperf3 --bidir`, i.e. simultaneous **uplink + downlink** at `--bitrate` per direction.
`--reverse` (downlink only) is also available.

```bash
# Low-load bidirectional UDP on both UEs. START LOW: UDP does NOT back off, so a
# bitrate above the link's effective (CPU-limited) capacity floods the buffers,
# RTT explodes (seconds), and the RLC DRB wedges. Raise only as the host allows.
for n in 1 2; do
  docker exec -d multi_ue /srsran/config/run_scenario.sh \
    --video-client --bidir --bitrate 256k --server-ip 10.45.0.1 --port $((5200+n)) --ue $n --duration 120
done

# Per-UE throughput (UL+DL rows) + latency in InfluxDB:
docker exec influxdb sh -c "curl -s -G 'http://localhost:8081/api/v3/query_sql' \
  --data-urlencode 'db=srsran' \
  --data-urlencode 'q=SELECT ue_id, count(*) AS n, round(max(throughput_mbps),3) AS max_mbps FROM ue_traffic GROUP BY ue_id ORDER BY ue_id'"
```

Grafana (http://localhost:3300) → **Multi-UE Traffic** dashboard.

### 30-minute test (5-minute checkpoints)

`checkpoint_sc.sh` (repo root) drives one checkpoint: launch bidir on both UEs, ping
mid-stream + idle, sample `ue_traffic`/`ue_latency`, and flag RLC-wedge log lines.
Run it 6× spaced ~5 min apart (each call self-paces with a tail sleep):

```bash
# args: <label> <duration_s> <tail_sleep_s> <bitrate_per_dir>
./checkpoint_sc.sh "SC-1/6 (t=0m)"  120 165 256k
./checkpoint_sc.sh "SC-2/6 (t=5m)"  120 165 256k
# ... through SC-6/6 (t=25m)
```

Read each checkpoint's **idle** ping as the connectivity gate (mid-stream 100% loss is
load-induced bufferbloat, not a fault, *as long as* the idle ping recovers to 0%). A
genuine RLC wedge shows `UE<n>: WEDGE +N lines` and idle ping stays at 100%.

## Teardown

```bash
docker compose -f multi_ue-single-cell/docker-compose.yaml down
./scripts/manage.sh stop monitoring
docker compose -f srsRAN_Project/gnb-zmq-single-cell/docker-compose.yml down   # stops 5gc + gnb
# Networks (optional): sudo ./scripts/net_manage.sh remove
```

## Known issues & gotchas

- **~2 UEs per cell on the summed bridge (PRACH preamble-0 collision).** All srsUEs send
  PRACH `preamble_index=0`; the bridge sums uplinks equally. With 4 UEs every msg3
  collides (`crc=KO`, no attach); the gNB ZMQ then often stalls (`Completed 0 of 23040
  samples`). 2 UEs attach reliably. `NUM_UES=2` in `multi_ue-single-cell/.env`. To go
  higher you'd need per-UE preamble diversity or unequal per-UE gain in
  `multi_ue_scenario.py` (an `add_vcc` with per-input `multiply_const_cc`) so capture
  effect lets UEs attach in a rolling fashion — not implemented here.

- **Host real-time headroom is the binding constraint.** srsRAN ZMQ is hard real-time. On
  a CPU-starved host (observed: load ~16 on 8 cores; gNB alone ~237% CPU) even **1M
  bidir** floods the link → ping RTT ~18 s (bufferbloat) → RLC DRB wedge within ~2 min.
  256k was the safe-ish floor on that machine. On a better-provisioned host (isolated
  cores / lower baseline load) raise the bitrate; keep UDP well under effective capacity,
  or use TCP for a self-limiting stream. Watch `cat /proc/loadavg` and
  `docker exec srsran_gnb sh -c 'grep -c "Completed 0 of" /tmp/gnb.log'` (ZMQ underruns).

- **RLC DRB wedge.** Symptoms: `ue<N>.log` spams `DRB1: buffer state - retx - invalid
  length=-NNN` / `Current SO larger or equal to SDU size`; the UE stops passing data (ping
  100% loss even when idle). Recover by cycling the gNB + re-attaching the UEs (see ZMQ
  reattach). Prevention: keep the bitrate low; let one run finish before the next.

- **ZMQ reattach limitation.** A srsUE that has attached once cannot reattach on the same
  ZMQ ports — recover by cycling the gNB:
  ```bash
  docker compose -f multi_ue-single-cell/docker-compose.yaml down
  docker compose -f srsRAN_Project/gnb-zmq-single-cell/docker-compose.yml down
  docker compose -f srsRAN_Project/gnb-zmq-single-cell/docker-compose.yml up -d   # wait "Cell was activated"
  for p in 5201 5202 5203 5204; do docker exec -d open5gs_5gc iperf3 -s -p $p; done   # iperf3 dies with 5gc
  docker compose -f multi_ue-single-cell/docker-compose.yaml up -d
  ```

- **No RIC / E2 / KPM here.** `gnb_zmq.yml` has `e2.*`/`e2sm_*` disabled and the gNB is not
  attached to the `oran-sc-ric` network. The Grafana **xApp KPM** dashboard stays empty;
  use **Multi-UE Traffic** (fed by `ue_export.py`). To add KPM: re-enable E2 in
  `gnb_zmq.yml`, re-attach the `oran-sc-ric` network in the compose, and start the RIC.

- **Single-cell mode = empty `CELL2_UES`.** The copy's `start_all.sh` defaults
  `CELL2_UES="${CELL2_UES:-}"` (empty ⇒ one bridge, all UEs on cell 1). Note the original
  `multi_ue` used `${CELL2_UES:-3,4}`, where `:-` substitutes the default for an *empty*
  value too — so `CELL2_UES=` there still routes UE3/UE4 to a (nonexistent) cell-2 gNB.

- **iperf3 servers die with the gNB.** `... up -d` on the gNB compose restarts `open5gs_5gc`
  and kills the iperf3 servers — restart them after any gNB cycle.

## Files (this experiment)

- `srsRAN_Project/gnb-zmq-single-cell/` — `docker-compose.yml` (5gc + 1 gnb, no gnb2, no
  oran-sc-ric net), `project-config/gnb/gnb_zmq.yml` (PCI 1, sst 1, **E2 disabled**),
  `project-config/gnb/gnb_compose_config.yml`, `project-config/{open5gs*,subscriber_db.csv}`.
- `multi_ue-single-cell/` — `.env` (`NUM_UES=2`, `CELL2_UES=` empty),
  `config/start_all.sh` (single-cell default), `config/{run_scenario.sh,ue_export.py}`
  (`--bidir`/`--reverse`), `config/multi_ue_scenario.py` (single summed bridge).
- `checkpoint_sc.sh` — 30-min / 5-min bidirectional checkpoint driver.
