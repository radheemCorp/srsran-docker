# 1. Components  
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


# 1.3 Build open5Gs and gNB images
1. go to srsRAN_Project/docker
2. run docker compose build 
```
docker compose build
```
Note: Alternatively if you have access to rptestbed docker registry you can pull the images 
  - gnb image: rptestbed/gnb:20260507-dpdk 
  - open5gs image: rptestbed/open5gs:20260507-dpdk


# 2. Set PC to performance mode 
```bash 
cd srsRAN_Project
./scripts/srsran_performance
```

# 3. Deploy oran ric (Optional)
```bash 
cd oran-sc-ric
docker compose up -d 
```

# 4. Deploy Open5gs 
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


# Configuring UE in Open5gs  
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

# Deploy gNB

## Configuring gNB
File [gnb-config.yaml](srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml)
### Configure the SDR 
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
- Now look for `Bandwidth range`, in our case it is 20MHz
- The srate is dependent on the bandwidth selected so select accordingly. 

  |Bandwidth (MHz) | Standard Sampling Rate (Msps)|
  | -------------- | ---------------------------- |
  | 5 MHz | 7.68 |
  | 10 MHz | 15.36 |
  | 15 MHz | 23.04 |
  | 20 MHz | 30.72 |

- TODO: add refernce to the formula to calulate srate from bandwidth  
- If oran ric was deployed enable e2 section in the [gnb-config.yaml](srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml)
  - the enable_du_e2 and enable_cu_cp_e2 should be set to true for the xApps to connect and collect metrics from cu and du
  - the bind_address should the ip address of the gnb (host ip in our deployment)
- Now deploy the gNB
```bash 
cd srsRAN_Project/gnb-uhd
# - if the oran ric deployment was skipped make sure to comment the e2 section in srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml
# - the gnb runs in host mode to enable optimum performance, if this is disabled please update the e2.bind_addr in srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml
# - the logs are written to srsRAN_Project/gnb-uhd/gnb-storage/gnb.log 
docker compose up -d gnb 
```
- check if the gnb is running 
- if yes, then review the logs at `srsRAN_Project/gnb-uhd/gnb-storage/gnb.log` for gnb runtime errors 
- if no, then run `docker compose logs gnb` to review the gnb startup logs 

# Connecting UE
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



# Deploy monitoring stack 
```bash
cd srsRAN_Project
docker compose -f docker/docker-compose.ui.yml up -d 
```

# Access monitoring 
1. Go to [http://localhost:3300](http://localhost:3300)
2. Select Home 

# View metrics using xApp
1. goto oran-sc-ric
2. make sure the oran ric is running 
3. enable_du_e2 and enable_cu_cp_e2 are set to true in the gnb config, these are required by the xApp to collect metrics  
4. run the xApp 
## KPM monitoring xApp
```bash
docker compose exec python_xapp_runner ./kpm_mon_xapp.py --kpm_report_style=1


# Expected response 
testbed@testbed:~/testbed/srsran-docker/oran-sc-ric$ docker compose exec python_xapp_runner ./kpm_mon_xapp.py --kpm_report_style=1
1778148342900 59/RMR [INFO] ric message routing library on SI95 p=4562 mv=3 flg=00 id=a (f447e29 4.9.4 built: Dec 13 2023)
Subscribe to E2 node ID: gnbd_001_001_00019b_0, RAN func: e2sm_kpm, Report Style: 1, metrics: ['DRB.UEThpUl', 'DRB.UEThpDl']
Successfully subscribed with Subscription ID:  3DOLoWdjChuzSpbTq6mend3P1z4
Received Subscription ID to E2EventInstanceId mapping: 3DOLoWdjChuzSpbTq6mend3P1z4 -> 5
{'response': 'OK', 'status': 200, 'payload': '{}', 'ctype': 'application/json', 'attachment': None, 'mode': 'plain'}
10.0.2.13 - - [07/May/2026 10:05:44] "POST /ric/v1/subscriptions/response HTTP/1.1" 200 -

RIC Indication Received from gnbd_001_001_00019b_0 for Subscription ID: 5, KPM Report Style: 1
E2SM_KPM RIC Indication Content:
-ColletStartTime:  2026-05-07 10:05:45
-Measurements Data:
-granulPeriod: 1000
--Metric: DRB.UEThpUl, Value: [0.0]
--Metric: DRB.UEThpDl, Value: [0.0]

RIC Indication Received from gnbd_001_001_00019b_0 for Subscription ID: 5, KPM Report Style: 1
E2SM_KPM RIC Indication Content:
-ColletStartTime:  2026-05-07 10:05:46
-Measurements Data:
-granulPeriod: 1000
--Metric: DRB.UEThpUl, Value: [0.0]
--Metric: DRB.UEThpDl, Value: [0.0]

RIC Indication Received from gnbd_001_001_00019b_0 for Subscription ID: 5, KPM Report Style: 1
E2SM_KPM RIC Indication Content:
-ColletStartTime:  2026-05-07 10:05:47
-Measurements Data:
-granulPeriod: 1000
--Metric: DRB.UEThpUl, Value: [0.0]
--Metric: DRB.UEThpDl, Value: [0.0]
```

- note: kpm_report_style=5 requires atleast 2 UE devices connected 

## Simple xApp
```bash
docker compose exec python_xapp_runner ./simple_mon_xapp.py --metrics=DRB.UEThpDl,DRB.UEThpUl

# Expected response 
$ docker compose exec python_xapp_runner ./simple_mon_xapp.py --metrics=DRB.UEThpDl,DRB.UEThpUl
1778148403668 72/RMR [INFO] ric message routing library on SI95 p=4561 mv=3 flg=00 id=a (f447e29 4.9.4 built: Dec 13 2023)
Subscribe to E2 node ID: gnbd_001_001_00019b_0, RAN func: e2sm_kpm for metrics ['DRB.UEThpDl', 'DRB.UEThpUl']
Successfully subscribed with Subscription ID:  3DOLw3HDZeTPI3Ui0fM1IYxlGeE
Received Subscription ID to E2EventInstanceId mapping: 3DOLw3HDZeTPI3Ui0fM1IYxlGeE -> 6
{'response': 'OK', 'status': 200, 'payload': '{}', 'ctype': 'application/json', 'attachment': None, 'mode': 'plain'}
10.0.2.13 - - [07/May/2026 10:06:44] "POST /ric/v1/subscriptions/response HTTP/1.1" 200 -
^CUnsubscribe Subscription ID:  3DOLw3HDZeTPI3Ui0fM1IYxlGeE
Successfully unsubscribed from Subscription ID:  3DOLw3HDZeTPI3Ui0fM1IYxlGeE
```
## Simple_rc_xapp
```bash
docker compose exec python_xapp_runner ./simple_rc_xapp.py

# Expected result 
$ docker compose exec python_xapp_runner ./simple_rc_xapp.py
1778148571811 85/RMR [INFO] ric message routing library on SI95 p=4560 mv=3 flg=00 id=a (f447e29 4.9.4 built: Dec 13 2023)
10:09:32 Send RIC Control Request to E2 node ID: gnbd_001_001_00019b_0 for UE ID: 0, PRB_min_ratio: 10, PRB_max_ratio: 30
Received RIC_CONTROL_FAILURE
10:09:37 Send RIC Control Request to E2 node ID: gnbd_001_001_00019b_0 for UE ID: 0, PRB_min_ratio: 10, PRB_max_ratio: 50
Received RIC_CONTROL_FAILURE
10:09:42 Send RIC Control Request to E2 node ID: gnbd_001_001_00019b_0 for UE ID: 0, PRB_min_ratio: 10, PRB_max_ratio: 70
Received RIC_CONTROL_FAILURE
^C10:09:47 Send RIC Control Request to E2 node ID: gnbd_001_001_00019b_0 for UE ID: 0, PRB_min_ratio: 10, PRB_max_ratio: 100
^Cfree(): double free detected in tcache 2
testbed@testbed:~/testbed/srsran-docker/oran-sc-ric$ 
```

# Utilities 
- To get subscribers from Open5gs 
```
./scripts/get_open5gs_subscribers.sh
```
- To get deployed docker services with IPs 
```
./scripts/dockstatus.sh
```

# Monitoring metrics collected 

## Metrics collected using telegraf
### **1. MCS (Modulation and Coding Scheme)**

MCS determines how much data is packed into every radio signal. The gNB chooses an MCS index (usually 0–28) based on the quality of the radio link.

*   **High MCS (e.g., 28):** Like high-speed shorthand. It uses complex modulation (256QAM) to pack many bits into one symbol. It provides **maximum speed** but requires a **perfect signal**.
*   **Low MCS (e.g., 2):** Like speaking slowly and clearly. It uses simple modulation (QPSK) and adds lots of redundant "error correction" bits. It is **slow** but very **rugged** and works in poor conditions.

### **2. BLER (Block Error Rate)**
BLER measures the percentage of data "blocks" that arrived corrupted and could not be fixed by the receiver.

*   **Target BLER:** In 5G, the goal is usually **10% (0.1)**. 
*   **High BLER (> 10%):** The connection is "noisy." You will experience lag and retransmissions. The gNB will see this and "downshift" the MCS to a lower, more stable index.
*   **Low BLER (< 1%):** The connection is "too easy." The gNB will see this as an opportunity to "upshift" the MCS to a higher index to get more speed.

### **How They Work Together (The Loop)**
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

## Metrics collected using xApp

- DRB.UEThpDl (Downlink User Equipment Throughput): This measures the amount of data (in bits or kilobits per second) successfully delivered to the UE over the Data Radio Bearers (DRBs) during the measurement interval.

- DRB.UEThpUl (Uplink User Equipment Throughput): This measures the amount of data successfully sent from the UE to the gNB.

# References 
- https://github.com/srsran/srsran_project
- https://github.com/srsran/oran-sc-ric