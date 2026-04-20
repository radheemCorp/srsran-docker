# Difference Report: current repo vs investigations/old-samples

## Compared files
- Old samples:
  - `investigations/old-samples/ue_generate_conf.py`
  - `investigations/old-samples/gnb.yaml`

- Current repo config:
  - `external_ue/ue1/config/generate_ue_conf.py`
  - `external_ue/ue2/config/generate_ue_conf.py`
  - `external_ue/ue1/docker-compose.yaml`
  - `external_ue/ue2/docker-compose.yaml`
  - `external_ue/zmq_bridge/docker-compose.yaml`
  - `external_ue/ue1/.env`
  - `external_ue/ue2/.env`
  - `project-config/gnb/gnb_zmq.yml`
  - `project-config/gnb/gnb_compose_config.yml`
  - `docker-compose.yml`

## High-level differences

### 1. Network architecture
- Old sample is a flat example using a single `10.10.3.x` domain for both gNB and UE traffic.
- Current repo is Docker-native and segmented across multiple networks:
  - `ran` for N2/AMF signaling (`10.53.1.x`)
  - `n3br` for RF/ZMQ user-plane traffic (`10.10.3.x`)
  - `ric_network` for E2/RIC (`10.0.2.x`)
  - plus `metrics` for monitoring and `n2network` for secondary signaling.

### 2. UE ZMQ topology
- Old sample UE config uses:
  - `tx_port=tcp://10.10.3.232:210X`
  - `rx_port=tcp://10.10.3.232:220X`
  - A single shared host/bridge endpoint at `10.10.3.232`
- Current repo uses a ZMQ bridge with:
  - gNB TX -> bridge RX at `tcp://10.10.3.236:2001`
  - gNB RX <- bridge TX at `tcp://10.10.3.231:2000`
  - UE-specific uplink endpoints on UE IPs:
    - UE1: `10.10.3.234:2101`
    - UE2: `10.10.3.235:2102`
  - UE downlink connects to bridge:
    - UE1: `10.10.3.236:2201`
    - UE2: `10.10.3.236:2202`

### 3. Static IP / netns behavior
- Old sample always writes `netns = ueX` in the generated UE config.
- Current repo uses `UE_USE_NETNS=true` through environment and compose on both UEs.
- Current repo also uses static `n3br` container IPs for UE1 and UE2.

### 4. APN/DNN and subscriber policy
- Old sample uses `apn = internet`.
- Current repo uses `apn = srsapn`.
- Current Open5GS subscriber data in the repo is already configured for `srsapn`.

### 5. gNB and core endpoints
- Old sample gNB config uses:
  - `amf.addr = 10.10.3.200`
  - `bind_addr = 10.10.3.231`
  - `e2.addr = 10.10.3.254`
  - `e2.bind_addr = 10.10.3.231`
- Current repo gNB config uses:
  - `amf.addr = 10.53.1.2`
  - `bind_addr = 10.53.1.3`
  - `e2.addr = 10.0.2.10`
  - `e2.bind_addr = 10.0.2.30`
- Current repo explicitly separates AMF/N2 traffic from RIC/E2 traffic.

### 6. Docker integration
- Old samples are standalone YAML examples for manual gNB/UE config.
- Current repo is a full Docker Compose deployment with separate service stacks for:
  - gNB
  - Open5GS core
  - UE1
  - UE2
  - ZMQ bridge
- Current repo includes `.env` files, macvlan/bridge network usage, and explicit compose network attachments.

## Practical impact
- The old sample is useful as a conceptual template, but it is not directly compatible with the current dockerized multi-container setup.
- The current repo is designed for multi-UE using a ZMQ bridge, static UE IPs, and network namespace isolation.
- The current repo also aligns APN/DNN (`srsapn`) with actual Open5GS subscriber provisioning.

## Recommendation
- Treat the old samples as legacy examples, not as the current runtime config.
- Use the current repo’s `project-config/gnb/gnb_zmq.yml` and `external_ue/*` compose/config files for actual deployment.
- If you want to keep a comparable sample, port the old sample’s APN and network settings into the current network segmentation model, rather than trying to use the old sample as-is.
