# srsRAN project 
## Dockerfile Open5gs + gNB
1. Add `ARG ENABLE_DPDK=On` after `ARG DPDK_VERSION=24.11.2` to switch on DPDK support in the build (required for gNB-UHD)
2. Add `/src/docker/scripts/install_dependencies.sh extra && \` to the build dependencies step install zmq dependencies (required for gNB-ZMQ) 
3. Change `-DENABLE_DPDK=On` to `-DENABLE_DPDK=${ENABLE_DPDK}` in the CMake call
4. Add `libzmq5 libdw1 libdwarf1 libelf1 libdpdk-dev` to the runtime `apt-get install` line 

## Docker compose updates
- `network_mode: host` on gNB
- `NET_ADMIN` capability
- Using pre-built `rptestbed/` images
- `./project-config/` directory references
- Volume mounts for `subscriber_db.csv` and `open5gs-5gc.yml.in`
- `expose` for SCTP/UDP instead of port publication

## Subscriber db update
- added apn field to the subscriber_db.csv file a dn updated srsRAN_Project/docker/open5gs/add_users.py to include the apn field when generating users 

