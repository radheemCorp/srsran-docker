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
- Now deploy the open5gs
```bash 
cd srsRAN_Project/gnb-uhd
docker compose up -d 5gc 
```

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

# deploy gNB
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
- kpm monitoring xApp
```bash
docker compose exec python_xapp_runner ./kpm_mon_xapp.py --kpm_report_style=1
```
- note: kpm_report_style=5 requires atleast 2 UE devices connected 
- simple xApp
```bash
docker compose exec python_xapp_runner ./simple_mon_xapp.py --metrics=DRB.UEThpDl,DRB.UEThpUl
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

References 
- https://github.com/srsran/srsran_project
- https://github.com/srsran/oran-sc-ric