# srsUE ↔ gNB connection attempts

This document records all approaches attempted to make `srsue` attach to the running gNB and get a PDU session via Open5GS.

- Created deployment plan and initial Docker Compose in `srsue/` (tracks/fresh-ue/plan.md).
- Examined repository: `srsue/config/` scripts (`start_ue.sh`, `wrapper.sh`, `add_route.sh`, `generate_ue_conf.py`) and gNB/Open5GS compose in `srsRAN_Project/gnb-zmq`.
- Tried to build a local `srsue` image via a `Dockerfile` (build produced missing binary and missing tools); abandoned due to long build/debug time.
- Switched to prebuilt image `ghcr.io/sulaimanalmani/srsranzmq/srsue:v1.1` to iterate faster.
- Adjusted container entrypoint/command to run `/srsran/config/wrapper.sh` (matches k8s manifest behavior) and made container `privileged` with `NET_ADMIN` caps.
- Mounted `./config` into container and modified entrypoint logic to avoid editing read-only mounts (copy to `/tmp` before editing).
- Created MACVLAN network `n3br` and attached `srsue` to it with static IP `10.10.3.232`; also connected to `ran` network (10.53.1.0/24).
- Generated `/tmp/ue_1.conf` via `generate_ue_conf.py` and started UE with `/srsran/config/start_ue.sh 1`.
- Observed srsUE ZMQ sockets bind/listen on `10.10.3.232:2101` (srsUE process running) but UE stuck at "Attaching UE...".
- Inspected `ip netns` inside container: `ue0`/`ue1` present but no `tun_srsue` device created by srsUE.
- Ran `add_route.sh` — it failed with "Error: Nexthop has invalid gateway." (script used gateway `10.41.0.1`).
- Verified Open5GS subscriber DB (`project-config/subscriber_db.csv`) contains subscriber rows including IMSI `001010000000001`/`...002` with matching K/OPC values.
- Checked `gnb_zmq.yml` gNB config: `cu_cp.amf.addr` set to `10.53.1.2` (Open5GS) and `ru_sdr.device_args` ports configured for ZMQ external bridge.
- Experimented by temporarily changing `generate_ue_conf.py` to bind srsUE directly to gNB ZMQ endpoints (10.53.1.3:2000 / 10.53.1.6:2001) — that failed with "Cannot assign requested address" because UE cannot bind to gNB IP.
- Restored generator to original behavior (bind to UE macvlan IP `10.10.3.232` and per-UE ports 2101/2201).
- Manually created `tun_srsue` inside the container, moved it into `ue1` netns, and brought it up:
  - `ip tuntap add dev tun_srsue mode tun`
  - `ip link set tun_srsue netns ue1`
  - `ip netns exec ue1 ip link set tun_srsue up`
- Queried Open5GS runtime inside `open5gs_5gc`: environment shows `UE_IP_RANGE=10.41.0.0/24`, `UE_GATEWAY_IP=10.41.0.1`, `UPF_ADVERTISE_IP=10.53.1.2`.
- Assigned UE-side IP `10.41.0.2/24` to `tun_srsue` and added default route via `10.41.0.1` inside `ue1` netns.
- Confirmed `tun_srsue` has `10.41.0.2/24` and default route via `10.41.0.1` (route shows `linkdown` which is expected for point-to-point tun).
- Checked gNB/Open5GS logs for Registration/NGAP; Open5GS shows PDU session/NSSF services up but no matching RegistrationRequest for the UE (gnb logs lacked IMSI lines).

Next steps to try (remaining):

- Continue monitoring `/tmp/ue1.log`, gNB logs (`gnb-storage/gnb.log`), and Open5GS logs for RegistrationRequest entries.
- If NGAP RegistrationRequest is missing, ensure gNB actually receives uplink NAS from srsUE (check gNB ngap pcap output or gNB logs for RA/NGAP messages).
- Automate `tun_srsue` creation and route add in `start_ue.sh` (so netns + tun are present before srsUE attaches).
- If gNB → AMF connectivity issues persist, validate container `ran` network firewall rules and that gNB can reach `10.53.1.2:38412` (AMF NGAP port).
- Optionally enable more verbose logs on srsUE/gnb/5gc (increase log levels) and capture NGAP PCAPs for packet-level triage.

Record maintained by Copilot — ask to add specific logs or to apply the automation change.
