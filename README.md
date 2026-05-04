# Setup 
The setup has 4 components oran-ric, Open5gs stack, monitoring stack and the srsRAN gNb.
- for more info on gnb and open5gs refer [here](srsRAN_Project/README.md)
- for more info on ORAN RIC refer [here](oran-sc-ric/README.md)
- to detect UHD device on machine refer [here](docs/FIND_UHD_DEVICE.md)
- for informatin on subscribers, refer [here](docs/subscribers.md)    


## Available Docker Compose Files

| Compose File | Services | Purpose | deploy location |
|--------------|----------|---------| -------- |
| `docker-compose.yml` | `5gc`, `gnb` | Complete gNB + Core deployment | srsRAN_Project/gnb-uhd |
| `docker-compose.yml` | `e2-agent`, `ric`, `xApp` | Minimal deployment of O-RAN Software Community (SC) Near-Real-time RIC | oran-sc-ric |
| `docker-compose.ui.yml` | `telegraf`, `influxdb`, `grafana` | Monitoring and metrics visualization | srsRAN_Project |

# Set PC to performance mode 
```bash 
cd srsRAN_Project
./scripts/srsran_performance
```

# Deploy oran ric (Optional)
```bash 
cd oran-sc-ric
docker compose up -d 
```

# Deploy gNB
```bash 
cd srsRAN_Project/gnb-uhd
# - if the oran ric deployment was skipped make sure to comment the e2 section in srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml
# - the gnb runs in host mode to enable optimum performance, if this is disabled please update the e2.bind_addr in srsRAN_Project/gnb-uhd/project-config/gnb/gnb_uhd.yml
# - the logs are written to srsRAN_Project/gnb-uhd/gnb-storage/gnb.log 
docker compose up -d 
```

# Deploy monitoring stack 
```bash
cd srsRAN_Project
docker compose -f docker/docker-compose.ui.yml up -d 
```

# Connnecting UE 
Device info:
  - device name: POCO M4 Pro 5G
  - imsi: 001010000000101
---
Steps:
1. Goto [localhost:9999](http://localhost:9999/)
2. Enter credentials <br> 
  username: `admin` <br>
  password: `1423`
3. Select device `001010000000101`
4. Click on edit button in the top right corner of the popup 
5. look for Slice configuration section, click on the SD textbox, enter the configured slice (111111, in our case)
6. Now unlock phone, goto Setting > SiIM cards & mobile networks section 
7. You should see SIM 1 as Test Network, click on it.
8. Click on Mobile networks, click on Automatically select network
9. You should see a pop up asking if you want to choose network manually, select Next, 
10. Then it will ask if you want to disconnect from current network, select yes 
11. Then it will ask if you want to turn off mobile network, selecl yes 
12. It should now be in searching mode, once done it will list some networks.
13. If the gNB and SDR device are working you will see srsRAN 5G or Gradient 5G. Select either one.
14. You should be connected now if not then good luck and happy debugging.    

# Access monitoring 
1. Go to [http://localhost:3300](http://localhost:3300)
2. Select Home 

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