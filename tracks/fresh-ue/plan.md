## Plan: Docker Compose deploy — srsUE → gNB (gnb-zmq) → Open5GS

TL;DR - Deploy the `srsue` container via Docker Compose, ensure the UE's IMSI is present in Open5GS `subscriber_db.csv`, connect `srsue` to the gNB ZMQ endpoint, and verify that the UE attaches and receives data connectivity via the core (Open5GS/UPF). Use a user-defined Docker network, mount `srsue/config`, and run the UE container with `CAP_NET_ADMIN` or `privileged` as required.

**Steps**
1. Discovery (quick): inspect `srsRAN_Project/gnb-zmq` and the Open5GS compose to extract the gNB ZMQ host/port, service names, and where `subscriber_db.csv` is mounted. *Action:* open `srsRAN_Project/gnb-zmq` and your Open5GS compose files to find `ZMQ` endpoints and service names.
2. Ensure subscriber: add the UE IMSI and keys to the Open5GS `subscriber_db.csv` located under `srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv`. If Open5GS already mounts this file, reload or restart the Open5GS container so it picks up the subscriber.
3. Create a Docker network: define a user network (e.g., `srsran-net`) in the root `docker-compose.yml` (or in an override). Attach gNB, Open5GS core, and srsUE services to this network.
4. Add srsUE service: create a `srsue` service in `docker-compose.override.yml` with:
   - **Image**: use your srsUE image (or build from `srsRAN_Project` if provided).
   - **Networks**: `srsran-net`.
   - **Volumes**: mount `srsue/config` into the container (so `ue0.conf`, scripts are available).
   - **Environment**: set `GNB_ZMQ_ENDPOINT` or `GNB_HOST` and `GNB_ZMQ_PORT` as extracted.
   - **Capabilites / Privilege**: add `cap_add: - NET_ADMIN` and/or `privileged: true` if `ip netns` or interface creation is needed.
   - **Command**: run `config/start_ue.sh` with appropriate args (ensure it points to the mounted `ue0.conf` and gNB address).
5. Configure UE `ue0.conf`: update fields that reference the gNB or core (if any) to use service names/DNS, or modify `start_ue.sh` to generate a config with the `GNB_ZMQ_ENDPOINT` environment variable.
6. Ensure Open5GS connectivity: confirm Open5GS core (AMF/UPF) is reachable from gNB and that UPF provides a path to the internet (host NAT or real upstream). If Open5GS runs in the same compose stack, ensure its `subscriber_db.csv` has the UE IMSI and that the `upf` has connectivity to the docker network's gateway to reach the internet.
7. Start stack: bring up Open5GS, gNB and the new srsUE service:

```bash
docker-compose up -d open5gs gnb srsue
```

8. Verification:
   - **Container status**: `docker ps` — ensure `srsue`, `gnb`, and Open5GS containers are running.
   - **Open5GS logs**: `docker logs -f <open5gs-container>` — look for registration/attach logs for the UE IMSI.
   - **gNB logs**: `docker logs -f <gnb-container>` — look for messages about UE connection or S1/N2 interactions.
   - **srsUE logs**: `docker logs -f <srsue-container>` — confirm ZMQ connection and attach sequence.
   - **Data plane test**: exec into the UE container and use its network namespace to ping an external IP (e.g., `8.8.8.8`) to validate internet access via the core/UPF.
   - **Connectivity checks**: from within the `srsue` container, test TCP reachability to the `GNB_ZMQ_ENDPOINT` with `nc -vz <gnb-host> <port>`.

9. Troubleshooting notes:
   - If `srsue` fails to create netns or interfaces, ensure `privileged: true` or `cap_add: NET_ADMIN` is set.
   - If UE attaches but has no internet, check UPF routing/NAT and host routing (UPF must be able to NAT/forward UE traffic to the internet gateway).
   - If Open5GS doesn't pick up new subscriber entries, restart or mount the CSV correctly into the core container.

**Relevant files**
- `srsue/ue-deployment.yaml` — contains the current k8s manifest; useful reference.
- `srsue/kustomization.yaml` — shows the config files used by the UE container.
- `srsue/config/ue0.conf` — base UE config to adapt.
- `srsue/config/start_ue.sh` — startup script; modify to accept env vars for gNB host/port.
- `srsRAN_Project/gnb-zmq` — inspect for gNB compose or docker run config; locate ZMQ endpoint.
- `project-config/subscriber_db.csv` — the Open5GS subscriber DB file to add the UE IMSI and auth details.

**Verification (explicit commands)**
- Start stack:

```bash
docker-compose up -d open5gs gnb srsue
```

- Check logs:

```bash
docker logs -f <srsue-container>
docker logs -f <gnb-container>
docker logs -f <open5gs-container>
```

- From inside srsue container (to test internet):

```bash
docker exec -it <srsue-container> bash
# inside container
ip netns list
# find UE netns, enter or run ping via wrapper script
ping -c 3 8.8.8.8
```

**Decisions & Assumptions**
- Runtime chosen: Docker Compose
- gNB exposes a ZMQ TCP endpoint and Open5GS provides the UPF for internet access.
- `srsue` requires `NET_ADMIN` capabilities to create netns and interfaces; `privileged` may be needed.
- The `subscriber_db.csv` format matches your Open5GS version; you will add a row for the UE IMSI.

---

**gNB & Open5GS deployment summary (from your environment)**

CONTAINER | IPs                     | PORTS     | NETWORKS      | WORKDIR
---|---|---|---|---
`srsran_gnb` | 172.19.1.3, 10.53.1.3 | (ZMQ port: see gNB config) | metrics, ran | /home/radr/tuilm/srsran-docker/srsRAN_Project/gnb-zmq
`open5gs_5gc` | 10.53.1.2           | 9999/tcp (ext 9999)         | ran          | /home/radr/tuilm/srsran-docker/srsRAN_Project/gnb-zmq

Use these concrete addresses when wiring the UE service into the same Docker network.

**How the UE will connect to the gNB (explicit)**

- Network: attach `srsue` to the same Docker Compose network that contains the gNB and Open5GS (the `ran` network). This allows using the 10.53.1.x addressing and service DNS.
- ZMQ endpoint: configure the UE's ZMQ connection using the gNB address. Prefer service DNS (`srsran_gnb`) if present; otherwise use the shown IP `10.53.1.3`. Set environment variables in the `srsue` service:

   - `GNB_HOST=10.53.1.3`
   - `GNB_ZMQ_PORT=<gnb-zmq-port>`
   - `GNB_ZMQ_ENDPOINT=tcp://${GNB_HOST}:${GNB_ZMQ_PORT}`

- Open5GS core info: set the core address the UE (or gNB) uses for N2/N1 signaling if needed:

   - `OPEN5GS_AMF=10.53.1.2` (Open5GS host)
   - `OPEN5GS_PORT=9999`

- Config generation: modify `srsue/config/start_ue.sh` (or have the `srsue` container entrypoint) generate `ue_*.conf` using `GNB_ZMQ_ENDPOINT` and `OPEN5GS_AMF` so srsUE knows where to send signaling.

**Subscriber (IMSI) handling**

- Add the UE IMSI and auth vectors to `srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv`. Example CSV row (adjust for your Open5GS CSV schema):

   IMSI,MSISDN,IMSI_STATUS,K,OP,AMF_UE_NGAP_ID, ...

   (Use the existing CSV format in your project-config file; restart Open5GS if it doesn't auto-reload.)

**Concrete compose snippet (high level)**

- In `docker-compose.override.yml` add `srsue` service attached to the `ran` network with:
   - `cap_add: - NET_ADMIN` (or `privileged: true`) to allow `ip netns` and interface setup
   - `volumes: - ./srsue/config:/opt/srsue/config`
   - `environment:` entries above (`GNB_HOST`, `GNB_ZMQ_PORT`, `OPEN5GS_AMF`)
   - `command:` to run `config/start_ue.sh` which will generate the final UE config and start srsUE

**Verification steps (use addresses above)**

- Confirm containers:

```bash
docker ps --filter name=srsran_gnb --filter name=open5gs_5gc --filter name=srsue
```

- Check srsUE logs for ZMQ connect to `10.53.1.3:<port>` and attach sequence.
- Check Open5GS logs on `10.53.1.2:9999` for UE registration.
- From inside `srsue` container, test internet ping once attached:

```bash
docker exec -it <srsue-container> bash
# use provided wrapper to enter UE netns and ping
ping -c3 8.8.8.8
```

---

If you want, I can now produce a ready-to-use `docker-compose.override.yml` with the `srsue` service using `10.53.1.3` and `10.53.1.2:9999` and a short command to append an IMSI row to `subscriber_db.csv`.


