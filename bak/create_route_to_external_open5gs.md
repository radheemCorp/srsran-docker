Since your **gNB is in `host` mode** but your **5GC (UPF) is in `bridge` mode**, the host machine's routing table is the key "bridge" between the two deployments. Because you are using `privileged: true` and a bridge network, the `ogstun` device created inside the `5gc` container is actually visible/managed by the host's kernel.

Follow these steps on both **Host A** and **Host B**.

### 1. Identify the Gateway IPs

* **Host A LAN IP:** `141.24.211.31` | **UE Subnet A:** `10.46.0.0/24`
* **Host B LAN IP:** `141.24.211.149` | **UE Subnet B:** `10.45.0.0/24`

### 2. Add Routes on the Host Machines

You must run these on the physical host machines (not inside the Docker containers).

**On Host A:**

```bash
# Route traffic for UE Subnet B to Host B
sudo ip route add 10.45.0.0/24 via 141.24.211.149

```

**On Host B:**

```bash
# Route traffic for UE Subnet A to Host A
sudo ip route add 10.46.0.0/24 via 141.24.211.31

```

---

### 3. Configure the "Traffic Pipeline" (Host Level)

Since the `5gc` container is using a bridge network, the Linux kernel sees traffic coming from the `ogstun` interface (inside the container/netns) and needs to forward it to the physical Ethernet card.

**Run these on both Host A and Host B:**

- find the name of your bridge to apply forward on 
```bash 
# 1. lookup docker networks 
docker network ls

# expected:

# $ docker network ls 
# NETWORK ID     NAME                  DRIVER    SCOPE
# 94d65e70e6e3   bridge                bridge    local
# 57be3a97db22   gnb-uhd_srs_network   bridge    local
# de5a6aeba40e   host                  host      local

# 2. Now check host bridges (you should see something like br-57be3a97db22, following br-<DOCKER_NETWORK_ID>)
nmcli device | grep bridge
```
- now replace <YOUR_BRIDGE_ID> with the bridge id in the snippet below. this id might change when network is recreated.

1. **Enable IPv4 Forwarding:**
```bash 
# 1. Enable packet forwarding in the kernel
sudo sysctl -w net.ipv4.ip_forward=1

# 2. Set the default Forward policy to ACCEPT (since security is not a concern)
sudo iptables -P FORWARD ACCEPT

# 3. Ensure the Docker bridge doesn't block the traffic
sudo iptables -A FORWARD -i <YOUR_BRIDGE_ID> -j ACCEPT
sudo iptables -A FORWARD -o <YOUR_BRIDGE_ID> -j ACCEPT
```

### 4. Adjust the NAT (Masquerade) Rule
In standard Open5GS setups, there is a masquerade rule that hides UE IPs behind the Host IP. **If you want UE-A to see the real IP of UE-B, you must make sure the NAT doesn't trigger for internal LAN traffic.**

**On Host A, check your NAT rules:**
```bash
sudo iptables -t nat -L POSTROUTING -n -v

```

If you see a rule masquerading everything from `10.45.0.0/16`, replace it or prepend a "RETURN" rule so it doesn't NAT traffic destined for the other site:

```bash
# Don't NAT traffic if the destination is the other UE pool
sudo iptables -t nat -I POSTROUTING -s 10.45.0.0/16 -d 10.46.0.0/16 -j RETURN

```

*(Do the reverse on Host B).*

---

### 5. Verify the Path

Because your gNB is in `network_mode: host`, it is talking to the 5GC container via the Docker bridge IP (`172.16.1.2`).

1. **Check `ogstun`:** Ensure the `ogstun` interface is actually up on the host or inside the `5gc` container.
* Run `docker exec -it open5gs_5gc ip addr` to see if `ogstun` has the correct `10.45.x.x` IP.


2. **Ping Test:**
* From **Host A**, try to ping a UE on **Deployment B**: `ping 10.46.0.2`.
* If that works, try pinging from **UE A** to **UE B**.



### Why this works with your Docker setup:

1. **gNB (Host Mode):** Sends GTP packets directly to the Host's IP stack.
2. **5GC (Bridge Mode):** Receives packets, decapsulates them. The resulting IP packet (Source: UE-A) hits the container's routing table.
3. **Container Routing:** The container sees the destination is `10.46.0.0/16`. It doesn't have a local route, so it sends it to its gateway (`172.16.1.1` - your Host).
4. **Host Routing:** Your Host looks at the packet, sees your manual route `via 192.168.1.20`, and pushes it out to the LAN.

**Note on MTU:** If you can ping but large files fail, the Docker bridge MTU (1500) minus the GTP overhead might be causing fragmentation. You may need to set the `ogstun` MTU to `1400` inside the `open5gs-5gc.yml` config.

```

```