# Runbook — 2 gNB / 2 slice / 2 UEs-per-slice (ZMQ)

Deploy two single-cell gNBs sharing one 5GC + RIC, each offering a different
network slice, with two UEs camped on each slice, plus per-UE traffic export and
per-gNB KPM monitoring.

- **Branch:** `approach-a-two-cell-slicing`
- **Design notes:** [../multi_ue/README.md](../multi_ue/README.md), [../SETUP.md](../SETUP.md) §9.5
- **Scope:** ZMQ (virtual RF), `DEPLOY_TYPE=zmq`. No SDR hardware.

## Topology

| | Cell 1 (`gnb`) | Cell 2 (`gnb2`) |
|---|---|---|
| gNB id / PCI | 1 / 1 | 2 / 2 |
| `dl_arfcn` (band 3) | 368500 | 368500 (same; ZMQ wires are isolated) |
| Slice | `sst:1` | `sst:2` |
| N3 / N2 IP | 10.10.3.231 / 10.53.1.3 | 10.10.3.232 / 10.53.1.4 |
| metrics / E2-bind | 172.19.1.3 / 10.0.2.25 | 172.19.1.7 / 10.0.2.26 |
| ZMQ gNB tx / rx | 10.10.3.231:2000 / 10.10.4.237:2001 | 10.10.3.232:2010 / 10.10.4.237:2011 |
| UEs (IMSI) | UE1 …001, UE2 …002 | UE3 …003, UE4 …004 |
| UE IP | 10.45.0.2, 10.45.0.3 | 10.45.0.5, 10.45.0.6 |
| UE ZMQ ul/dl ports | 2101/2201, 2102/2202 | 2103/2203, 2104/2204 |
| DU E2 node id | `gnbd_001_001_000001_0` | `gnbd_001_001_000002_0` |

All four UEs run in **one** `multi_ue` container at `10.10.4.237`; two co-located
bridges (`bridge_cell1`, `bridge_cell2`) split them across the two gNBs
(`CELL2_UES=3,4` in `multi_ue/.env`).

## Prerequisites

```bash
cd ~/pers/srsran-docker
git checkout approach-a-two-cell-slicing
# Images already built/pulled: gnb, open5gs, srsran/grafana, srsran/telegraf,
# influxdb, srsue, and the ric-plt-* images. Verify:
docker images | grep -E "gnb|open5gs|grafana|influxdb|srsue|ric-plt"
# Build the grafana image once so dashboards (Multi-UE Traffic, xApp KPM) exist:
docker compose -f srsRAN_Project/docker/docker-compose.ui.yml build grafana
```

## Deploy

Run the components **one at a time, in order**. `manage.sh start gnb` brings up
`5gc + gnb + gnb2`; `start ric` self-heals the e2mgr/Redis race (see Known issues).

```bash
# 1. Host + docker networks (needs sudo for host macvlan/NAT). Idempotent.
sudo ./scripts/net_manage.sh init

# 2. RIC (fresh; auto-heals e2mgr + e2term)
./scripts/manage.sh start ric

# 3. gNB1 + gNB2 + 5GC. Wait until both gNBs log "Cell was activated".
./scripts/manage.sh start gnb
sleep 15

# 4. Provision the slice-2 UEs (UE3/UE4 -> sst:2). Re-run after ANY gnb cycle,
#    since the 5GC mongo is in-container and ephemeral.
./scripts/open5gs_add_ue.sh --csv srsRAN_Project/gnb-zmq/project-config/subscriber_db_slice2.csv

# 5. Monitoring (InfluxDB + Grafana + Telegraf)
./scripts/manage.sh start monitoring

# 6. The 4 UEs in one container (NUM_UES=4, CELL2_UES=3,4)
./scripts/manage.sh start multi_ue
sleep 50   # staggered attach of 4 UEs across 2 cells
```

## Verify

```bash
# UEs attached (each gets a 10.45.0.x IP):
for n in 1 2 3 4; do
  echo -n "UE$n: "; docker exec multi_ue sh -c "grep -aE 'PDU Session' /tmp/ue$n.log | tail -1"
done

# Slices (UE1/2 -> SST:1, UE3/4 -> SST:2):
docker logs open5gs_5gc 2>&1 | grep -aE "S_NSSAI" | tail -4

# Cell assignment (each gNB serves its 2 UEs; RNTIs 0x4601/0x4602 per gNB):
docker exec srsran_gnb  sh -c 'grep -ao "rnti=0x46[0-9a-f]*" /tmp/gnb.log | sort -u'
docker exec srsran_gnb2 sh -c 'grep -ao "rnti=0x46[0-9a-f]*" /tmp/gnb.log | sort -u'

# Data plane:
docker exec multi_ue ip netns exec ue1 ping -c2 10.45.0.1   # cell1 UE
docker exec multi_ue ip netns exec ue3 ping -c2 10.45.0.1   # cell2 UE

# E2 healthy on both gNBs (DU registered as gnbd_):
docker exec ric_dbaas redis-cli keys '*RAN:gnbd*'
for c in srsran_gnb srsran_gnb2; do
  echo -n "$c E2-DU setups: "; docker exec $c sh -c 'grep -acE "E2-DU.*E2 Setup procedure successful" /tmp/gnb.log'
done
```

## Generate traffic

iperf3 servers live in the `open5gs_5gc` container on the UE gateway `10.45.0.1`.
One server per UE (a single `iperf3 -s` serves one test at a time).

```bash
for p in 5201 5202 5203 5204; do docker exec -d open5gs_5gc iperf3 -s -p $p; done

# Bounded UDP on all 4 UEs (avoid unlimited TCP: --file-client can cause RLF).
# Let a run FINISH before starting another — overlapping/back-to-back runs can
# wedge a UE's RLC (see "RLC DRB wedge" under Known issues).
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

## KPM xApp (per gNB)

KPM (`DRB.UEThpDl/Ul`) comes from the **DU** node `gnbd_001_001_00000N_0`.
Run the xApp **sequentially per gNB** (the RIC's static routing only delivers
indications to the default RMR port, so two concurrent xApps don't both work).

```bash
cd oran-sc-ric
# gNB1
docker compose exec python_xapp_runner ./kpm_mon_xapp.py \
  --e2_node_id gnbd_001_001_000001_0 --kpm_report_style 1 --metrics DRB.UEThpDl,DRB.UEThpUl
# gNB2 (Ctrl-C the first, then run this)
docker compose exec python_xapp_runner ./kpm_mon_xapp.py \
  --e2_node_id gnbd_001_001_000002_0 --kpm_report_style 1 --metrics DRB.UEThpDl,DRB.UEThpUl
```

The `--video-client` traffic flows **uplink** (UE → server), so under load expect a
high `DRB.UEThpUl` (~3000 kbps) and a near-zero `DRB.UEThpDl` — that is correct, not
a fault. A `DRB.UEThpUl` of `0` while traffic is supposedly running almost always
means that cell's UEs are not actually passing data (see "RLC DRB wedge").

**Killing the xApp between gNBs (non-TTY runs).** Ctrl-C works at a real terminal,
but if you launched the xApp detached/scripted, stopping the host-side
`docker compose exec` does **not** kill the `kpm_mon_xapp.py` inside
`python_xapp_runner`. The next gNB's xApp then dies with
`OSError: [Errno 98] Address already in use`. The container has no `ps`/`kill`/`pkill`
binaries — kill it via `/proc` + the shell builtin `kill`:
```bash
docker exec python_xapp_runner sh -c '
  for d in /proc/[0-9]*; do
    tr "\0" " " < "$d/cmdline" 2>/dev/null | grep -q kpm_mon_xapp \
      && kill -9 "$(basename "$d")"
  done'
```

KPM data refreshes slowly under real-time ZMQ (~every 10–15 s), so indications
are sparse — leave each xApp running a while. Verify in InfluxDB (note the dots
in field names are sanitized to underscores):

```bash
docker exec influxdb sh -c "curl -s -G 'http://localhost:8081/api/v3/query_sql' \
  --data-urlencode 'db=srsran' \
  --data-urlencode 'q=SELECT e2_node_id, count(*) AS n, round(max(\"DRB_UEThpUl\"),1) AS max_ul_kbps FROM kpm GROUP BY e2_node_id ORDER BY e2_node_id'"
```

Grafana → **xApp KPM** dashboard (per-`e2_node_id`).

## Teardown

```bash
docker compose -f multi_ue/docker-compose.yaml down
./scripts/manage.sh stop monitoring
./scripts/manage.sh stop gnb        # stops 5gc + gnb + gnb2
./scripts/manage.sh stop ric
# Networks (optional): sudo ./scripts/net_manage.sh remove
```

## Known issues & gotchas

- **srsRAN metrics dashboards only show cell 1 (monitoring is single-gNB).** The
  telegraf `ws_adapter.py` connects to exactly **one** websocket, `WS_URL` in
  `srsRAN_Project/docker/.env` (default `172.19.1.3:8001` = gNB1's metrics IP). gNB2
  (`172.19.1.7:8001`) exposes an identical websocket (`enable_json: true` in both
  `gnb_compose_config*.yml`) but **nothing scrapes it**, so its metrics never reach
  InfluxDB. Consequences for Grafana:
  - The **pci-based srsRAN dashboards** (home / "Cells with Active UEs", "srsRAN
    Metrics", CU-CP, RRC, NGAP) only ever see `pci=1`. The home panel computes
    `COUNT(DISTINCT pci)` from the `ue` measurement, so **"Cells with Active UEs"
    reads 1 even though both cells are up and serving UEs** — it is a monitoring
    blind spot, not a RAN fault.
  - Two-cell visibility comes from the dashboards fed by other pipelines: **xApp
    KPM** (per `e2_node_id`, both `gnbd_…000001_0` and `…000002_0`) and **Multi-UE
    Traffic** (per `ue_id`, all 4 UEs). Trust those for per-cell/per-UE state.
  - To actually ingest gNB2, run a second telegraf/`ws_adapter` instance with
    `WS_URL=172.19.1.7:8001` (and tag its rows so the `ue` measurement carries both
    PCIs). Not wired up by default.

- **RLC DRB wedge (cell goes silent, KPM throughput = 0).** Overlapping or
  back-to-back traffic runs (starting a new `run_scenario.sh` before the previous
  one ends) can corrupt a UE's RLC state. Symptoms: `ue<N>.log` spams
  `DRB1: buffer state - retx - invalid length=-NNN` and `Current SO larger or equal
  to SDU size`, the UE stops passing data (ping = 100% loss), and that gNB's
  `DRB.UEThpUl` KPM reads 0 even though the gNB is still scheduling its RNTIs. The
  radio link (PHY/MAC) is fine — only the DRB is wedged. Recover by re-attaching the
  UEs (recreate `multi_ue`); if the gNB ZMQ also wedged, use the full recovery
  below. **Prevention:** let one traffic run finish before starting the next.

- **RIC holds stale E2 state across a gNB recreate → E2 Setup Failure.** If you
  force-recreate the gNBs while the RIC is already up, E2 setup can fail —
  `gnb.log` shows `E2AP msg, "unsuccessfulOutcome.E2setupFailure"` /
  `E2 Setup procedure failed` — because e2mgr still has the previous DU
  registrations in Redis (`{e2Manager},RAN:gnbd_*`). The `gnbd_*` keys then look
  "registered" but no live E2 path exists. Fix: restart the RIC **clean** so Redis
  is empty, then recreate the gNBs (RIC must be healthy *before* gNB E2 setup — see
  the segfault note below):
  ```bash
  ./scripts/manage.sh stop ric && ./scripts/manage.sh start ric
  docker exec ric_dbaas redis-cli keys '*RAN:gnbd*'   # should be empty now
  docker compose -f srsRAN_Project/gnb-zmq/docker-compose.yml \
    up -d --force-recreate --no-deps gnb gnb2
  # wait for both: grep -ac "E2-DU.*E2 Setup procedure successful" /tmp/gnb.log == 1
  ```

- **RIC e2mgr/Redis startup race (auto-healed).** `e2mgr` retries Redis only
  3×/30 ms then exits; if it does, `e2term` can't route E2 (`RMR_ERR_NOENDPT`)
  and gNB E2 setup **segfaults the gNB**. `manage.sh start ric` runs `_ric_heal`
  (restarts e2mgr if down, then e2term); the compose also has `restart:
  on-failure` on e2mgr. If you start the RIC by hand (`cd oran-sc-ric && docker
  compose up -d`), run the heal yourself: `docker start ric_e2mgr; sleep 4;
  docker restart ric_e2term`.

- **ZMQ lockstep — clean restart order.** srsRAN ZMQ needs the gNB and UEs to
  start their sample exchange in lockstep. After an **unclean** teardown a gNB's
  ZMQ can wedge (`gnb.log` shows `Completed 0 of 23040 samples`); a plain
  `docker restart` does **not** clear it. Recover with:
  ```bash
  docker compose -f multi_ue/docker-compose.yaml down
  docker compose -f srsRAN_Project/gnb-zmq/docker-compose.yml up -d --force-recreate --no-deps gnb gnb2
  # wait until both gNBs are "Waiting for request", then:
  ./scripts/open5gs_add_ue.sh --csv srsRAN_Project/gnb-zmq/project-config/subscriber_db_slice2.csv
  ./scripts/manage.sh start multi_ue
  ```
  After the gNB recreate, confirm E2 actually re-established
  (`grep -ac "E2-DU.*E2 Setup procedure successful" /tmp/gnb.log` == 1 on each). If
  it shows `E2 Setup procedure failed` instead, the RIC is holding stale E2 state —
  see "RIC holds stale E2 state across a gNB recreate" above.

- **`e2sm_ccc` must be OFF for KPM.** With `e2sm_ccc_enabled: true` the srsRAN DU
  never completes E2 setup (stops after adding CCC RAN function id 4), so no
  `gnbd_` node appears and KPM subscriptions fall to the CU-CP (which rejects
  them). Both gNB configs ship with `e2sm_ccc_enabled: false`.

- **~2 UEs per cell.** The co-located bridge **sums** all UE uplinks, so (a)
  every srsUE must be running for the summed uplink to flow — don't space UE
  starts far apart (the short `START_STAGGER` is deliberate; do NOT attach
  sequentially), and (b) >~2 UEs attaching on one cell contend on PRACH. Two
  cells × 2 UEs stays under that limit.

- **iperf3 servers die with the gNB.** `manage.sh stop gnb` also stops
  `open5gs_5gc`, killing the iperf3 servers — restart them after any gNB cycle.

- **Concurrent xApps.** Two xApp instances need distinct
  `--http_server_port`/`--rmr_port`, but the RIC's static `routes.rtg` only
  delivers indications to the default RMR port. Run per-gNB xApps **sequentially**
  (or extend the routing table) for now.

## Reference

- IMSIs / IPs: `srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv`
  (sst:1) + `subscriber_db_slice2.csv` (UE3/4 -> sst:2).
- gNB configs: `gnb_zmq.yml` (cell 1), `gnb_zmq_cell2.yml` (cell 2),
  `gnb_compose_config_cell2.yml`.
- multi_ue knobs: `multi_ue/.env` (`NUM_UES`, `CELL2_UES`, `GNB2_IP`,
  `GNB2_TX_PORT/RX`), orchestrator `multi_ue/config/start_all.sh`.
- Live DU node ids: `docker exec ric_dbaas redis-cli keys '*RAN:gnbd*'`.
