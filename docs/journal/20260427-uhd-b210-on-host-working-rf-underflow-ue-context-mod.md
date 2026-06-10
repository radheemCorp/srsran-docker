# 20260427 — UHD B210 on host: working setup, RF underflow → repeated UE context release

- **Date:** 2026-04-27
- **Area:** SDR / RAN
- **Status:** Mitigated (happy-path works; RF underflow + UE context churn persist)
- **Components:** USRP B210, srsran_gnb (network mode host), open5gs_5gc, Android UE

> Source: `tracks/successful_uhd_on_host/README.md` (+ gnb.log, 5gc.log).

## Summary
- A working over-the-air setup: B210 + srsRAN gNB in **host network mode**, Open5GS in a
  privileged container on its own Docker network with a static IP, a real Android UE
  attaching to slice SST 1 / SD 111111.
- Two known issues remain: **RF underflow/late** persists despite the performance script,
  and that RF instability triggers **repeated UE context modification / PDU session
  release** (the core tears the session down when signaling/ACKs are missed).

## Context / setup
- **Slice encoding mismatch is intentional:** Open5GS expresses SD in **hex** (`111111`),
  the gNB expresses it in **decimal** (`1118481` = 0x111111). The UE requests SST 1 /
  SD 111111.
- gNB runs `network_mode: host` (to avoid Docker network juggling); Open5GS runs
  privileged on its own network with a static IP the gNB targets.
- Open5GS `add_users.py` does **not** set the UE slice from the subscriber CSV — SST
  defaults to 1 and SD is empty, so **SD is set by hand via the Open5GS WebUI**
  (`localhost:9999` → edit subscriber → slice configuration). Improving `add_users.py` to
  set the S-NSSAI from CSV is a noted TODO.
- Subscribers: `sub1 001010000000101 … 10.45.0.2`, `sub2 001010000000102 … 10.45.0.3`.

## Investigation / what was determined
- RF real-time failures persist even after `srsRAN_Project/scripts/srsran_performance`:
  ```
  [RF] [W] Real-time failure in RF: underflow
  [RF] [W] Real-time failure in RF: late
  ```
- The release chain (from `gnb.log`) — RF failure → missed signaling/ACK → core releases:
  ```
  NGAP : Rx PDU ...: PDUSessionResourceReleaseCommand
  CU-CP-E1 : BearerContextReleaseCommand ; GTPU : Tunnel removed. teid=0x000001
  CU-UP : ue=1: Disconnecting PDU session with psi=10
  CU-CP-F1 : UEContextModificationRequest/Response ; RRC : rrcReconfiguration
  ```
  i.e. dropped RRC Reconfiguration/keep-alive → AMF/SMF assume the link is lost → send
  `PDUSessionResourceReleaseCommand` → bearer/tunnel torn down → UE context modified.

## Root cause
- **RF underflow/late (host can't meet the radio's real-time deadlines)** is the prime
  mover; the repeated UE-context-modification / session release is a **downstream effect**
  of that RF instability, not an independent core bug.

## Resolution / workaround
- Works as a happy-path demo with the WebUI SD step. To stabilize the session, attack the
  RF timing (CPU isolation, USB power, frame buffers — see the SDR tuning entries).
- TODOs captured: teach `add_users.py` to set S-NSSAI (SST/SD) from the subscriber CSV so
  the manual WebUI step isn't needed.

## Lessons / gotchas
- **SD is hex in Open5GS, decimal in srsRAN** (`111111` ↔ `1118481`) — a frequent
  apparent "mismatch" that is actually correct.
- Open5GS `add_users.py` ignores CSV slice fields (SST→1, SD empty) — set SD in the WebUI
  or fix the script (this is the same provisioning gap that later bit the ZMQ slice-2 UEs).
- Repeated `UEContextModification` + `PDUSessionResourceRelease` under load usually means
  the **radio is dropping signaling**, not a core fault — fix RF timing first.

## References
- `tracks/successful_uhd_on_host/README.md`, `.../gnb-uhd/gnb-storage/gnb.log`, `.../5gc.log`.
- `srsRAN_Project/gnb-uhd/project-config/{subscriber_db.csv,open5gs-5gc.yml.in}`,
  `srsRAN_Project/docker/open5gs/add_users.py`.
- Related: [20260427-host-sdr-outgoing-packets-dropped.md](./20260427-host-sdr-outgoing-packets-dropped.md),
  [20260428-uhd-in-vm-rf-underflow-pcore-scheduling.md](./20260428-uhd-in-vm-rf-underflow-pcore-scheduling.md).
