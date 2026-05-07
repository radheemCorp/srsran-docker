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
- added apn field to the subscriber_db.csv file a dn updated srsRAN_Project/docker/open5gs/add_users.py to include the apn field when generating users 

# Notes
- The original srsRAN porject dockerfile is available at [srsRAN_Project/docker/Dockerfile.srsran-original](srsRAN_Project/docker/Dockerfile.srsran-original)
- The original srsRAN porject docker-compose is available at [srsRAN_Project/docker/srsran-original-docker-compose.yml](srsRAN_Project/docker/srsran-original-docker-compose.yml)
- The gnb-zmq and gnb-uhd doncker compose directories were sperated to manage the differing configuration needs of each deployment and are available at [srsRAN_Project/gnb-zmq/docker-compose.yml](srsRAN_Project/gnb-zmq/docker-compose.yml) and [srsRAN_Project/gnb-uhd/docker-compose.yml](srsRAN_Project/gnb-uhd/docker-compose.yml) respectively 