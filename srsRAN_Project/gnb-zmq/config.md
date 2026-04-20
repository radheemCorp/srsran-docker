# ZMQ gNB and UE Configuration Guide

This document explains how the srsRAN Project gNB ZMQ configuration and the UE ZMQ configuration connect, with exact values shown and formula reasoning for why they match.

## 1. Overview

The gNB configuration defines a ZMQ-based RF frontend and the 5G NR cell parameters. The UE configuration defines a ZMQ RF frontend and NR radio settings that must align with the gNB.

For ZMQ RF, the two sides must match:

- gNB `ru_sdr.device_driver = zmq`
- UE `[rf].device_name = zmq`
- gNB `ru_sdr.device_args` must connect to the same endpoints used by UE
- gNB sample rate and UE `srate` must be identical
- gNB NR band and bandwidth must match UE `rat.nr` band and PRB settings

## 2. gNB configuration values

From `project-config/gnb/gnb_zmq.yml`:

- `ru_sdr.device_driver: zmq`
- `ru_sdr.device_args: tx_port=tcp://10.10.3.231:2000,rx_port=tcp://10.10.3.236:2001,base_srate=23.04e6`
- `srate: 23.04`
- `cell_cfg.band: 3`
- `cell_cfg.channel_bandwidth_MHz: 20`
- `cell_cfg.common_scs: 15`
- `cell_cfg.dl_arfcn: 368500`
- `cell_cfg.plmn: "00101"`
- `cell_cfg.tac: 7`

This means the gNB is configured to use a 20 MHz NR cell on band 3 with 15 kHz subcarrier spacing, and to exchange samples through ZMQ sockets at 23.04 MHz sample rate.

## 3. UE configuration values

From `external_ue/ue1/config/generate_ue_conf.py` template:

- `[rf].device_name = zmq`
- `[rf].device_args = tx_port={tx_port},rx_port={rx_port},base_srate=23.04e6`
- `[rf].srate = 23.04e6`
- `[rat.nr].bands = 3`
- `[rat.nr].max_nof_prb = 106`
- `[rat.nr].nof_prb = 106`

The template also configures UE radio gains and UE identity values, but the most important values for RF matching are the ZMQ endpoints and the NR carrier settings.

## 4. ZMQ endpoint mapping

### gNB side

- gNB TX (downlink) binds to: `tcp://10.10.3.231:2000`
- gNB RX (uplink) connects to: `tcp://10.10.3.236:2001`

### UE side behavior

The UE generator can use either:

- `direct` mode:
  - UE TX -> gNB RX at `tcp://<GNB_IP>:2000`
  - UE RX <- gNB TX at `tcp://<UE_BIND_IP>:2001`
- `bridge` mode:
  - UE TX -> bridge RX at `tcp://<UE_BIND_IP>:2100+ue_number`
  - UE RX <- bridge TX at `tcp://<BRIDGE_IP>:2200+ue_number`

For the repo's `gnb_zmq.yml` external bridge topology, the relevant mapping is:

- gNB expects to send DL samples from `tcp://10.10.3.231:2000`
- gNB expects to receive UL samples from `tcp://10.10.3.236:2001`
- UE must therefore be configured so its transmit socket eventually reaches `10.10.3.236:2001` and its receive socket is a source for `10.10.3.231:2000` through the bridge.

## 5. Why 20 MHz matches 106 PRBs

For 5G NR in FR1 with 15 kHz subcarrier spacing:

- Each PRB comprises `12` subcarriers.
- A 20 MHz carrier contains `106` PRBs at 15 kHz.

The formula is:

- `bandwidth_hz = channel_bandwidth_MHz * 1e6`
- `subcarrier_spacing_hz = common_scs * 1000`
- `resource_block_spacing_hz = 12 * subcarrier_spacing_hz`
- `approximate_prbs = bandwidth_hz / resource_block_spacing_hz`

Plugging in the values:

- `bandwidth_hz = 20 * 1e6 = 20,000,000`
- `subcarrier_spacing_hz = 15 * 1000 = 15,000`
- `resource_block_spacing_hz = 12 * 15,000 = 180,000`
- `approximate_prbs = 20,000,000 / 180,000 ≈ 111.11`

NR standard tables allocate `106` PRBs for 20 MHz at 15 kHz, after accounting for guard bands and bandwidth occupancy.

Therefore:

- gNB `cell_cfg.channel_bandwidth_MHz: 20` and `common_scs: 15` implies a 20 MHz carrier with 106 usable PRBs.
- UE `max_nof_prb = 106` and `nof_prb = 106` means the UE is configured to use the full 20 MHz carrier.

## 6. Exact matching values summary

| Concept | gNB value | UE value | Why it matters |
|---|---|---|---|
| ZMQ driver | `ru_sdr.device_driver = zmq` | `[rf].device_name = zmq` | Both sides must use the same transport driver |
| Sample rate | `srate = 23.04` | `[rf].srate = 23.04e6` | Both sides must use identical sample rate |
| ZMQ TX endpoint | `tx_port=tcp://10.10.3.231:2000` | UE RX should source from gNB TX through the bridge | DL samples must flow to UE |
| ZMQ RX endpoint | `rx_port=tcp://10.10.3.236:2001` | UE TX should send to bridge RX that reaches gNB RX | UL samples must flow to gNB |
| NR band | `band: 3` | `[rat.nr].bands = 3` | Same RF frequency band |
| Bandwidth | `channel_bandwidth_MHz: 20` | `max_nof_prb = 106`, `nof_prb = 106` | Same usable NR carrier bandwidth |
| Subcarrier spacing | `common_scs: 15` | implicit by PRB count and 15 kHz relationship | Same NR numerology |

## 7. Practical advice

- If the gNB log shows ZMQ RX waiting for samples, verify the bridge or UE is publishing to `tcp://10.10.3.236:2001`.
- Keep `base_srate=23.04e6` and `srate=23.04` aligned exactly.
- Keep the UE `band` and `PRB` settings consistent with the gNB band and bandwidth.
- Use the `sample_gnb_zmq.yaml` comments as a template for local testing, then apply the repo-specific IPs for bridge mode.
