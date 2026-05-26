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

Optional: pull prebuilt images
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
Ensure `open5gs.env` UE subnet matches `subscriber_db.csv` IPs.

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
Use your phone to select the test network after gNB is running. Confirm UE registers.

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
- Grafana no data: verify `GNB_IP`, ping from Telegraf, check logs.
- UE attach stuck: verify IMSI/subscriber DB, N2 connection, 5GC logs.
- UE no internet: verify ogstun, NAT, IP forwarding in 5GC container.

## 13. Utilities
- Subscribers: `./scripts/get_open5gs_subscribers.sh`
- Container status: `./scripts/dockstatus.sh`
- Network status: `./scripts/net_manage.sh dnet`

## 14. References
- https://github.com/srsran/srsran_project
- https://github.com/srsran/oran-sc-ric
