# srsRAN project 
## Dockerfile Open5gs + gNB
1. Add `ARG ENABLE_DPDK=On` after `ARG DPDK_VERSION=24.11.2` to switch on DPDK support in the build (required for gNB-UHD)
2. Add `/src/docker/scripts/install_dependencies.sh extra && \` to the build dependencies step install zmq dependencies (required for gNB-ZMQ) 
3. Change `-DENABLE_DPDK=On` to `-DENABLE_DPDK=${ENABLE_DPDK}` in the CMake call
4. Add `libzmq5 libdw1 libdwarf1 libelf1 libdpdk-dev` to the runtime `apt-get install` line 

## Docker compose updates for image build
- Added `EXTRA_CMAKE_ARGS` build argument to the gNB service in `srsRAN_Project/docker/docker-compose.yml` to enable ZMQ, UHD, and export features and disable MKL and DPDK 
    - MKL is disabled to avoid the need for additional dependencies and to ensure compatibility with the gNB-ZMQ deployment which does not use MKL
    - DPDK is disabled by default to avoid potential issues with running in non-privileged mode, but can be enabled by setting `EXTRA_CMAKE_ARGS` to include `-DENABLE_DPDK=On` if DPDK support is desired and the environment allows for privileged containers

## Docker compose updates for ZMQ deployment
- `NET_ADMIN` capability
- Using pre-built `rptestbed/` images
- `./project-config/` directory references
- Volume mounts for `subscriber_db.csv` and `open5gs-5gc.yml.in`
- `expose` for SCTP/UDP instead of port publication

## Docker compose updates for UHD deployment
- `network_mode: host` on gNB
- `NET_ADMIN` capability
- Using pre-built `rptestbed/` images
- `./project-config/` directory references
- Volume mounts for `subscriber_db.csv` and `open5gs-5gc.yml.in`
- `expose` for SCTP/UDP instead of port publication

## Subscriber db update
- added apn field to the subscriber_db.csv file and updated srsRAN_Project/docker/open5gs/add_users.py to include the apn field when generating users 

## enable rlc metrics for e2 agent
- reference : oran-sc-ric/e2-agents/srsRAN/gnb_zmq.yaml
- add the following to the pcap section of the srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yaml file to enable RLC metrics for the E2 agent
```
pcap:
  mac_enable: false                 # Set to true to enable MAC-layer PCAPs.
  mac_filename: /tmp/gnb_mac.pcap   # Path where the MAC PCAP is stored.
  ngap_enable: false                # Set to true to enable NGAP PCAPs.
  ngap_filename: /tmp/gnb_ngap.pcap # Path where the NGAP PCAP is stored.
  e2ap_enable: true                 # Set to true to enable E2AP PCAPs.
  e2ap_du_filename: /tmp/gnb_du_e2ap.pcap       # Path where the DU E2AP PCAP is stored.
  e2ap_cu_cp_filename: /tmp/gnb_cu_cp_e2ap.pcap # Path where the CU-CP E2AP PCAP is stored.
  e2ap_cu_up_filename: /tmp/gnb_cu_up_e2ap.pcap # Path where the CU-UP E2AP PCAP is stored.
```

- add the following to the metrics section of the srsRAN_Project/gnb-zmq/project-config/gnb/gnb_compose_config.yml file to enable RLC metrics for the E2 agent
```
metrics:
  autostart_stdout_metrics: true
  enable_json: true
  layers:
    enable_rlc: true
    enable_mac: true
    enable_sched: true
  periodicity:
    du_report_period: 1000
    cu_up_report_period: 1000
    cu_cp_report_period: 1000
  
  layers:
    enable_ru: false
    enable_sched: true
    enable_rlc: true
    enable_mac: true
    enable_pdcp: false
    enable_du_low: false
```



# Notes
- The original srsRAN porject dockerfile is available at [srsRAN_Project/docker/Dockerfile.srsran-original](srsRAN_Project/docker/Dockerfile.srsran-original)
- The original srsRAN porject docker-compose is available at [srsRAN_Project/docker/srsran-original-docker-compose.yml](srsRAN_Project/docker/srsran-original-docker-compose.yml)
- The gnb-zmq and gnb-uhd doncker compose directories were sperated to manage the differing configuration needs of each deployment and are available at [srsRAN_Project/gnb-zmq/docker-compose.yml](srsRAN_Project/gnb-zmq/docker-compose.yml) and [srsRAN_Project/gnb-uhd/docker-compose.yml](srsRAN_Project/gnb-uhd/docker-compose.yml) respectively 