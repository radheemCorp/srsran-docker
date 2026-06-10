# Onboarding Guide — gNB + Open5GS + UHD B210

This document is a concise, runnable onboarding guide for bringing up the core (`Open5GS`), the gNB (`srsRAN`), and attaching a UHD B210 SDR. It documents the files used, exact commands to run, verification steps, troubleshooting notes, and a short journal of actions already performed in this workspace.

**Audience:** Engineers new to the repository who need to reproduce the gNB + 5GC + SDR setup.

---

**Files used and where to look**
- `srsRAN_Project/docker/docker-compose.yml` — primary compose to build and run `5gc` and `gnb` (run from `srsRAN_Project/docker`).
- `srsRAN_Project/docker/open5gs/open5gs.env` — environment file used by the `5gc` service (contains `SUBSCRIBER_DB`, `OPEN5GS_IP`, ...).
- `srsRAN_Project/docker/open5gs/subscriber_db.csv` — CSV file containing custom subscriber definitions used by `5gc`.
- `srsRAN_Project/docker/open5gs/open5gs-5gc.yml` / `open5gs-5gc.yml.in` — Open5GS config template used by the entrypoint.
- `srsRAN_Project/configs/gnb_zmq_external_ue.yml` — gNB runtime config; RU / AMF / ZMQ / cell parameters we use to attach the B210.
- `srsRAN_Project/configs/gnb_rf_b210_fdd_srsUE.yml` — example RU config for B210 (reference).
- `external_ue/host_ue_bridge/docker-compose.yaml` — ZMQ bridge service (used later for external UEs).
- `external_ue/host_ue1/docker-compose.yaml`, `external_ue/host_ue2/docker-compose.yaml` — example external UE containers.

Refer to these files to change IPs, IMSIs, or RF parameters.

---

Prerequisites (host)
- Linux host with Docker and Docker Compose plugin installed.
- `uhd` drivers & tools installed (verify with `uhd_find_devices`). See `FIND_UHD_DEVICE.md` for install notes.
- Host user in `docker` group or run `docker` commands with `sudo`.
- A host interface to act as macvlan parent (the repository uses a bridge named `n3br` by default). If you prefer, use an existing physical NIC (e.g. `eth0`) as parent for the `n3br` macvlan.

Quick checks before starting
```bash
uhd_find_devices        # confirm the B210 is visible (serial printed)
ip -br a show n3br      # check the host bridge; create it if missing
groups                  # ensure you are in the docker group or use sudo
```

Host network (create once)
1. Create/prepare the `n3br` bridge and the external `n3br` macvlan network. Replace `n3br` with an existing NIC if you prefer.

```bash
sudo ip link add n3br type bridge || true
sudo ip link set dev n3br up
sudo ip addr del 10.10.3.1/24 dev n3br || true
sudo ip addr add 10.10.3.254/24 dev n3br

docker network create -d macvlan \
  --subnet=10.10.3.0/24 \
  --gateway=10.10.3.254 \
  -o parent=n3br \
  n3br
```

If `n3br` already exists, Docker will report that — that is fine.

Prepare Open5GS & gNB configs (required)
1. Use the compose located at `srsRAN_Project/docker/docker-compose.yml`. Files referenced by that compose are expected relative to `srsRAN_Project/docker`.

```bash
# from repository root (one-time prep)
mkdir -p srsRAN_Project/docker/open5gs
cp srsRAN_Project/docker/open5gs/open5gs.env srsRAN_Project/docker/open5gs/open5gs.env
cp srsRAN_Project/docker/open5gs/subscriber_db.csv srsRAN_Project/docker/open5gs/subscriber_db.csv
# the entrypoint expects the template; ensure the .in file is present
cp srsRAN_Project/docker/open5gs/open5gs-5gc.yml srsRAN_Project/docker/open5gs/open5gs-5gc.yml.in
# place or verify gNB config referenced by the compose
mkdir -p srsRAN_Project/configs
cp srsRAN_Project/configs/gnb_zmq_external_ue.yml srsRAN_Project/configs/gnb_zmq_external_ue.yml
```

Notes:
- Edit `srsRAN_Project/docker/open5gs/open5gs.env` if you need to change IPs (e.g. `OPEN5GS_IP`, `MONGODB_IP`, `UE_IP_BASE`).
- Do NOT mount a rendered `/open5gs/open5gs-5gc.yml` into the container; the image entrypoint performs `envsubst < open5gs-5gc.yml.in > open5gs-5gc.yml` so the `.in` template must be present and writable inside the image or build context.

Troubleshooting Open5GS startup
- If `open5gs` exits immediately with a message about `open5gs-5gc.yml` being
  read-only, confirm you created `project-config/open5gs-5gc.yml.in` and that
  your `docker-compose.yml` does not mount a host file onto
  `/open5gs/open5gs-5gc.yml`.
- If you see `No nrf.sbi.address` in the logs, the generated configuration is
  likely malformed (often due to `envsubst` failing). Inspect the rendered
  file inside the running container:

```bash
docker compose exec 5gc cat /open5gs/open5gs-5gc.yml
```

  If the file is missing or incomplete, check `docker compose logs 5gc` for the
  envsubst / permission error and ensure `project-config/open5gs.env` exists and
  contains the expected variables.


Building images
- Use the compose under `srsRAN_Project/docker` (this keeps Dockerfile contexts intact).

```bash
# from repository root
cd srsRAN_Project/docker
docker compose build 5gc gnb
```

Notes:
- The `gnb` build uses build args such as `ENABLE_ZEROMQ=On` / `ENABLE_UHD=On` in the override compose.
- If you change `open5gs` subscriber CSV, rebuild the `5gc` image so `subscriber_db.csv` is copied into the image (or set `SUBSCRIBER_DB` to a CSV path mounted into the container).

Published images (pushed to `rptestbed`)
- `rptestbed/open5gs:v2.7.0-ubuntu22.04-20260413`
  - Built with: `OPEN5GS_VERSION=v2.7.0`, `OS_VERSION=22.04` (see `srsRAN_Project/docker/docker-compose*.yml` build args)
  - Contains: Open5GS 5gc binaries, `subscriber_db.csv` (copied at build time), and the bundled webui.

- `rptestbed/srsran-gnb:ubuntu24.04-uhd-zeromq-20260413`
  - Built with: `OS_VERSION=24.04`, `EXTRA_CMAKE_ARGS` enabling `ZEROMQ` and `UHD` (the compose override used `-DENABLE_ZEROMQ=On -DENABLE_UHD=On -DENABLE_EXPORT=On -DENABLE_MKL=False -DENABLE_DPDK=Off`).
  - Drivers/features included: UHD (libuhd), ZeroMQ support; DPDK was disabled in this build. UHD version default in the Dockerfile is `4.7.0.0` unless overridden at build time.

Build config summary / drivers
- Open5GS image: `OPEN5GS_VERSION` controlled by the compose `OPEN5GS_VERSION` build arg (in our run we used `v2.7.0`) and the base OS is `ubuntu:22.04`.
- gNB image: built on `ubuntu:24.04` and compiled with `-DENABLE_UHD=On` and `-DENABLE_ZEROMQ=On` so the container includes UHD support for B210 (and ZMQ if you want to connect external UE containers). DPDK was disabled in the override used for this workspace.

PLMN and IMSI
- The test PLMN used by the default configs is `00101` (MCC=001, MNC=01). Android devices may show this as `001-01` or by the operator name broadcast by the gNB.


Adding custom subscribers to Open5GS
- We add `subscriber_db.csv` under `srsRAN_Project/docker/open5gs/` containing CSV rows with this format (name,imsi,key,op_type,op_or_opc,amf,qci,ip_alloc)

Example entries added for this workspace:
```
sub1,001010000000101,0C0A34601D4F07677303652C0462535B,opc,63BFA50EE6523365FF14C1F45F88737B,8000,9,10.45.1.2
sub2,001010000000102,0C0A34601D4F07677303652C0462535D,opc,63BFA50EE6523365FF14C1F45F88737D,8000,9,10.45.1.3
```

- Set `SUBSCRIBER_DB=subscriber_db.csv` in `srsRAN_Project/docker/open5gs/open5gs.env` (we updated this file in the workspace).
- Rebuild the 5gc image so `subscriber_db.csv` is included by the image build step shown above.

gNB configuration for UHD B210 (what we changed)
- File: `srsRAN_Project/configs/gnb_zmq_external_ue.yml`
- Key snippet we use for a B210 device:

```yaml
ru_sdr:
  device_driver: uhd
  device_args: type=b200,serial=310C56E
  srate: 23.04
  tx_gain: 80
  rx_gain: 40
```

- Ensure `cu_cp.amf.addr` in the same file points to the Open5GS container IP on the `ran` network (default `10.53.1.2`).

Starting services (order matters)
1) Ensure `n3br` network exists (see Host network above). Example (run as root or sudo):

```bash
# create bridge + macvlan if needed (run once)
sudo ip link add n3br type bridge || true
sudo ip link set dev n3br up
sudo ip addr add 10.10.3.254/24 dev n3br || true
docker network create -d macvlan --subnet=10.10.3.0/24 --gateway=10.10.3.254 -o parent=n3br n3br || true
```

2) Start both Open5GS and gNB in one command (from the compose directory):

```bash
cd srsRAN_Project/docker
docker compose up -d
```

If you prefer to start only the core first, then the gNB:

```bash
cd srsRAN_Project/docker
docker compose up -d 5gc
docker compose up -d gnb
```

If `open5gs` reports missing `subscriber_db.csv` on startup, rebuild `5gc` (see "Building images") so the file is copied into the image.

Verification & common checks
- Watch Open5GS logs to confirm subscribers were imported (run from `srsRAN_Project/docker`):

```bash
cd srsRAN_Project/docker
docker compose logs -f 5gc
# expect lines like: "Added subscriber with Inserted ID : <id>"
```

- Watch gNB logs to confirm UHD device open and AMF/NGAP connection:

```bash
cd srsRAN_Project/docker
docker compose logs -f gnb
# expect B210 detection and later: "N2: Connection to AMF on 10.53.1.2:38412 was established" and NGSetupRequest/Response
```

- Confirm gNB config inside container:

```bash
cd srsRAN_Project/docker
docker compose exec gnb cat /gnb_config.yml
```

Connectivity checks performed in this workspace
- We observed the following (example): gNB detected the B210, loaded FPGA, and negotiated clock rate. Open5GS imported the two subscribers from `subscriber_db.csv`. NGAP/AMF exchange completed (CU-CP started).

Connecting your custom device (summary)
- Ensure your device implements a 5G UE stack (a full UE stack or srsUE). The device must be provisioned with one of the IMSIs and matching security material (K and OPC/OP) that are present in Open5GS.
- RF parameters must match gNB cell configuration: band, ARFCN/center frequency, bandwidth, SCS, and sample rate.
- If your device is a phone, it must support band 3 and the exact configuration; usually manual network selection helps.

Example test flow with a UE (conceptual):
1. Ensure the gNB is running and broadcasting SSB.
2. Start your UE (or srsUE) with IMSI `001010000000101` and matching keys.
3. Observe gNB logs for RACH/RA/Attach messages and Open5GS logs for "Registration complete".

Troubleshooting (quick)
- No SSB / UE cannot sync: check `srate`, center frequency, and TX power; ensure antennas and cabling are correct.
- Subscriber not found: check `open5gs` logs for `Added subscriber` messages and ensure `SUBSCRIBER_DB` is set correctly in `open5gs.env` or use `subscriber_db.csv` in the image.
- gNB cannot open SDR: confirm `uhd_find_devices` on host, and that the container has access to `/dev/bus/usb` (compose sets `privileged: true` and mounts `/dev/bus/usb/`).
- AMF/NGAP issues: check gNB logs for NGSetupRequest/Response and `open5gs` logs for gNB registration lines.

Journal (progress in this workspace)
- 2026-04-13: Created and verified host bridge `n3br` with IP `10.10.3.254/24` and created Docker macvlan `n3br`.
- 2026-04-13: Added `srsRAN_Project/docker/open5gs/subscriber_db.csv` with two custom subscribers (IMSI 001010000000101 and 001010000000102) and updated `open5gs.env` to `SUBSCRIBER_DB=subscriber_db.csv`.
- 2026-04-13: Rebuilt the `docker-5gc` image so the subscribers file was included and started `open5gs_5gc`; Open5GS imported the subscribers successfully.
- 2026-04-13: Updated `srsRAN_Project/configs/gnb_zmq_external_ue.yml` to use UHD (`device_args: type=b200,serial=310C56E`).
- 2026-04-13: Started `srsran_gnb`; B210 detected and initialized, and gNB completed NGAP/AMF NGSetup exchange with Open5GS.

Next recommended steps
1. Start the ZMQ bridge in `external_ue/host_ue_bridge` if you want to use external container UEs.
2. Or run your custom UE against the running gNB (see "Connecting your custom device").

If you want, I can now either:
- start the ZMQ bridge and show socket ESTAB checks, or
- help craft the exact UE configuration (srsUE or custom) to use IMSI `001010000000101` and test an attach.

---

File locations (quick links)
- `srsRAN_Project/docker/docker-compose.yml` (compose to build & run core + gNB)
- `srsRAN_Project/docker/open5gs/open5gs.env`
- `srsRAN_Project/docker/open5gs/subscriber_db.csv`
- `srsRAN_Project/configs/gnb_zmq_external_ue.yml`

Compose location & editable configs
- Compose used for this setup: `srsRAN_Project/docker/docker-compose.yml` — run commands from `srsRAN_Project/docker` to build and start `5gc` and `gnb`.
- Editable config locations used by that compose:
  - `srsRAN_Project/docker/open5gs/subscriber_db.csv` → used by `5gc` for subscriber provisioning.
    - `srsRAN_Project/docker/open5gs/subscriber_db.csv` → used by `5gc` for subscriber provisioning. This file is bind-mounted into the container so you can edit it on the host and then restart the `5gc` service to pick up changes without rebuilding.
  - `srsRAN_Project/docker/open5gs/open5gs.env` → environment variables for `5gc`.
  - `srsRAN_Project/docker/open5gs/open5gs-5gc.yml.in` → template rendered by the container entrypoint.
  - `srsRAN_Project/configs/gnb_zmq_external_ue.yml` → gNB runtime config mounted into the gNB container.

Apply config changes (example):
```bash
# edit the subscriber DB in the compose directory
cd srsRAN_Project/docker
vi open5gs/subscriber_db.csv

# restart only the 5gc service to pick up subscriber_db.csv changes (no rebuild required)
docker compose up -d --no-deps 5gc

# or just restart the service
docker compose restart 5gc

# restart gnb after updating gnb configs
docker compose up -d --no-deps gnb
```

Smart startup (pull-or-build fallback)

- A helper script `up-with-fallback.sh` is provided at the repository root. It will parse images referenced by `docker-compose.yml`, attempt to pull them, and if a pull fails it builds the corresponding service locally before bringing the stack up. This avoids rebuilding images unless needed.

Usage:
```bash
./up-with-fallback.sh
```

Notes:
- The script invokes `docker compose build <service>` for any missing image — ensure you have sufficient resources and time to build large images locally.
- If you prefer manual control, you can run `docker compose pull` and `docker compose build` yourself before `docker compose up -d`.
- Why the UE cannot be on the ran network
  10.53.1.0/24 is the RAN/ZMQ control network used for gNB, bridge, and core signaling.
  The UE data-plane address from tun_srsue must be on the core UE subnet (e.g. 10.41.0.0/24) so it can route through Open5GS/UPF.
  If the UE gets 10.53.1.x, it collides with the RAN network and the UE’s tunnel traffic is no longer distinguishable from gNB/bridge control traffic.
  That breaks the expected path: UE → tun_srsue → UPF gateway → core/internet.

