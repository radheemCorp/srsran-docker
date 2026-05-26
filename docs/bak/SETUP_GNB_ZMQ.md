# Deploy gNB with ZMQ (External UE Bridge)

This guide shows how to run the srsRAN gNB in ZMQ-RF mode with external UE devices
connected via a ZMQ bridge. No UHD SDR hardware is required.

**Components**: ORAN-SC RIC (optional), Open5GS Core, ZMQ Bridge, and external UE containers.

---

## 1. Build images

All images are built from a single Dockerfile using a shared Docker Compose file.

### Prerequisites

- No host-level dependencies are required to build the images. UHD drivers and SDR hardware are only needed at runtime for the UHD variant.

### Build steps

```bash
cd srsRAN_Project/docker
docker compose build
```

- **Dockerfile:** `srsRAN_Project/docker/Dockerfile`
- **Compose file:** `srsRAN_Project/docker/docker-compose.yml`

### Verify the build

Confirm all images were built successfully:

```bash
docker images | grep -E "srsran|open5gs"
```

Expected output (tag may differ if using `--tag`):

| Image | Description |
|-------|-------------|
| `gnb` (or whatever `build.args` / `image:` is set in `docker-compose.yml`) | srsRAN gNB binary |
| `open5gs` | Open5GS 5GC core |

### Sync image name in compose file

After building, verify the image name reference in the deploy compose file matches the built image:

```bash
grep "image:" srsRAN_Project/gnb-zmq/docker-compose.yml
```

If you tagged the build (e.g., `docker compose build --tag rptestbed/gnb:latest`), update the `image:` key in `srsRAN_Project/gnb-zmq/docker-compose.yml` and `srsRAN_Project/gnb-zmq/docker-compose.ui.yml` accordingly.

### Pull pre-built images (alternative)

If you skip the build step, pull the pre-built images from the registry:

- gNB image: `rptestbed/gnb:20260507-dpdk`
- open5gs image: `rptestbed/open5gs:20260507-dpdk`
- UE/bridge image: `ghcr.io/sulaimanalmani/srsranzmq/srsue:v1.1`



## 1.1 Available Docker Compose Files

| Compose File | Services | Purpose | deploy location |
|--------------|----------|---------| -------- |
| `docker-compose.yml` | `5gc`, `gnb` | Complete gNB + Open5Gs Core deployment | srsRAN_Project/gnb-zmq |
| `docker-compose.yml` | `e2-agent`, `ric`, `xApp` | Minimal deployment of O-RAN Software Community (SC) Near-Real-time RIC | oran-sc-ric |
| `docker-compose.ui.yml` | `telegraf`, `influxdb`, `grafana` | Monitoring and metrics visualization | srsRAN_Project |

## 1.2 Configuration files 

| Services | Purpose | location |
|----------|---------| -------- |
| `gnb` | Configuring the gNB | srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml |
| `open5gs` | Configuring the Open5gs | srsRAN_Project/gnb-zmq/project-config/open5gs-5gc.yml.in |
| `open5gs` | Configuring the Open5gs | srsRAN_Project/gnb-zmq/project-config/open5gs.env 



---

## 2. Setup Docker networks

### 2.0 Initialize all required networks

Run the init script to create **all** Docker and host networks needed for this setup:

```bash
./scripts/net_manage.sh init
```

This creates the following networks:

| Network | IPv4 Subnet | Type | Required by |
|---------|-------------|------|-------------|
| `n2` | `10.53.1.0/24` | macvlan | `gnb-zmq/docker-compose.yml` (5GC, gNB) |
| `n3` | `10.10.3.0/24` | macvlan | `gnb-zmq/docker-compose.yml`, `ue/*/docker-compose.yaml`, `ue/bridge/docker-compose.yaml` |
| `n6` | `10.41.0.0/24` | macvlan | 5GC N6 (internet-facing) |
| `metrics` | `172.19.1.0/24` | bridge | `docker-compose.ui.yml` (Telegraf, InfluxDB, Grafana) |
| `ric_network` / `oran-sc-ric` | `10.0.2.0/24` | bridge | `gnb-zmq/docker-compose.yml` for RIC, `oran-sc-ric/docker-compose.yml` |
| `n3br` | `10.10.3.0/24` | macvlan (parent) | `ue/bridge/docker-compose.yaml` |
| `ue_n3` | `10.10.3.0/24` | macvlan (child of n3br) | `ue/*/docker-compose.yaml` for UE containers |

The host-side helper macvlan interface (`macvlan_ran`) and PDN route are also created.

### 2.1 Verify networks

List all Docker networks and verify they match the subnets declared in the Docker Compose files:

```bash
./scripts/net_manage.sh dnet
```

Expected output:

```
NETWORK                  IPv4 SUBNETS               IPv6 SUBNETS
-------                  ------------               ------------
n2                       10.53.1.0/24               -
n3                       10.10.3.0/24               -
n6                       10.41.0.0/24               -
metrics                  172.19.1.0/24              -
ric_network              10.0.2.0/24                -
oran-sc-ric              10.0.2.0/24                -
n3br                     10.10.3.0/24               -
ue_n3                    10.10.3.0/24               -
macvlan_ran              10.53.1.254/24             -
```

### 2.2 Fix mismatched networks

If any network already exists with a wrong subnet, remove then reinitialize:

```bash
# Remove existing (mismatched) networks
./scripts/net_manage.sh remove

# Recreate all networks with correct defaults
./scripts/net_manage.sh init
```

### 2.3 Override network parameters

All subnets and names can be overridden via environment variables (e.g. `N3_SUBNET=10.10.4.0/24`).
See `scripts/net_manage.sh` for all configurable variables.

---

## 3. Deploy Open5GS (5GC)

### 3.0 Sync UE IP configuration

The UE IP subnet must match between `open5gs.env` (used by the 5GC entrypoint for routing/NAT)
and `subscriber_db.csv` (used by the SMF/UPF session config).

| File | Parameter | Example |
|------|-----------|---------|
| `srsRAN_Project/gnb-zmq/project-config/open5gs.env` | `UE_IP_BASE` | `10.45.0` |
| `srsRAN_Project/gnb-zmq/project-config/open5gs.env` | `UE_IP_RANGE` | `10.45.0.0/24` |
| `srsRAN_Project/gnb-zmq/project-config/open5gs.env` | `UE_GATEWAY_IP` | `10.45.0.1` |
| `srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv` | `ip_alloc` column | `10.45.0.2`, `10.45.0.3`, etc. |

The 5GC entrypoint hardcodes the subnet as `${UE_IP_BASE}.0/24` regardless of what
`UE_IP_RANGE` is set to. **All subscriber `ip_alloc` values must fall within this /24.**

Verify your subscriber data before starting:

```bash
# Should list UEs with IPs inside 10.45.0.0/24
cat srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv
```

### 3.1 Deploy the 5GC

```bash
cd srsRAN_Project/gnb-zmq
docker compose up -d 5gc
```

### 3.2 Verify forwarding and NAT rules

```bash
# IP forwarding should be enabled
docker exec open5gs_5gc sysctl net.ipv4.ip_forward

# ogstun TUN interface should exist with the gateway IP
docker exec open5gs_5gc ip addr show ogstun

# POSTROUTING MASQUERADE rule for UE subnet
docker exec open5gs_5gc iptables-legacy -t nat -L POSTROUTING -v -n

# FORWARD rules (ogstun <-> internet)
docker exec open5gs_5gc iptables-legacy -L FORWARD -v -n

# 5GC logs — confirm all NFs started, no errors
docker logs open5gs_5gc 2>&1 | tail -30
```

Expected output:
- `ogstun` interface: `10.45.0.1/24`
- MASQUERADE rule: source `10.45.0.0/24` → out `eth0`
- FORWARD: ACCEPT for both directions between `ogstun` and `eth0`

---

## 4. Deploy ORAN-SC RIC (Optional)

> **Note**: ORAN-SC RIC is optional. If deployed, E2 must be enabled in the gNB config. If skipped, E2 must be disabled (see the Troubleshooting section for details).

For more information on the ORAN-SC Near-Real-time RIC, see the [RIC README](oran-sc-ric/README.md).

### Prerequisites

- The gNB must be running before deploying the RIC (the RIC E2 agent registers with the gNB).
- All networks must already be created (see section 2.0).

### Deploy RIC

```bash
cd oran-sc-ric
docker compose up -d
```

This starts:

| Service | Subnet | Purpose |
|---------|--------|---------|
| `e2-agent` | `oric_network` / `oran-sc-ric` (`10.0.2.0/24`) | E2 Node agent that connects gNB to RIC |
| `ric` | `oric_network` / `oran-sc-ric` (`10.0.2.0/24`) | Near-Real-time RIC platform |
| `xApp` | `oric_network` (`10.0.2.0/24`) | Placeholder — xApps are deployed separately (see section 11) |

### Enable E2 in the gNB config

Before starting gNB, enable E2 connections in the gNB config:

```yaml
# srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml
e2:
  enable_du_e2: true
  enable_cu_cp_e2: true
  enable_cu_up_e2: false
  addr: 10.0.2.5          # RIC IP — set to the RIC container's IP
  bind_addr: <host-ip>    # gNB's host IP — see below how to find it
```

**Finding the RIC IP and gNB bind address:**

- The RIC E2 service typically binds to `10.0.2.5` on the `oric_network` — run the following to confirm:

```bash
cd oran-sc-ric
docker compose ps
# Note the IP address of the ric or e2-agent container
```

- **If gNB uses host networking** (for optimum UHD performance), `bind_addr` is the host IP:

```bash
ip a | grep "inet " | grep -v 127.0.0.1
```

- **If gNB does not use host networking**, get the gNB container IP:

```bash
cd srsRAN_Project/gnb-zmq
docker compose ps
# Note the gNB container's IP address
```

The `addr` field must point to the RIC's IP, and `bind_addr` must point to the gNB's IP. Both must be reachable over the `oric_network` (`10.0.2.0/24`).

---

## 5. Start gNB

```bash 
cd srsRAN_Project/gnb-zmq
docker compose up -d gnb 
```
- review startup at logs 
```bash 
docker compose logs gnb
```
- view gNB runtime logs at `srsRAN_Project/gnb-zmq/gnb-storage/gnb.log`

---

## 6. Start the ZMQ Bridge

The bridge connects gNB → external UEs over ZMQ. It handles multiple UEs in a single
GNU Radio process.

### 6.1 Deploy

```bash
cd ue/bridge
docker compose up -d
```

### 6.2 Verify bridge sockets

```bash
docker exec zmq_bridge ss -ltnp
docker exec zmq_bridge ss -tnp
```

Expected:

| Socket | Direction | Description |
|--------|-----------|-------------|
| LISTEN on `10.10.3.237:2001` | Bridge → gNB (uplink aggregate) | REP sink |
| LISTEN on `10.10.3.237:2201` | Bridge ← gNB → UE1 (downlink) | REP sink |
| LISTEN on `10.10.3.237:2202` | Bridge ← gNB → UE2 (downlink) | REP sink |
| ESTAB `10.10.3.237:2000` ↔ gNB | Bridge → gNB (downlink) | REQ source |

At this stage (UEs not started yet), you should see the bridge connected to the gNB
on ports `2000`/`2001`, but **no ESTAB connections to UE containers** yet.

---

## 7. Start UE1

```bash
cd ue/ue1
docker compose up -d
```

Then start the UE instance:

```bash
docker compose exec -it srsran_ue_host /srsran/config/start_ue.sh 1
```

This will:
- Generate `/tmp/ue_1.conf` from env vars (`GNB_IP`, `ZMQ_BRIDGE_IP`, `UE_BIND_IP`, `UE_ZMQ_MODE`)
- Create a network namespace `ue1`
- Run srsUE which will create `tun_srsue` inside the namespace after successful attach

---

## 8. Start UE2

Repeat the same steps in the other UE container:

```bash
cd ue/ue2
docker compose up -d
docker compose exec -it srsran_ue_host /srsran/config/start_ue.sh 2
```

---

## 9. Verify all connections

Check the bridge again — all UE sockets should now be ESTABLISHED:

```bash
docker exec zmq_bridge ss -tnp
```

Expected connections:

| Local Address | Remote | Process |
|--------------|--------|---------|
| `10.10.3.237:52674` → `10.10.3.231:2000` | UE1 → gNB | bridge REQ source (UE1 uplink) |
| `10.10.3.237:2201` ← `10.10.3.234:35894` | gNB → UE1 | bridge REP sink (UE1 downlink) |
| `10.10.3.237:43852` → `10.10.3.234:2101` | UE1 → bridge | bridge REQ source (UE1 uplink) |
| `10.10.3.237:42638` → `10.10.3.235:2102` | UE2 → bridge | bridge REQ source (UE2 uplink) |
| `10.10.3.237:2202` ← `10.10.3.235:52632` | gNB → UE2 | bridge REP sink (UE2 downlink) |

---

## 10. Verify UE attach

Inside each UE container:

```bash
# tun_srsue should now exist in the network namespace
docker exec ue1 ip netns exec ue1 ip addr show tun_srsue
docker exec ue2 ip netns exec ue2 ip addr show tun_srsue
```

Expected: a `tun_srsue` interface with a `10.45.0.x` address.

Check the 5GC logs to confirm the registration:

```bash
docker logs open5gs_5gc 2>&1 | grep -iE "ngap| registration|pdu|session"
```

Expected:
- `gNB-N2 accepted[...] in ng-path module`
- `gNB-N2[...] max_num_of_ostreams`
- UE registration messages (look for IMSI values from `subscriber_db.csv`)

Check the gNB log:

```bash
docker logs srsran_gnb 2>&1 | grep -iE "cell|prach|ssb|msg1|msg2|msg3|msg4|nc:|ue:"
```

---

## 11. Deploy Monitoring Stack

### Prerequisites

- Set the gNB IP in `srsRAN_Project/docker/.env` — this is the same IP as `e2.bind_addr` if you configured the ORAN RIC.

**Finding the gNB IP:**

- **If using host networking**, get the host IP:

```bash
ip a | grep "inet " | grep -v 127.0.0.1
```

- **If not using host networking**, get the container IP:

```bash
./scripts/dockstatus.sh
# If multiple IPs appear, use the one in the same subnet as the monitoring stack (172.19.1.0/24)
```

### Deploy

```bash
cd srsRAN_Project
docker compose -f docker/docker-compose.ui.yml up -d
```

This starts:

| Service | Subnet | Port | Purpose |
|---------|--------|------|---------|
| `telegraf` | `metrics` (`172.19.1.0/24`) | — | Collects metrics from gNB |
| `influxdb` | `metrics` (`172.19.1.0/24`) | `8086` | Time-series database |
| `grafana` | `metrics` (`172.19.1.0/24`) | `3300` | Visualization dashboard |

### Access Grafana

1. Open [http://localhost:3300](http://localhost:3300) in your browser
2. Default credentials are configured in the Grafana provisioned config
3. Select **Home** to view the dashboards

---

## 12. Run xApps on ORAN RIC

> **Note**: xApps require the ORAN-SC RIC to be deployed (see section 4) and E2 to be enabled in the gNB config (`enable_du_e2` and `enable_cu_cp_e2` must be `true`).

Make sure the ORAN RIC is running:

```bash
cd oran-sc-ric
docker compose ps
```

### 12.1 KPM Monitoring xApp
- style 1: reports aggregated cell-level metrics every second
```bash
cd oran-sc-ric
docker compose exec python_xapp_runner ./kpm_mon_xapp.py --kpm_report_style=1
```

**Expected response:**

```bash
1778148342900 59/RMR [INFO] ric message routing library on SI95 p=4562 mv=3 flg=00 id=a (f447e29 4.9.4 built: Dec 13 2023)
Subscribe to E2 node ID: gnbd_001_001_00019b_0, RAN func: e2sm_kpm, Report Style: 1, metrics: ['DRB.UEThpUl', 'DRB.UEThpDl']
Successfully subscribed with Subscription ID:  3DOLoWdjChuzSpbTq6mend3P1z4
Received Subscription ID to E2EventInstanceId mapping: 3DOLoWdjChuzSpbTq6mend3P1z4 -> 5
{'response': 'OK', 'status': 200, 'payload': '{}', 'ctype': 'application/json', 'attachment': None, 'mode': 'plain'}
10.0.2.13 - - [07/May/2026 10:05:44] "POST /ric/v1/subscriptions/response HTTP/1.1" 200 -

RIC Indication Received from gnbd_001_001_00019b_0 for Subscription ID: 5, KPM Report Style: 1
E2SM_KPM RIC Indication Content:
-COllecStartTime:  2026-05-07 10:05:45
-Measurements Data:
-granulPeriod: 1000
--Metric: DRB.UEThpUl, Value: [0.0]
--Metric: DRB.UEThpDl, Value: [0.0]
```
- style 5: reports per-UE metrics every second (if multiple UEs, each UE's metrics are reported separately), requires atleast 2 UEs to be attached to the gNB
```bash
cd oran-sc-ric
docker compose exec python_xapp_runner ./kpm_mon_xapp.py --kpm_report_style=5
```

**Expected response:**

```bash
RIC Indication Received from gnbd_001_001_00019b_0 for Subscription ID: 2, KPM Report Style: 5
E2SM_KPM RIC Indication Content:
-ColletStartTime:  2026-05-12 00:06:48
-Measurements Data:
--UE_id: 0
---granulPeriod: 1000
---Metric: DRB.UEThpUl, Value: [107.0]
---Metric: DRB.UEThpDl, Value: [20.0]
--UE_id: 1
---granulPeriod: 1000
---Metric: DRB.UEThpUl, Value: [21.0]
---Metric: DRB.UEThpDl, Value: [107.0]
```

---

### 12.2 Simple xApp

```bash
cd oran-sc-ric
docker compose exec python_xapp_runner ./simple_mon_xapp.py --metrics=DRB.UEThpDl,DRB.UEThpUl
```

**Expected response:**

```bash
$ docker compose exec python_xapp_runner ./simple_mon_xapp.py --metrics=DRB.UEThpDl,DRB.UEThpUl
1778544505460 46/RMR [INFO] ric message routing library on SI95 p=4561 mv=3 flg=00 id=a (f447e29 4.9.4 built: Dec 13 2023)
Subscribe to E2 node ID: gnbd_001_001_00019b_0, RAN func: e2sm_kpm for metrics ['DRB.UEThpDl', 'DRB.UEThpUl']
Successfully subscribed with Subscription ID:  3DbInAIOhS0uLUnN9RpsXGKplxX
Received Subscription ID to E2EventInstanceId mapping: 3DbInAIOhS0uLUnN9RpsXGKplxX -> 3
{'response': 'OK', 'status': 200, 'payload': '{}', 'ctype': 'application/json', 'attachment': None, 'mode': 'plain'}
10.0.2.13 - - [12/May/2026 00:08:26] "POST /ric/v1/subscriptions/response HTTP/1.1" 200 -

RIC Indication Received from gnbd_001_001_00019b_0 for Subscription ID: 3
E2SM_KPM RIC Indication Content:
-ColletStartTime:  2026-05-12 00:08:27
-Measurements Data:
-granulPeriod: 100
--Metric: DRB.UEThpDl, Value: [125.0]
--Metric: DRB.UEThpUl, Value: [129.0]

RIC Indication Received from gnbd_001_001_00019b_0 for Subscription ID: 3
E2SM_KPM RIC Indication Content:
-ColletStartTime:  2026-05-12 00:08:29
-Measurements Data:
-granulPeriod: 100
--Metric: DRB.UEThpDl, Value: [126.0]
--Metric: DRB.UEThpUl, Value: [126.0]

```

---

### 12.3 Simple RC xApp

```bash
cd oran-sc-ric
docker compose exec python_xapp_runner ./simple_rc_xapp.py
```

**Expected behavior:**

```bash
00:08:05 Send RIC Control Request to E2 node ID: gnbd_001_001_00019b_0 for UE ID: 0, PRB_min_ratio: 10, PRB_max_ratio: 30
Received RIC_CONTROL_ACK
00:08:10 Send RIC Control Request to E2 node ID: gnbd_001_001_00019b_0 for UE ID: 0, PRB_min_ratio: 10, PRB_max_ratio: 50
Received RIC_CONTROL_ACK
00:08:15 Send RIC Control Request to E2 node ID: gnbd_001_001_00019b_0 for UE ID: 0, PRB_min_ratio: 10, PRB_max_ratio: 70
Received RIC_CONTROL_ACK
00:08:20 Send RIC Control Request to E2 node ID: gnbd_001_001_00019b_0 for UE ID: 0, PRB_min_ratio: 10, PRB_max_ratio: 100
Received RIC_CONTROL_ACK
```
---

## 13. Monitoring Metrics

The monitoring stack collects and visualizes key radio metrics via Telegraf, InfluxDB, and Grafana. The xApps also expose metrics through the RIC E2 interface.

### Metrics collected via Telegraf

#### MCS (Modulation and Coding Scheme)

MCS determines how much data is packed into every radio signal. The gNB chooses an MCS index (usually 0–28) based on the quality of the radio link.

- **High MCS (e.g., 28):** Uses complex modulation (256QAM) to pack many bits into one symbol. Provides **maximum speed** but requires a **perfect signal**.
- **Low MCS (e.g., 2):** Uses simple modulation (QPSK) with lots of redundant error correction bits. Is **slow** but very **rugged** and works in poor conditions.

#### BLER (Block Error Rate)

BLER measures the percentage of data "blocks" that arrived corrupted and could not be fixed by the receiver.

- **Target BLER:** In 5G, the goal is typically **10% (0.1)**.
- **High BLER (> 10%):** The connection is "noisy." You will experience lag and retransmissions. The gNB will downshift the MCS to a lower, more stable index.
- **Low BLER (< 1%):** The connection is "too easy." The gNB will upshift the MCS to a higher index to get more speed.

#### How MCS and BLER Work Together (The Link Adaptation Loop)

1. **The Test:** The gNB sends data at a certain **MCS**.
2. **The Result:** The receiver calculates the **BLER**.
3. **The Feedback:** If BLER is high, the gNB **lowers the MCS** (stability over speed). If BLER is low, the gNB **raises the MCS** (speed over stability).

| Feature | MCS | BLER |
| :--- | :--- | :--- |
| **What it represents** | Transmission Efficiency | Transmission Error Rate |
| **Controlled by** | The Base Station (gNB) | The Radio Environment |
| **Goal** | Highest possible value | Stable value (~10%) |
| **If it's too high...** | The signal will likely crash (High BLER) | Throughput drops due to retransmissions |
| **If it's too low...** | Wasting network capacity | Could be going faster (lowering efficiency) |

### Metrics collected via xApp

The xApps below expose additional metrics through the E2SM-KPM RIC service:

- **DRB.UEThpDl** (Downlink User Equipment Throughput): The amount of data (in bits or kilobits per second) successfully delivered to the UE over the Data Radio Bearers (DRBs) during the measurement interval.

- **DRB.UEThpUl** (Uplink User Equipment Throughput): The amount of data successfully sent from the UE to the gNB.

---

## Troubleshooting

### UE stuck on "Attaching UE..." / `tun_srsue` never appears

This means the UE never completed PDU session establishment.

1. **Check subscriber IMSI matches** — the `imsi` field in the generated config must exist in the CSV:
   ```bash
   docker exec ue1 cat /tmp/ue_1.conf | grep imsi
   cat srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv
   ```

2. **Verify IP subnet matches** — the UE's assigned IP from the CSV must be within
   the `/24` subnet set by the 5GC entrypoint:
   ```bash
   docker exec open5gs_5gc ip addr show ogstun
   # Should show /24, all subscriber IPs must fit
   ```

3. **Restart 5GC after subscriber CSV changes** — the entrypoint loads the CSV into MongoDB only at startup:
   ```bash
   docker compose restart 5gc
   ```

4. **Check gNB-N2 connection** — the gNB must have established NGAP with the AMF:
   ```bash
   docker logs srsran_gnb 2>&1 | grep "ngap" | tail -10
   docker logs open5gs_5gc 2>&1 | grep "gNB-N2" | tail -10
   ```

### E2 / RIC errors blocking gNB startup

If ORAN-SC RIC is **not deployed**, **disable E2** in the gNB config:

```yaml
# srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml
e2:
  enable_du_e2: false
  enable_cu_cp_e2: false
  enable_cu_up_e2: false
```

If you want to **enable E2**, make sure:
1. The RIC is deployed: `cd oran-sc-ric && docker compose up -d`
2. `e2.addr` in the gNB config points to the RIC's IP on the `oric_network`
3. `e2.bind_addr` points to the gNB's own IP (or the host IP if gNB uses host networking)

### Grafana shows no data / monitoring not working

If the monitoring stack deploys but Grafana shows no data:

1. **Verify gNB IP is set in `.env`**:

```bash
cat srsRAN_Project/docker/.env | grep -i gnb
```

2. **Verify Telegraf can reach the gNB**:

```bash
cd srsRAN_Project
docker compose -f docker/docker-compose.ui.yml exec telegraf ping -c 3 <GNB_IP>
```

3. **Check Telegraf logs**:

```bash
docker logs <telegraf_container_id> 2>&1 | tail -20
```

### xApp fails to connect to RIC

If xApps error out when trying to subscribe:

1. **Check the RIC is running**:

```bash
cd oran-sc-ric && docker compose ps
```

2. **Check E2 is enabled in the gNB config**:

```bash
grep -A 5 "e2:" srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml
```

3. **Check the RIC IP matches `e2.addr` in the gNB config**. Look up the RIC IP:

```bash
cd oran-sc-ric && docker compose ps
```

4. **The gNB must be running before the xApp starts** — the E2 agent registers with the gNB at gNB startup. Restart the gNB if you added RIC after gNB was already running:

```bash
cd srsRAN_Project/gnb-zmq && docker compose up -d --force-recreate gnb
```

### No RRC/NAS traffic between UE and gNB

The ZMQ sockets may be established but no radio data crosses them. This usually means:
- Frequency mismatch (LTE EARFCN vs NR ARFCN)
- The gNB cell is not broadcasting (check gNB logs for "ssb", "prach", "sib")
- The ZMQ bridge is not connected to gNB on the correct ports

### Connection refused after 6 minutes

The gNB AMF `inactivity_timer` defaults to 7200 seconds. If the gNB N2 connection drops
silently, the AMF won't clean up for 2 hours. Check for NAT/port exhaustion or network
interruptions between gNB and AMF containers.

### UE can't access the Internet — missing IP forwarding or NAT

If the UE attaches successfully but has no internet connectivity, the problem is usually
IP forwarding or NAT masquerading rules inside the 5GC container.

1. **Enter the 5GC container**

```bash
docker exec -it open5gs_5gc bash
```

2. **Check the ogstun TUN interface**

```bash
ip addr show ogstun | grep 10.45.0
ip route show table main | grep 10.45
sudo ip -d link show ogstun
```

Expected: `inet 10.45.0.1/24` on ogstun, and a kernel route for `10.45.0.0/24`.

3. **Check IP forwarding**

```bash
sysctl net.ipv4.ip_forward
```

Expected: `net.ipv4.ip_forward = 1`

If it shows `0`, enable it:

```bash
sysctl -w net.ipv4.ip_forward=1
```

To make it permanent inside the container (note: will reset on container restart):

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
```

4. **Check NAT (masquerading) rules**

```bash
iptables-legacy -t nat -L POSTROUTING -v -n
```

Expected: a MASQUERADE rule matching source `10.45.0.0/24`.

If missing, add it (replace `eth0` with your actual internet-facing interface):

```bash
iptables-legacy -t nat -A POSTROUTING -s 10.45.0.0/24 -o eth0 -j MASQUERADE
```

5. **Check FORWARD rules**

```bash
iptables-legacy -L FORWARD -v -n
```

If missing, add the forwarding rules:

```bash
iptables-legacy -A FORWARD -i ogstun -o eth0 -j ACCEPT
iptables-legacy -A FORWARD -i eth0 -o ogstun -m state --state RELATED,ESTABLISHED -j ACCEPT
```

6. **Verify routing table**

```bash
ip route
```

You should see a `default via ... dev eth0` rule.

7. **Test from the UE**

Once forwarding and NAT are in place, test internet access from the phone or UE:

```bash
docker exec ue1 ip netns exec ue1 ping 8.8.8.8
```

