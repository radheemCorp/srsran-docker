## 1. Components  
The setup has 4 components oran-ric, Open5gs stack, monitoring stack and the srsRAN gNb.
- for more info on gnb and open5gs refer [here](srsRAN_Project/README.md)
- for more info on ORAN RIC refer [here](oran-sc-ric/README.md)
- to detect UHD device on machine refer [here](docs/FIND_UHD_DEVICE.md)
- for informatin on subscribers, refer [here](docs/subscribers.md)    


## 1.1 Available Docker Compose Files

| Compose File | Services | Purpose | deploy location |
|--------------|----------|---------| -------- |
| `docker-compose.yml` | `5gc`, `gnb` | Complete gNB + Open5Gs Core deployment | srsRAN_Project/gnb-uhd |
| `docker-compose.yml` | `e2-agent`, `ric`, `xApp` | Minimal deployment of O-RAN Software Community (SC) Near-Real-time RIC | oran-sc-ric |
| `docker-compose.ui.yml` | `telegraf`, `influxdb`, `grafana` | Monitoring and metrics visualization | srsRAN_Project |

## 1.2 Configuration files 

| Services | Purpose | location |
|----------|---------| -------- |
| `gnb` | Configuring the gNB | srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml |
| `open5gs` | Configuring the Open5gs | srsRAN_Project/gnb-uhd/project-config/open5gs-5gc.yml.in |
| `open5gs` | Configuring the Open5gs | srsRAN_Project/gnb-uhd/project-config/open5gs.env |


## 1.3 Build Open5GS and gNB Images

All images are built from a single Dockerfile using a shared Docker Compose file.

### Prerequisites

- No host-level dependencies are required to build the images. UHD drivers and SDR hardware are only needed at runtime.

### Build steps

1. Go to the Docker build directory:

```bash
cd srsRAN_Project/docker
```

2. Run the build:

```bash
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
grep "image:" srsRAN_Project/gnb-uhd/docker-compose.yml
```

If you tagged the build (e.g., `docker compose build --tag rptestbed/gnb:latest`), update the `image:` key in `srsRAN_Project/gnb-uhd/docker-compose.yml` and `srsRAN_Project/gnb-uhd/docker-compose.ui.yml` accordingly.

### Pull pre-built images (alternative)

If you skip the build step, you can pull pre-built images from the registry:

- gNB image: `rptestbed/gnb:20260507-dpdk`
- open5gs image: `rptestbed/open5gs:20260507-dpdk`


## 2. Setup Docker networks 

### 2.0 Initialize all required networks

Run the init script to create **all** Docker and host networks needed for this setup:

```bash
./scripts/net_manage.sh init
```

This creates the following networks:

| Network | IPv4 Subnet | Type | Required by |
|---------|-------------|------|-------------|
| `n2` | `10.53.1.0/24` | macvlan | `gnb-uhd/docker-compose.yml` (5GC, gNB) |
| `n3` | `10.10.3.0/24` | macvlan | `gnb-uhd/docker-compose.yml`, `ue/*/docker-compose.yaml` |
| `n6` | `10.41.0.0/24` | macvlan | 5GC N6 (internet-facing) |
| `metrics` | `172.19.1.0/24` | bridge | `docker-compose.ui.yml` (Telegraf, InfluxDB, Grafana) |
| `oric_network` / `oran-sc-ric` | `10.0.2.0/24` | bridge | `gnb-uhd/docker-compose.yml` for RIC, `oran-sc-ric/docker-compose.yml` |

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
oric_network             10.0.2.0/24                -
oran-sc-ric              10.0.2.0/24                -
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

## 3. Deploy ORAN-SC RIC (Optional)

> **Note**: ORAN-SC RIC is optional. If deployed, E2 must be enabled in the gNB config. If skipped, E2 must be disabled in the gNB config (uncomment/comment the `e2:` section).

For more information on the ORAN-SC Near-Real-time RIC, see the [RIC README](oran-sc-ric/README.md).

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
| `xApp` | `oric_network` (`10.0.2.0/24`) | Placeholder — xApps are deployed separately (see section 10) |

### Configure RIC networks

Ensure the `oric_network` and `oran-sc-ric` networks match the subnets defined in the compose files. These networks share the `10.0.2.0/24` subnet and must be compatible with the gNB's `oric_network` declaration in `gnb-uhd/docker-compose.yml`.

### Find the RIC IP

To configure `e2.addr` in the gNB config, find the RIC container's IP:

```bash
cd oran-sc-ric
docker compose ps
# Note the IP address of the ric or e2-agent container (typically on the oric_network)
```

## 4. Deploy Open5GS
Files 
- [open5gc-config.yaml](srsRAN_Project/gnb-uhd/project-config/open5gs-5gc.yml.in)
- [open5gc.env](srsRAN_Project/gnb-uhd/project-config/open5gs.env)

- Make sure the open5gs and the gnb configuration are in sync, the params to focus on:

| Parameter | Description | gNB Location (gnb.yaml) | Core Location (amf.yaml / upf.yaml) | Database Location (WebUI) | 
| --------- | ----------- | ----------------------- | ----------------------------------- | ------------------------- | 
| MCC | "Mobile Country Code (e.g. 001)" | cell_cfg.plmn | amf.guami.plmn_id.mcc | Subscriber IMSI (first 3 digits) | 
| MNC | "Mobile Network Code (e.g. 01)" | cell_cfg.plmn | amf.guami.plmn_id.mnc | Subscriber IMSI (digits 4-5/6) | 
| TAC | Tracking Area Code | cell_cfg.tac | amf.tai.tac | N/A (Must match gNB/AMF) | 
| SST | Slice Service Type | tai_slice_support_list.sst | amf.plmn_support.s_nssai.sst | Subscriber Slice SST | 
| SD | Slice Differentiator | tai_slice_support_list.sd | amf.plmn_support.s_nssai.sd | Subscriber Slice SD | 
| AMF IP | Control Plane Target | cu_cp.amf.addr | amf.ngap.server.address | N/A | 
| UPF IP | User Plane Target | amf.addr (within gNB context) | upf.gtpu.server.address | N/A | 

- protocols to compare 

| Parameter | Critical Note | Requirement | 
| --------- | ------------- | ----------- | 
| SD Format | Decimal vs Hex | Open5GS uses Hex (0x111111) in YAML/Logs. srsRAN YAML requires the Decimal version (1118481) | 
| SCTP Port | 38412 | NGAP communication happens over SCTP. Ensure your firewall allows SCTP on 38412 | 
| GTP-U Port | 2152 | The User Plane data travels via UDP on port 2152 | 
| Integrity/Ciphering | Security Algorithms | "The security order in amf.yaml must be supported by the UE/gNB (e.g., NIA2, NEA2)." | 

- Now deploy the open5gs
```bash 
cd srsRAN_Project/gnb-uhd
docker compose up -d 5gc 
```
- Once deployed run `docker compose cp 5gc:/open5gs/open5gs-5gc.yml curr-open5gs.yaml` to get the running open5gs config from the container


## 5. Configure UE in Open5GS
Device info:
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

## 6. Deploy gNB

### 6.1 Configure gNB
File [gnb-config.yaml](srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml)

### 6.2 Set host to performance mode 
```bash
cd srsRAN_Project
# if you are running the gNB in a VM run this in the VM and the next one on Host
./scripts/vm_srsran_performance

# if you are running the gNB on host, run this on host and skip the previous step
./scripts/srsran_performance
``` 

### 6.3 Configure the SDR 
- get sdr spcifications using uhd_find_devices
```bash 
testbed@testbed:~/testbed/srsran-docker$ uhd_find_devices 
[INFO] [UHD] linux; GNU C++ version 11.2.0; Boost_107400; UHD_4.1.0.5-3
[INFO] [B200] Loading firmware image: /usr/share/uhd/images/usrp_b200_fw.hex...
--------------------------------------------------
-- UHD Device 0
--------------------------------------------------
Device Address:
    serial: 30A3DFB
    name: NI2901
    product: B210
    type: b200
```
- set the ru_sdr.device_driver to uhd 
- set the sdr serial number in ru_sdr.device_args set it like `type=b200,serial=<sdr-serial-number>,num_recv_frames=64,num_send_frames=64`
- To see exactly what bandwidth your specific B210 can handle, run this on your host:
```bash 
 uhd_usrp_probe --args "type=b200,serial=30A3DFB"
```
- set the srate to 23.04
- TODO: add refernce to the formula to calulate srate from bandwidth  
- If ORAN RIC is deployed, enable E2 in the [gnb-config.yaml](srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml):
  - Set `enable_du_e2` and `enable_cu_cp_e2` to `true` so xApps can connect and collect metrics from cu and du.
  - Set `addr` to the RIC's IP address (find it with `docker compose ps` in `oran-sc-ric/`).
  - Set `bind_addr` to the gNB's IP address — see below.

**Finding the gNB IP / bind_addr:**

- **If using host networking** (for optimum performance), use the host IP:

```bash
ip a | grep "inet " | grep -v 127.0.0.1
```

- **If not using host networking**:

```bash
cd srsRAN_Project/gnb-uhd
docker compose ps
# Use the gNB container's IP address
```

- Now deploy the gNB:
```bash
cd srsRAN_Project/gnb-uhd
# If the ORAN RIC deployment was skipped, make sure to comment the e2 section in srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml
# The gNB runs in host mode to enable optimum performance — if this is disabled, please update e2.bind_addr in the gNB config
# Logs are written to srsRAN_Project/gnb-uhd/gnb-storage/gnb.log
docker compose up -d gnb
```
- check if the gnb is running 
- if yes, then review the logs at `srsRAN_Project/gnb-uhd/gnb-storage/gnb.log` for gnb runtime errors 
- if no, then run `docker compose logs gnb` to review the gnb startup logs 

## 7. Connect UE
Steps:
1. Now unlock phone, goto Setting > SiIM cards & mobile networks section 
2. You should see SIM 1 as Test Network, click on it.
3. Click on Mobile networks, click on Automatically select network
4. You should see a pop up asking if you want to choose network manually, select Next, 
5. Then it will ask if you want to disconnect from current network, select yes 
6. Then it will ask if you want to turn off mobile network, selecl yes 
7. It should now be in searching mode, once done it will list some networks.
8. If the gNB and SDR device are working you will see srsRAN 5G or Gradient 5G. Select either one.
9. You should be connected now if not then good luck and happy debugging.    



## 8. Deploy monitoring stack 
- Go to srsRAN_Project/docker/.env and set the gnb IP, it will be the same as e2.bind_address if you already set it up
  - if using network mode host, use `ip a` to get host ip
  - if not using host,
    - go to project root
    - run `bash ./scripts/dockstatus.sh`
    - You should see the container IP, if you see multiple IPs use the one in the same subnet as the monitioring stack.         
- Now deploy 
```bash
cd srsRAN_Project
docker compose -f docker/docker-compose.ui.yml up -d 
```

## 9. Access monitoring
1. Go to [http://localhost:3300](http://localhost:3300)
2. Select Home 

### Troubleshooting: Grafana shows no data / monitoring not working

The monitoring stack deploys but Grafana shows no data. Follow these steps:

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

### Troubleshooting: xApp fails to connect to RIC

If xApps error out when trying to subscribe:

1. **Check the RIC is running**:

```bash
cd oran-sc-ric && docker compose ps
```

2. **Check E2 is enabled in the gNB config**:

```bash
grep -A 5 "e2:" srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml
```

3. **Check the RIC IP matches `e2.addr` in the gNB config**. Look up the RIC IP:

```bash
cd oran-sc-ric && docker compose ps
```

4. **The gNB must be running before the xApp starts** — the E2 agent registers with the gNB at gNB startup. Restart the gNB if you added RIC after gNB was already running:

```bash
cd srsRAN_Project/gnb-uhd && docker compose up -d --force-recreate gnb
``` 

## 10. Run xApps on ORAN RIC
1. goto oran-sc-ric
2. make sure the oran ric is running 
3. enable_du_e2 and enable_cu_cp_e2 are set to true in the gnb config, these are required by the xApp to collect metrics  
4. run the xApp 
### 10.1 KPM Monitoring xApp
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

### 10.2 Simple xApp

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

### 10.3 Simple RC xApp

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
## 11. Utilities 
- To get subscribers from Open5gs 
```
./scripts/get_open5gs_subscribers.sh
```
- To get deployed docker services with IPs 
```
./scripts/dockstatus.sh
```

## 12. Monitoring metrics 

### Metrics collected using telegraf
#### **1. MCS (Modulation and Coding Scheme)**

MCS determines how much data is packed into every radio signal. The gNB chooses an MCS index (usually 0–28) based on the quality of the radio link.

*   **High MCS (e.g., 28):** Like high-speed shorthand. It uses complex modulation (256QAM) to pack many bits into one symbol. It provides **maximum speed** but requires a **perfect signal**.
*   **Low MCS (e.g., 2):** Like speaking slowly and clearly. It uses simple modulation (QPSK) and adds lots of redundant "error correction" bits. It is **slow** but very **rugged** and works in poor conditions.

#### **2. BLER (Block Error Rate)**
BLER measures the percentage of data "blocks" that arrived corrupted and could not be fixed by the receiver.

*   **Target BLER:** In 5G, the goal is usually **10% (0.1)**. 
*   **High BLER (> 10%):** The connection is "noisy." You will experience lag and retransmissions. The gNB will see this and "downshift" the MCS to a lower, more stable index.
*   **Low BLER (< 1%):** The connection is "too easy." The gNB will see this as an opportunity to "upshift" the MCS to a higher index to get more speed.

#### **How They Work Together (The Loop)**
The relationship between them is a constant feedback loop called **Link Adaptation**:

1.  **The Test:** The gNB sends data at a certain **MCS**.
2.  **The Result:** The receiver calculates the **BLER**.
3.  **The Feedback:** If BLER is high, the gNB **lowers the MCS** (Stability over Speed). If BLER is low, the gNB **raises the MCS** (Speed over Stability).

| Feature | MCS | BLER |
| :--- | :--- | :--- |
| **What it represents** | Transmission Efficiency | Transmission Error Rate |
| **Controlled by** | The Base Station (gNB) | The Radio Environment |
| **Goal** | Highest possible value | Stable value (usually ~10%) |
| **If it's too high...** | The signal will likely crash (High BLER) | Throughput drops because of retransmissions |
| **If it's too low...** | You are wasting network capacity | You could be going faster (Lowering efficiency) |

### Metrics collected using xApp

- DRB.UEThpDl (Downlink User Equipment Throughput): This measures the amount of data (in bits or kilobits per second) successfully delivered to the UE over the Data Radio Bearers (DRBs) during the measurement interval.

- DRB.UEThpUl (Uplink User Equipment Throughput): This measures the amount of data successfully sent from the UE to the gNB.

## 13. References 
- https://github.com/srsran/srsran_project
- https://github.com/srsran/oran-sc-ric
