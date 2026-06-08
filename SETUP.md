# SETUP (Merged Guide)

This guide merges ZMQ and UHD setup with a shared flow and mode-specific steps.

## 1. Overview
Components: ORAN-SC RIC (optional), Open5GS 5GC, monitoring stack, and srsRAN gNB.

References:
- gNB/Open5GS docs: [srsRAN_Project/README.md](srsRAN_Project/README.md)
- ORAN RIC: [oran-sc-ric/README.md](oran-sc-ric/README.md)
- UHD device check: [docs/FIND_UHD_DEVICE.md](docs/FIND_UHD_DEVICE.md)
- Subscribers: [docs/subscribers.md](docs/subscribers.md)

## 2. Choose Your Mode
- **ZMQ (virtual RF)**: no SDR hardware, ideal for dev and xApps.
- **UHD (physical SDR)**: needs USRP B210/B200 and UHD drivers.

## 3. Build Images (Common)
```bash
cd srsRAN_Project/docker
docker compose build
```
Verify:
```bash
docker images | grep -E "srsran|open5gs"
```
If you used custom tags, update the `image:` values in the deploy compose files.

Optional: pull prebuilt images, if registry acess is available
- gNB: `rptestbed/gnb:20260507-dpdk`
- open5gs: `rptestbed/open5gs:20260507-dpdk`

## 4. Network Setup (Common)
Create all Docker + host networks:
```bash
./scripts/net_manage.sh init
```
Verify:
```bash
./scripts/net_manage.sh dnet
```
If mismatched, reset:
```bash
./scripts/net_manage.sh remove
./scripts/net_manage.sh init
```
Override subnets by env vars (see `scripts/net_manage.sh`).

## 5. Open5GS Core (Common)
### 5.1 Ensure config sync
Match MCC/MNC/TAC/SST/SD and AMF/UPF IPs across gNB and Open5GS.

### 5.2 Deploy 5GC
ZMQ:
```bash
cd srsRAN_Project/gnb-zmq
docker compose up -d 5gc
```
UHD:
```bash
cd srsRAN_Project/gnb-uhd
docker compose up -d 5gc
```

### 5.3 (ZMQ only) Subscriber IP subnet sync
Ensure `srsRAN_Project/gnb-zmq/project-config/open5gs.env` UE subnet matches `srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv` IPs.

## 6. ORAN-SC RIC (Optional)
Deploy RIC:
```bash
cd oran-sc-ric
docker compose up -d
```
Find the RIC IP (use in `e2.addr`):
```bash
cd oran-sc-ric
docker compose ps
```

If RIC is skipped, disable E2 in the gNB config.

## 7. gNB Configuration
### 7.1 Common config checklist
- MCC/MNC, TAC, SST/SD
- AMF and UPF IPs
- SCTP 38412, GTP-U 2152
- E2 enable/disable and `e2.addr` / `e2.bind_addr`

### 7.2 E2 and PCAP config

If RIC is enabled:
```yaml
pcap:
  mac_enable: false                 # Set to true to enable MAC-layer PCAPs.
  mac_filename: /tmp/gnb_mac.pcap   # Path where the MAC PCAP is stored.
  ngap_enable: false                # Set to true to enable NGAP PCAPs.
  ngap_filename: /tmp/gnb_ngap.pcap # Path where the NGAP PCAP is stored.
  e2ap_enable: true                 # Set to true to enable E2AP PCAPs.
  e2ap_du_filename: /tmp/gnb_du_e2ap.pcap       # Path where the DU E2AP PCAP is stored.
  e2ap_cu_cp_filename: /tmp/gnb_cu_cp_e2ap.pcap # Path where the CU-CP E2AP PCAP is stored.
  e2ap_cu_up_filename: /tmp/gnb_cu_up_e2ap.pcap # Path where the CU-UP E2AP PCAP is stored.


e2:
  enable_du_e2: true
  enable_cu_cp_e2: true
  enable_cu_up_e2: false
  addr: <ric-ip>
  bind_addr: <gnb-ip>
```

### 7.3 UHD gNB config
File: [srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml](srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml)

- before starting the gnb follow Section 9.2 below

UHD notes:
- `ru_sdr.device_driver: uhd`
- `ru_sdr.device_args: type=b200,serial=<serial>,num_recv_frames=64,num_send_frames=64`
- `srate: 23.04`

Find UHD device:
```bash
uhd_find_devices
```
Probe device:
```bash
uhd_usrp_probe --args "type=b200,serial=<serial>"
```
Enable Performance mode for the machine
```bash
cd srsRAN_Project
```
- if running on host machine 
```
./scripts/srsran_performance
```

- if running in VM, then execute the script above on the host and the following script in the vm
```
./scripts/vm_srsran_performance
```


- if host pc run
### 7.3 ZMQ gNB config
File: [srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml](srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml)

- Ensure the following:
- `ru_sdr.device_driver: zmq`
- `device_args: tx_port=tcp://10.10.3.231:2000,rx_port=tcp://10.10.4.237:2001,base_srate=23.04e6`
    - the tx_port IP should be the gNB side of the bridge (matches `bridge_tx_port` in the bridge config)
    - the rx_port IP should be the bridge side that receives from the UE (matches `bridge_rx_port` in the bridge config)
- `srate: 23.04`


## 8. Start gNB
ZMQ:
```bash
cd srsRAN_Project/gnb-zmq
docker compose up -d gnb
```
UHD:
```bash
cd srsRAN_Project/gnb-uhd
docker compose up -d gnb
```
Logs:
- ZMQ: `srsRAN_Project/gnb-zmq/gnb-storage/gnb.log`
- UHD: `srsRAN_Project/gnb-uhd/gnb-storage/gnb.log`

## 9. UE Setup
### 9.1 ZMQ UE (external UE containers)
Start bridge:
```bash
cd ue/bridge
docker compose up -d
```
Start UE1:
```bash
cd ue/ue1
docker compose up -d
docker compose exec -it srsran_ue_host /srsran/config/start_ue.sh 1
```
Start UE2:
```bash
cd ue/ue2
docker compose up -d
docker compose exec -it srsran_ue_host /srsran/config/start_ue.sh 2
```
Verify attach:
```bash
docker exec ue1 ip netns exec ue1 ip addr show tun_srsue
docker exec ue2 ip netns exec ue2 ip addr show tun_srsue
```

### 9.2 UHD UE (phone)

#### Configure UE in Open5GS
Sample Device info:
  - device name: POCO M4 Pro 5G
  - imsi: 001010000000101
  - sst: 0x111111
  - sd: 1
---
The following configuration steps are only required because the default value for sd is 0xffffff and the UE requests 0x111111 hence if not configured the ANF does not authorize the connection

Steps:
1. Goto [localhost:9999](http://localhost:9999/)
2. Enter credentials <br> 
  username: `admin` <br>
  password: `1423`
3. Select device `001010000000101`
4. Click on edit button in the top right corner of the popup 
5. look for Slice configuration section, click on the SD textbox, enter the configured slice (111111, in our case)
6. Now proced to deploy gnb 
7. Use your phone to select the test network after gNB is running. Confirm UE registers.

### 9.3 Multi-UE in one container (ZMQ) + traffic test

`multi_ue/` runs **N srsUEs in a single container** (shared IP, port-multiplexed,
co-located bridge) and exports per-UE traffic/latency to InfluxDB for Grafana.
It is **mutually exclusive with §9.1** — both claim `10.10.4.237` / the gNB
`rx_port`. See [multi_ue/README.md](multi_ue/README.md) for the design.

`NUM_UES` (in `multi_ue/.env`) is capped by the subscriber DB — 4 IMSIs by
default. Build the Grafana image once so the dashboard is present:
```bash
docker compose -f srsRAN_Project/docker/docker-compose.ui.yml build grafana
```

**1. Bring up the stack (one component per call), in order:**
```bash
./scripts/manage.sh start ric         # optional (E2/xApps)
./scripts/manage.sh start gnb         # wait until gnb.log shows "Waiting for data"
./scripts/manage.sh start monitoring  # influxdb + grafana + telegraf
./scripts/manage.sh start multi_ue    # bridge + NUM_UES srsUEs (auto-started)
```

**2. Confirm both UEs attached (RRC + PDU session, get a 10.45.0.x IP):**
```bash
docker exec multi_ue sh -c 'grep -aE "RRC Connected|PDU Session" /tmp/ue1.log | tail -2'
docker exec multi_ue sh -c 'grep -aE "RRC Connected|PDU Session" /tmp/ue2.log | tail -2'
docker exec multi_ue ip netns exec ue1 ping -c2 10.45.0.1     # gateway reachable
```
If a UE is stuck at `Attaching...` and `gnb.log` shows `Completed 0 of 23040
samples`, the ZMQ stream is desynced — do the clean restart from
[multi_ue/README.md](multi_ue/README.md) (`down multi_ue` → `stop/start gnb` →
`start multi_ue`).

**3. Start iperf3 servers on the UE gateway (one port per UE):**
```bash
docker exec -d open5gs_5gc iperf3 -s -p 5201
docker exec -d open5gs_5gc iperf3 -s -p 5202
```

**4. Generate traffic on both UEs (bounded UDP — avoid unlimited TCP):**
```bash
docker exec multi_ue /srsran/config/run_scenario.sh \
  --video-client --bitrate 1M --server-ip 10.45.0.1 --port 5201 --ue 1 --duration 20 &
docker exec multi_ue /srsran/config/run_scenario.sh \
  --video-client --bitrate 1M --server-ip 10.45.0.1 --port 5202 --ue 2 --duration 20 &
wait
```
Concurrent latency-only across all UEs (no port contention) also works:
```bash
docker exec multi_ue /srsran/config/run_all_scenarios.sh --latency --server-ip 10.45.0.1
```

**5. Verify metrics landed in InfluxDB (per `ue_id`):**
```bash
docker exec influxdb sh -c "curl -s -G 'http://localhost:8081/api/v3/query_sql' \
  --data-urlencode 'db=srsran' \
  --data-urlencode 'q=SELECT ue_id, count(*) AS samples, round(max(throughput_mbps),3) AS max_mbps FROM ue_traffic GROUP BY ue_id ORDER BY ue_id'"
```

**6. View in Grafana:** open the **Multi-UE Traffic** dashboard
(`http://localhost:3300/d/multi-ue-traffic`) — per-UE throughput, RTT, jitter,
loss and retransmits.

**Tear down:**
```bash
docker compose -f multi_ue/docker-compose.yaml down
```

### 9.4 Network slicing (two slices on one cell)

Run two S-NSSAIs (`sst:1`, `sst:2`) on the existing single cell and place UEs on
a slice via their **subscription** — no second cell needed. Provisioning is done
at runtime (no image rebuild).

**Config (already applied in this repo):**
- `gnb_zmq.yml`: `cell_cfg.slicing: [{sst:1},{sst:2}]` and
  `cu_cp …tai_slice_support_list: [{sst:1},{sst:2}]` (gNB advertises both).
- `open5gs-5gc.yml.in`: AMF `plmn_support.s_nssai += sst:2`, NSSF `nsi += sst:2`.
- `add_users.py`: optional 10th CSV field = `sst`; `open5gs_add_ue.sh` `docker cp`s
  this updated script into the container before provisioning (no rebuild).

**Provision per-UE slices (after gNB/5GC is up, before starting UEs):**
```bash
# Boot provisions every subscriber as sst:1 from subscriber_db.csv.
# Re-provision the slice-2 UE(s) — e.g. UE2 -> sst:2:
./scripts/open5gs_add_ue.sh --csv srsRAN_Project/gnb-zmq/project-config/subscriber_db_slice2.csv
```
(The 5GC mongo is in-container and ephemeral, so re-run this after any `gnb` cycle.)

**Verify the two slices (single cell):**
```bash
docker logs open5gs_5gc 2>&1 | grep -aE "S_NSSAI" | tail
# UE1 -> S_NSSAI[SST:1 ...], UE2 -> S_NSSAI[SST:2 ...]
```

> **Note — UEs per cell.** The `multi_ue` co-located bridge **sums** all UE
> uplinks, so (a) every srsUE must be running for the summed uplink to flow
> (don't space UE starts far apart), and (b) more than ~2 UEs attaching on one
> cell contend on PRACH and may not all attach. Validating *two slices* needs
> only one UE per slice; *2 UEs per slice* uses two cells — see §9.5.

### 9.5 Two cells, two slices, two UEs per slice (Approach A)

> Full copy-paste deployment + verification + troubleshooting:
> **[docs/RUNBOOK_2GNB_2SLICE.md](docs/RUNBOOK_2GNB_2SLICE.md)**.

Run **two single-cell gNBs** sharing one 5GC + RIC: cell 1 (`gnb`, PCI 1, sst1)
and cell 2 (`gnb2`, PCI 2, sst2). In ZMQ both use the same `dl_arfcn 368500` —
the cells are separated by **isolated ZMQ wires + PCI + slice**, not frequency.
`multi_ue` runs **two bridges**: bridge1 (UE1,UE2 → gnb1) and bridge2 (UE3,UE4 →
gnb2, ports 2010/2011), set by `CELL2_UES`/`GNB2_IP` in `multi_ue/.env`. Two
UEs per cell also stays under the PRACH-contention limit from §9.4.

```bash
./scripts/manage.sh start gnb         # starts 5gc + gnb + gnb2
# (after both gNBs are up) provision the slice-2 UEs:
./scripts/open5gs_add_ue.sh --csv srsRAN_Project/gnb-zmq/project-config/subscriber_db_slice2.csv
./scripts/manage.sh start multi_ue    # NUM_UES=4, CELL2_UES=3,4
```
Verify (UE1/2 on cell1/SST:1, UE3/4 on cell2/SST:2):
```bash
docker logs open5gs_5gc 2>&1 | grep -aE "S_NSSAI" | tail -4
docker exec srsran_gnb  sh -c 'grep -ao "rnti=0x46[0-9a-f]*" /tmp/gnb.log | sort -u'  # cell1 UEs
docker exec srsran_gnb2 sh -c 'grep -ao "rnti=0x46[0-9a-f]*" /tmp/gnb.log | sort -u'  # cell2 UEs
```

> **E2 with two gNBs — works (was a RIC startup race, now fixed).** Both gNBs
> run E2 to the same RIC. An earlier segfault in `send_e2_setup_request` was
> **not** a two-gNB limit: the RIC `e2mgr` loses a startup race with Redis
> (`dbaas`) — it retries the RNIB connection only 3×/30 ms then **exits**, so
> `e2term` can't route E2 (`RMR_ERR_NOENDPT`) and the gNB's E2 setup dereferences
> a null association and crashes. Fixed by `restart: on-failure` on `e2mgr`
> (oran-sc-ric compose) plus `manage.sh _ric_heal`, which restarts `e2term`
> after `e2mgr` is up (e2term doesn't exit, so a restart policy can't save it).
> `./scripts/manage.sh start ric` now self-heals; both gNBs E2-setup cleanly.

> **KPM xApp needs the DU node — and `e2sm_ccc` must be off.** KPM metrics
> (`DRB.UEThpDl/Ul`) come from the **DU** E2 node (`gnbd_001_001_00000N_0`), not
> the CU-CP. With `e2sm_ccc_enabled: true` the srsRAN **DU never completes E2
> setup** (it stops right after adding the CCC RAN function id 4; CU-CP/CU-UP are
> fine), so no `gnbd_` node appears in the RNIB and KPM subscriptions fall to the
> CU-CP, which rejects them. Setting `e2sm_ccc_enabled: false` on both gNBs makes
> the DU register and KPM work. Run the xApp per gNB:
> ```bash
> cd oran-sc-ric
> docker compose exec python_xapp_runner ./kpm_mon_xapp.py \
>   --e2_node_id gnbd_001_001_000001_0 --kpm_report_style 1 --metrics DRB.UEThpDl,DRB.UEThpUl
> # gNB2: --e2_node_id gnbd_001_001_000002_0  (use a 2nd instance with distinct
> #       --http_server_port/--rmr_port; data is tagged by e2_node_id in InfluxDB)
> ```
> KPM data refreshes slowly under real-time ZMQ (~every 10–15 s), so indications
> are sparse. Find the live DU node ids with:
> `docker exec ric_dbaas redis-cli keys '*RAN:gnbd*'`.

## 10. Monitoring Stack
Set `GNB_IP` in `srsRAN_Project/docker/.env` (same as `e2.bind_addr`).

Start:
```bash
cd srsRAN_Project
docker compose -f docker/docker-compose.ui.yml up -d
```
Grafana: http://localhost:3300

## 11. xApps (Optional)
Run xApps (RIC must be running, E2 enabled):
```bash
cd oran-sc-ric
docker compose exec python_xapp_runner ./kpm_mon_xapp.py --kpm_report_style=1
```
Other examples:
```bash
cd oran-sc-ric
docker compose exec python_xapp_runner ./simple_mon_xapp.py --metrics=DRB.UEThpDl,DRB.UEThpUl
cd oran-sc-ric
docker compose exec python_xapp_runner ./simple_rc_xapp.py
```

## 12. Troubleshooting (Quick)
- RIC not deployed: disable E2 in gNB config.
- Grafana no data: verify `WS_URL` ip in `srsRAN_Project/docker/.env`, then try to ping from Telegraf container, check logs.
- UE attach stuck: verify IMSI/subscriber DB, N2 connection, 5GC logs.
- UE no internet: verify ogstun, NAT, IP forwarding in 5GC container.
- for more details refer to [troubleshooting.md](./Troubleshooting.md)

## 13. Utilities
- Subscribers: 
  - add subscriber: `./scripts/open5gs_add_ue.sh`
  - get subscriber: `./scripts/get_open5gs_subscribers.sh` 
- Container status: `./scripts/dockstatus.sh`
- Network status: `./scripts/net_manage.sh`
- deployment: `./scripts/manage.sh`

## 14. References
- https://github.com/srsran/srsran_project
- https://github.com/srsran/oran-sc-ric
