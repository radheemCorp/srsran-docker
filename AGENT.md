# Agent Notes for docker-srsran

This repo runs a ZMQ-based srsRAN Project gNB + srsUE with Open5GS core and OSC Near-RT RIC. Use the scripts below for deploy/undeploy, and keep configs aligned with the existing ZMQ bridge topology and RIC network.

## Deployment Orchestration

- Network setup (macvlan/bridge): run `scripts/net_manage.sh init` before any deployment.
- Start/stop components: use `scripts/manage.sh start|stop {ric|gnb|ue|monitoring|all}`.
- Default `DEPLOY_TYPE` is `zmq` (bridge + UE containers). UHD is available but not default.

## Known Network/IP Conventions

- Open5GS AMF: `10.53.1.2:38412`
- gNB N2 bind: `10.53.1.3`
- gNB N3: `10.10.3.231`
- ZMQ bridge IP: `10.10.3.236`
- RIC network: `10.0.2.0/24`, RIC IP: `10.0.2.15`, gNB E2 bind: `10.0.2.25`

## ZMQ RF Defaults

- Sample rate: `23.04e6`
- Band 3, 20 MHz, SCS 15 kHz (106 PRBs)
- UE ZMQ config is generated from `ue/ue1/config/generate_ue_conf.py` and expects matching RF params.

## RIC / xApp Notes

- E2 service models are enabled in gNB ZMQ configs via `e2` block.
- Example xApps live in `oran-sc-ric/xApps/python/` and use KPM/RC modules.
- RIC E2 reconnect backoff is ~60s after disconnect.

## Closed-Loop Mobility Work

- Implement multi-cell ZMQ gNB with two PCIs on a single carrier if supported by srsRAN config schema.
- Use GNU Radio ZMQ channel emulator for dual-cell path loss sweep.
- Use KPM metrics `RSRP`/`RSRQ` (UE-level) and RC handover control in a custom xApp.
