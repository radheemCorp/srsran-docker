# Multi-UE in Separate Docker Containers Plan

## Goal
Run 2 UEs simultaneously in 2 separate Docker containers:
- UE1 from `ue1`
- UE2 from `ue2`
Both attach to the same gNB/Open5GS deployment and pass user-plane traffic.

## Current status
- Multi-UE workspace is now under `external_ue/`:
  - `external_ue/ue1`
  - `external_ue/ue2`
  - `external_ue/zmq_bridge`
- `ue2/docker-compose.yaml` updated to avoid collision with UE1:
  - `container_name: srsran_ue_external_2`
  - `ipv4_address: 10.10.3.235`
- `ue1` remains on `10.10.3.234`.
- Added dedicated bridge stack: `external_ue/zmq_bridge/` with bridge IP `10.10.3.236`.
- UE config generators in both `external_ue/ue1` and `external_ue/ue2` support dynamic modes:
  - `direct` (single UE)
  - `bridge` (multi-UE, dynamic up to N UEs)
- All three compose stacks now use a shared external Docker network `ue_n3` to avoid overlapping macvlan subnet errors.
- Added `.env` files to all three directories for reproducible defaults:
  - `external_ue/ue1/.env`
  - `external_ue/ue2/.env`
  - `external_ue/zmq_bridge/.env`

Observed runtime behavior:
- UE console can remain on `Attaching UE...` even when core logs show success.
- AMF/SMF logs confirmed simultaneous success for both UEs:
  - `imsi-001010000000001` -> `10.41.0.3`
  - `imsi-001010000000002` -> `10.41.0.2`
- Frequent gNB restarts cause `connection refused` events in AMF and can interrupt active UE sessions.

Latest finding:
- UEs stuck at `Attaching UE...` because bridge uplink sockets were bound incorrectly on bridge IP.
- Fix applied: bridge now actively connects to each UE uplink endpoint by UE IP (`10.10.3.<base+ue_id>:210X`) and listens on bridge downlink ports (`220X`).
- gNB<->bridge sockets are healthy (`2000/2001`) and both UE sockets are established after fix.
- Bridge startup log lines
  - `/root/.gnuradio/prefs/vmcircbuf_default_factory: No such file or directory`
  - `vmcircbuf_createfilemapping: createfilemapping is not available`
  are expected GNU Radio fallback messages in this container and are non-fatal.

Additional finding:
- Running bridge with `NUM_UES=10` and no UE filter causes repeated `SYN-SENT` to non-existent UE IPs (`.237-.243`).
- This adds noise and can make troubleshooting harder.
- Fix applied: bridge now supports `UE_IDS` filter (for example `UE_IDS=1,2`) while still keeping dynamic support up to 10 UEs.

Current issue under investigation:
- Resolved in latest run after clean restart sequence.
- Both UE1 and UE2 successfully attached via bridge with separate IMSIs and received PDU IPs:
  - UE1 -> `10.41.0.3`
  - UE2 -> `10.41.0.2`
- Bridge sessions confirmed ESTAB for:
  - gNB<->bridge `2000/2001`
  - bridge<->UE1 `2101/2201`
  - bridge<->UE2 `2102/2202`

## Important design constraint
With current direct ZMQ setup (`gNB 2000/2001` directly paired to one UE endpoint), only one UE can be active at a time.

To support 2 simultaneous UEs with one gNB, add a ZMQ fan-in/fan-out bridge (multiplexer) between gNB and UEs.

---

## Target architecture for 2 simultaneous UEs

1. gNB keeps one base ZMQ pair (`2000/2001`) toward the bridge.
2. Bridge maps each UE to a unique port pair:
   - UE1: `2101/2201`
   - UE2: `2102/2202`
3. UE containers use unique IMSIs/subscribers:
   - UE1 -> `imsi ...001`
   - UE2 -> `imsi ...002`

Dynamic scaling model:
- Reserve UE uplink ports: `2101..2110` for UE1..UE10
- Reserve UE downlink ports: `2201..2210` for UE1..UE10
- Bridge is started once with `NUM_UES=10` and can serve up to 10 UEs without config rewrite.
- Bridge UE IP mapping is parameterized by `UE_IP_BASE` (default `233`):
  - UE1 -> `10.10.3.234`
  - UE2 -> `10.10.3.235`
  - ...
  - UE10 -> `10.10.3.243`
- Active UE set is parameterized by `UE_IDS` (default currently `1,2` in compose for this phase).

---

## Required configuration updates

### A) gNB (`configs/srsRAN/srsran-gnb/config/srsran-gnb.yaml`)
- Keep `tx_port=tcp://10.10.3.231:2000`.
- Set `rx_port=tcp://10.10.3.236:2001` (bridge endpoint).

### B) Bridge (new runtime component)
- Run one bridge process reachable from gNB and both UE containers.
- Bridge should map:
  - gNB downlink stream -> UE1/UE2 downlink sockets
  - UE1/UE2 uplink sockets -> summed/forwarded uplink stream to gNB
- Implemented as `zmq_bridge/config/zmq_bridge.py` with runtime `--num-ues`.
- Containerized in `zmq_bridge/docker-compose.yaml`.

### C) UE1 (`external_ue/ue1`)
- Start UE with UE number `1`.
- Set mode: `UE_ZMQ_MODE=bridge`
- ZMQ ports are UE1-specific:
  - UE1 tx bind: `*:2101`
  - UE1 rx connect: `10.10.3.236:2201`

### D) UE2 (`external_ue/ue2`)
- Start UE with UE number `2`.
- ZMQ ports should be UE2-specific:
  - UE2 tx bind: `*:2102`
  - UE2 rx connect: `10.10.3.236:2202`

### E) Open5GS
- Keep single SMF/UPF mode for deterministic debugging.
- Ensure both subscribers exist and match UE configs:
  - `001010000000001`
  - `001010000000002`
  - DNN `internet`, slice `sst=1/sd=000001`.

---

## Bring-up sequence

1. Start Open5GS (single SMF/UPF) and verify healthy.
2. Start gNB with bridge-facing ZMQ config.
3. Create shared Docker macvlan network once on host (if missing):
   - `docker network create -d macvlan --subnet=10.10.3.0/24 --gateway=10.10.3.254 -o parent=n3br ue_n3`
4. Start bridge container from `external_ue/zmq_bridge`:
   - `docker compose up -d`
5. Start UE1 container (`external_ue/ue1`) and run:
   - `UE_ZMQ_MODE=bridge ZMQ_BRIDGE_IP=10.10.3.236 /srsran/config/start_ue.sh 1`
6. Start UE2 container (`external_ue/ue2`) and run:
   - `UE_ZMQ_MODE=bridge ZMQ_BRIDGE_IP=10.10.3.236 /srsran/config/start_ue.sh 2`
7. Validate both UEs have:
   - successful attach
   - `tun_srsue`
   - default route via tunnel
    - DNS configured in `/etc/netns/ueX/resolv.conf`.

Important operational rule:
- Avoid restarting gNB while UEs are attaching/testing.
- Start gNB once, then bridge, then UEs.
- If gNB is restarted, restart both UE processes afterward.

---

## Validation checklist (both UEs)

- `ip netns exec ueX ip a`
- `ip netns exec ueX ip route`
- `ip netns exec ueX ping -c3 10.41.0.1`
- `ip netns exec ueX ping -c3 8.8.8.8`
- `ip netns exec ueX ping -c3 google.com`

Authoritative attach validation (use these, not UE console text alone):
- AMF log: `Registration complete` for both IMSIs.
- SMF log: session added + UE IPv4 assigned for both IMSIs.
- UE namespace: `ip netns exec ueX ip a` shows `tun_srsue` with `10.41.x.x`.

Latest validation snapshot:
- UE1:
  - default route via `tun_srsue`: OK
  - `ping 8.8.8.8`: OK
  - `ping 1.1.1.1`: OK
  - `ping google.com`: OK
- UE2:
  - default route via `tun_srsue`: OK
  - `ping 8.8.8.8`: OK
  - `ping google.com`: OK

Bridge checks:
- `docker exec -it srsran_zmq_bridge ss -ltnp | egrep '2001|210[1-9]|2110|220[1-9]|2210'`
- Expect bridge listening on `2001` and all configured UE port pairs.
- `docker exec -it srsran_zmq_bridge ss -tnp`
- Expect ESTAB sessions:
  - bridge -> gNB `:2000`
  - gNB -> bridge `:2001`
  - bridge -> UE1 `:2101`
  - bridge -> UE2 `:2102`
  - UE1 -> bridge `:2201`
  - UE2 -> bridge `:2202`
- No persistent `SYN-SENT` sessions to unused UE IDs when `UE_IDS` is set.

## Missing steps discovered during implementation

1. Subscriber provisioning must match generated UE identities before attach
- Current UE scripts generate:
  - UE1 IMSI `001010000000001`
  - UE2 IMSI `001010000000002`
  - `k = 465B5CE8B199B49FAA5F0A2EE238A6BC`
  - `opc = E8ED289DEBA952E4283B54E88E6183CA`
- If `project-config/subscriber_db.csv` does not match these values, AMF will reject registration.
- After editing subscriber CSV, recreate 5GC so subscribers are reloaded:
  - `cd /home/radr/tuilm/srsran-build && docker compose up -d --force-recreate 5gc`

2. `docker compose up` for UE containers does not start srsUE attach automatically
- UE containers start `wrapper.sh` and remain idle.
- You must start UE processes manually in each container:
  - `docker exec srsran_ue_host  sh -lc 'UE_ZMQ_MODE=bridge ZMQ_BRIDGE_IP=10.10.3.236 /srsran/config/start_ue.sh 1'`
  - `docker exec srsran_ue_host2 sh -lc 'UE_ZMQ_MODE=bridge ZMQ_BRIDGE_IP=10.10.3.236 /srsran/config/start_ue.sh 2'`

3. UE container restarts can leave stale netns references
- Symptom:
  - `Error: Peer netns reference is invalid`
- Recovery before re-running `start_ue.sh`:
  - `docker exec srsran_ue_host  sh -lc 'pkill -f srsue || true; ip netns del ue1 >/dev/null 2>&1 || true; rm -f /run/netns/ue1'`
  - `docker exec srsran_ue_host2 sh -lc 'pkill -f srsue || true; ip netns del ue2 >/dev/null 2>&1 || true; rm -f /run/netns/ue2'`

4. gNB logs are file-based in this setup
- `docker compose logs gnb` can be empty while gNB is healthy.
- Use:
  - `docker exec srsran_gnb sh -lc 'tail -f /tmp/gnb.log'`
- Check for:
  - `InitialUEMessage`
  - `DownlinkNASTransport`
  - absence of immediate `UEContextReleaseCommand`

5. Deterministic restart order (after failures)
- Use this order to avoid stale ZMQ or partial control-plane state:
  1. Ensure 5GC healthy
  2. Start/restart gNB once
  3. Start/restart bridge
  4. Start UE1 process, then UE2 process

Network captures during test:
- gNB N3: `udp port 2152`
- UPF N3: `udp port 2152`
- UPF `ogstun`: ICMP from both UE IPs

---

## Common pitfalls for multi-container UE setup

- Both compose stacks using same `container_name` or same UE IP.
- Running direct gNB<->UE ZMQ mode and expecting 2 simultaneous UEs.
- Reusing same UE number/IMSI in both containers.
- Stale ZMQ session after abrupt UE restart (may require gNB restart).
- Forgetting `UE_ZMQ_MODE=bridge` in UE containers (then UE tries direct mode).
- Creating separate compose-managed macvlan networks with same subnet (`10.10.3.0/24`) causing overlap errors.
- Bridge connecting to wrong UE IP mapping (`UE_IP_BASE`) causing attach to stall at PHY attach phase.

## Environment files

`external_ue/ue1/.env`
- `GNB_IP=10.10.3.231`
- `ZMQ_BRIDGE_IP=10.10.3.236`
- `UE_ZMQ_MODE=bridge`
- `UE_DNS1=1.1.1.1`
- `UE_DNS2=8.8.8.8`

`external_ue/ue2/.env`
- `GNB_IP=10.10.3.231`
- `ZMQ_BRIDGE_IP=10.10.3.236`
- `UE_ZMQ_MODE=bridge`
- `UE_DNS1=1.1.1.1`
- `UE_DNS2=8.8.8.8`

`external_ue/zmq_bridge/.env`
- `NUM_UES=10`
- `UE_IDS=1,2`
- `GNB_IP=10.10.3.231`
- `BRIDGE_IP=10.10.3.236`
- `UE_IP_BASE=233`
