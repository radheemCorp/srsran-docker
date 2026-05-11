# Deploy gNB with ZMQ (External UE Bridge)

This guide shows how to run the srsRAN gNB in ZMQ-RF mode with external UE devices
connected via a ZMQ bridge. No UHD SDR hardware is required.

**Components**: ORAN-SC RIC (optional), Open5GS Core, ZMQ Bridge, and external UE containers.

---

## 1. Build images

Same as the UHD setup — build from the same Dockerfile:

```bash
cd srsRAN_Project/docker
docker compose build
```
Once built, make sure the image name in the srsRAN_Project/gnb-zmq/docker-compose.yml matches the image that was just built.

Alternatively, pull pre-built images from the registry:
- gNB image: `rptestbed/gnb:20260507-dpdk`
- open5gs image: `rptestbed/open5gs:20260507-dpdk`
- UE/bridge image: `ghcr.io/sulaimanalmani/srsranzmq/srsue:v1.1`



## 1.1 Available Docker Compose Files

| Compose File | Services | Purpose | deploy location |
|--------------|----------|---------| -------- |
| `docker-compose.yml` | `5gc`, `gnb` | Complete gNB + Open5Gs Core deployment | srsRAN_Project/gnb-uhd |
| `docker-compose.yml` | `e2-agent`, `ric`, `xApp` | Minimal deployment of O-RAN Software Community (SC) Near-Real-time RIC | oran-sc-ric |
| `docker-compose.ui.yml` | `telegraf`, `influxdb`, `grafana` | Monitoring and metrics visualization | srsRAN_Project |

## 1.2 Configuration files 

| Services | Purpose | location |
|----------|---------| -------- |
| `gnb` | Configuring the gNB | srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml |
| `open5gs` | Configuring the Open5gs | srsRAN_Project/gnb-zmq/project-config/open5gs-5gc.yml.in |
| `open5gs` | Configuring the Open5gs | srsRAN_Project/gnb-zmq/project-config/open5gs.env 



---

## 2. Deploy Open5GS (5GC)

### Prerequisites

#### 2.0 Verify Docker networks match compose files

All networks must exactly match the configurations declared in the Docker Compose files.
Use `dnet` and `remove`/`recreate` to fix them.

```bash
./scripts/net_manage.sh dnet
```

Expected output (check names and subnets match the compose files):

| Network | IPv4 Subnet | Required by |
|---------|-------------|-------------|
| `n2` | `10.53.1.0/24` | `gnb-zmq/docker-compose.yml` (5GC, gNB) |
| `n3` | `10.10.3.0/24` | `gnb-zmq/docker-compose.yml`, `ue/*/docker-compose.yaml`, `ue/bridge/docker-compose.yaml` |
| `oric_network` | `10.0.2.0/24` | `gnb-zmq/docker-compose.yml` for RIC |
| `metrics` | `172.19.1.0/24` | `docker-compose.ui.yml` |
| `oran-sc-ric` | `10.0.2.0/24` | `oran-sc-ric/docker-compose.yml` |

If the output doesn't match, fix it:

```bash
# Remove existing (mismatched) networks
./scripts/net_manage.sh remove

# Recreate with correct defaults
./scripts/net_manage.sh create
```

All subnets and names can be overridden via environment variables (e.g. `N3_SUBNET=10.10.4.0/24`).
See `scripts/net_manage.sh` for all configurable variables.

Ensure the shared Docker network exists:

```bash
docker network create -d macvlan --subnet=10.10.3.0/24 --gateway=10.10.3.254 -o parent=n3br ue_n3
```

### 2.1 Sync UE IP configuration

The UE IP subnet must match between `open5gs.env` (used by the 5GC entrypoint for routing/NAT)
and `subscriber_db.csv` (used by the SMF/UPF session config).

| File | Parameter | Example |
|------|-----------|---------|
| `srsRAN_Project/gnb-zmq/project-config/open5gs.env` | `UE_IP_BASE` | `10.45.0` |
| `srsRAN_Project/gnb-zmq/project-config/open5gs.env` | `UE_IP_RANGE` | `10.45.0.0/24` |
| `srsRAN_Project/gnb-zmq/project-config/open5gs.env` | `UE_GATEWAY_IP` | `10.45.0.1` |
| `srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv` | `ip_alloc` column | `10.45.0.2`, `10.45.0.3`, etc. |

The 5GC entrypoint hardcodes the subnet as `${UE_IP_BASE}.0/24` regardless of what
`UE_IP_RANGE` is set to. **All subscriber `ip_alloc` values must fall within this /24.**

Verify your subscriber data before starting:

```bash
# Should list UEs with IPs inside 10.45.0.0/24
cat srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv
```

### 2.2 Deploy the 5GC

```bash
cd srsRAN_Project/gnb-zmq
docker compose up -d 5gc
```

### 2.3 Verify forwarding and NAT rules

```bash
# IP forwarding should be enabled
docker exec open5gs_5gc sysctl net.ipv4.ip_forward

# ogstun TUN interface should exist with the gateway IP
docker exec open5gs_5gc ip addr show ogstun

# POSTROUTING MASQUERADE rule for UE subnet
docker exec open5gs_5gc iptables-legacy -t nat -L POSTROUTING -v -n

# FORWARD rules (ogstun <-> internet)
docker exec open5gs_5gc iptables-legacy -L FORWARD -v -n

# 5GC logs — confirm all NFs started, no errors
docker logs open5gs_5gc 2>&1 | tail -30
```

Expected output:
- `ogstun` interface: `10.45.0.1/24`
- MASQUERADE rule: source `10.45.0.0/24` → out `eth0`
- FORWARD: ACCEPT for both directions between `ogstun` and `eth0`


### 2.4 Start gNB 
```bash 
cd srsRAN_Project/gnb-zmq
docker compose up -d gnb 
```
- review startup at logs 
```bash 
docker compose logs gnb
```
- review gnb logs avaiable at `srsRAN_Project/gnb-zmq/gnb-storage/gnb.log`

---

## 3. Start the ZMQ Bridge

The bridge connects gNB → external UEs over ZMQ. It handles multiple UEs in a single
GNU Radio process.

### 3.1 Deploy

```bash
cd ue/bridge
docker compose up -d
```

### 3.2 Verify bridge sockets

```bash
docker exec zmq_bridge ss -ltnp
docker exec zmq_bridge ss -tnp
```

Expected:

| Socket | Direction | Description |
|--------|-----------|-------------|
| LISTEN on `10.10.3.237:2001` | Bridge → gNB (uplink aggregate) | REP sink |
| LISTEN on `10.10.3.237:2201` | Bridge ← gNB → UE1 (downlink) | REP sink |
| LISTEN on `10.10.3.237:2202` | Bridge ← gNB → UE2 (downlink) | REP sink |
| ESTAB `10.10.3.237:2000` ↔ gNB | Bridge → gNB (downlink) | REQ source |

At this stage (UEs not started yet), you should see the bridge connected to the gNB
on ports `2000`/`2001`, but **no ESTAB connections to UE containers** yet.

---

## 4. Start UE1

```bash
cd ue/ue1
docker compose up -d
```

Then enter the container and start the UE instance:

```bash
docker compose exec srsran_ue_host bash
root@<hash>:/# /srsran/config/start_ue.sh 1
```

This will:
- Generate `/tmp/ue_1.conf` from env vars (`GNB_IP`, `ZMQ_BRIDGE_IP`, `UE_BIND_IP`, `UE_ZMQ_MODE`)
- Create a network namespace `ue1`
- Run srsUE which will create `tun_srsue` inside the namespace after successful attach

---

## 5. Start UE2

Repeat the same steps in the other UE container:

```bash
cd ue/ue2
docker compose up -d
docker compose exec srsran_ue_host bash
root@<hash>:/# /srsran/config/start_ue.sh 2
```

---

## 6. Verify all connections

Check the bridge again — all UE sockets should now be ESTABLISHED:

```bash
docker exec zmq_bridge ss -tnp
```

Expected connections:

| Local Address | Remote | Process |
|--------------|--------|---------|
| `10.10.3.237:52674` → `10.10.3.231:2000` | UE1 → gNB | bridge REQ source (UE1 uplink) |
| `10.10.3.237:2201` ← `10.10.3.234:35894` | gNB → UE1 | bridge REP sink (UE1 downlink) |
| `10.10.3.237:43852` → `10.10.3.234:2101` | UE1 → bridge | bridge REQ source (UE1 uplink) |
| `10.10.3.237:42638` → `10.10.3.235:2102` | UE2 → bridge | bridge REQ source (UE2 uplink) |
| `10.10.3.237:2202` ← `10.10.3.235:52632` | gNB → UE2 | bridge REP sink (UE2 downlink) |

---

## 7. Verify UE attach

Inside each UE container:

```bash
# tun_srsue should now exist in the network namespace
docker exec ue1 ip netns exec ue1 ip addr show tun_srsue
docker exec ue2 ip netns exec ue2 ip addr show tun_srsue
```

Expected: a `tun_srsue` interface with a `10.45.0.x` address.

Check the 5GC logs to confirm the registration:

```bash
docker logs open5gs_5gc 2>&1 | grep -iE "ngap| registration|pdu|session"
```

Expected:
- `gNB-N2 accepted[...] in ng-path module`
- `gNB-N2[...] max_num_of_ostreams`
- UE registration messages (look for IMSI values from `subscriber_db.csv`)

Check the gNB log:

```bash
docker logs srsran_gnb 2>&1 | grep -iE "cell|prach|ssb|msg1|msg2|msg3|msg4|nc:|ue:"
```

---

## Troubleshooting

### UE stuck on "Attaching UE..." / `tun_srsue` never appears

This means the UE never completed PDU session establishment.

1. **Check subscriber IMSI matches** — the `imsi` field in the generated config must exist in the CSV:
   ```bash
   docker exec ue1 cat /tmp/ue_1.conf | grep imsi
   cat srsRAN_Project/gnb-zmq/project-config/subscriber_db.csv
   ```

2. **Verify IP subnet matches** — the UE's assigned IP from the CSV must be within
   the `/24` subnet set by the 5GC entrypoint:
   ```bash
   docker exec open5gs_5gc ip addr show ogstun
   # Should show /24, all subscriber IPs must fit
   ```

3. **Restart 5GC after subscriber CSV changes** — the entrypoint loads the CSV into MongoDB only at startup:
   ```bash
   docker compose restart 5gc
   ```

4. **Check gNB-N2 connection** — the gNB must have established NGAP with the AMF:
   ```bash
   docker logs srsran_gnb 2>&1 | grep "ngap" | tail -10
   docker logs open5gs_5gc 2>&1 | grep "gNB-N2" | tail -10
   ```

### E2 / RIC errors blocking gNB startup

If ORAN-SC RIC is not deployed, **disable E2** in the gNB config:

```yaml
# srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml
e2:
  enable_du_e2: false
  enable_cu_cp_e2: false
  enable_cu_up_e2: false
```

### No RRC/NAS traffic between UE and gNB

The ZMQ sockets may be established but no radio data crosses them. This usually means:
- Frequency mismatch (LTE EARFCN vs NR ARFCN)
- The gNB cell is not broadcasting (check gNB logs for "ssb", "prach", "sib")
- The ZMQ bridge is not connected to gNB on the correct ports

### Connection refused after 6 minutes

The gNB AMF `inactivity_timer` defaults to 7200 seconds. If the gNB N2 connection drops
silently, the AMF won't clean up for 2 hours. Check for NAT/port exhaustion or network
interruptions between gNB and AMF containers.

### UE can't access the Internet — missing IP forwarding or NAT

If the UE attaches successfully but has no internet connectivity, the problem is usually
IP forwarding or NAT masquerading rules inside the 5GC container.

1. **Enter the 5GC container**

```bash
docker exec -it open5gs_5gc bash
```

2. **Check the ogstun TUN interface**

```bash
ip addr show ogstun | grep 10.45.0
ip route show table main | grep 10.45
sudo ip -d link show ogstun
```

Expected: `inet 10.45.0.1/24` on ogstun, and a kernel route for `10.45.0.0/24`.

3. **Check IP forwarding**

```bash
sysctl net.ipv4.ip_forward
```

Expected: `net.ipv4.ip_forward = 1`

If it shows `0`, enable it:

```bash
sysctl -w net.ipv4.ip_forward=1
```

To make it permanent inside the container (note: will reset on container restart):

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
```

4. **Check NAT (masquerading) rules**

```bash
iptables-legacy -t nat -L POSTROUTING -v -n
```

Expected: a MASQUERADE rule matching source `10.45.0.0/24`.

If missing, add it (replace `eth0` with your actual internet-facing interface):

```bash
iptables-legacy -t nat -A POSTROUTING -s 10.45.0.0/24 -o eth0 -j MASQUERADE
```

5. **Check FORWARD rules**

```bash
iptables-legacy -L FORWARD -v -n
```

If missing, add the forwarding rules:

```bash
iptables-legacy -A FORWARD -i ogstun -o eth0 -j ACCEPT
iptables-legacy -A FORWARD -i eth0 -o ogstun -m state --state RELATED,ESTABLISHED -j ACCEPT
```

6. **Verify routing table**

```bash
ip route
```

You should see a `default via ... dev eth0` rule.

7. **Test from the UE**

Once forwarding and NAT are in place, test internet access from the phone or UE:

```bash
docker exec ue1 ip netns exec ue1 ping 8.8.8.8
```

