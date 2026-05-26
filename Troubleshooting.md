# ZMQ gNB Troubleshooting
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

If ORAN-SC RIC is **not deployed**, **disable E2** in the gNB config:

```yaml
# srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml
e2:
  enable_du_e2: false
  enable_cu_cp_e2: false
  enable_cu_up_e2: false
```

If you want to **enable E2**, make sure:
1. The RIC is deployed: `cd oran-sc-ric && docker compose up -d`
2. `e2.addr` in the gNB config points to the RIC's IP on the `oric_network`
3. `e2.bind_addr` points to the gNB's own IP (or the host IP if gNB uses host networking)

### Grafana shows no data / monitoring not working

If the monitoring stack deploys but Grafana shows no data:

1. **Verify gNB IP is set in `.env`**:

```bash
cat srsRAN_Project/docker/.env | grep -i gnb
```

2. **Verify Telegraf can reach the gNB**:

```bash
cd srsRAN_Project
docker compose -f docker/docker-compose.ui.yml exec telegraf ping -c 3 <GNB_IP>
```

3. **Check Telegraf logs**:

```bash
docker logs <telegraf_container_id> 2>&1 | tail -20
```

### xApp fails to connect to RIC

If xApps error out when trying to subscribe:

1. **Check the RIC is running**:

```bash
cd oran-sc-ric && docker compose ps
```

2. **Check E2 is enabled in the gNB config**:

```bash
grep -A 5 "e2:" srsRAN_Project/gnb-zmq/project-config/gnb/gnb_zmq.yml
```

3. **Check the RIC IP matches `e2.addr` in the gNB config**. Look up the RIC IP:

```bash
cd oran-sc-ric && docker compose ps
```

4. **The gNB must be running before the xApp starts** — the E2 agent registers with the gNB at gNB startup. Restart the gNB if you added RIC after gNB was already running:

```bash
cd srsRAN_Project/gnb-zmq && docker compose up -d --force-recreate gnb
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

