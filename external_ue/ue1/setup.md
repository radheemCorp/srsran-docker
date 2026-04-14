# host_ue1 setup and runbook

## 0) Host network pre-check (run on host once)

```bash
sudo ip link set n3br up
sudo ip addr del 10.10.3.1/24 dev n3br || true
sudo ip addr add 10.10.3.254/24 dev n3br
ip -br a show n3br
```

Expected:
- `n3br` is UP
- host bridge IP is `10.10.3.254/24`

Also ensure shared Docker network exists:

```bash
docker network create -d macvlan --subnet=10.10.3.0/24 --gateway=10.10.3.254 -o parent=n3br ue_n3
```

If it already exists, Docker returns an "already exists" message.

---

## 1) Single-UE mode (direct gNB<->UE)

Use this when running only one external UE.

1. In `.env`, set:
   - `UE_ZMQ_MODE=direct`
2. Ensure gNB `ru_sdr.device_args.rx_port` points to UE1 IP: `10.10.3.234:2001`.
3. Start container:

```bash
docker compose up -d
docker compose exec -it srsran_ue_external bash
/srsran/config/start_ue.sh 1
```

What to check after attach:

```bash
ip netns exec ue1 ip a
ip netns exec ue1 ip route
ip netns exec ue1 ping -c3 10.41.0.1
ip netns exec ue1 ping -c3 8.8.8.8
ip netns exec ue1 ping -c3 google.com
```

Expected:
- `tun_srsue` exists
- default route via `tun_srsue`
- pings succeed

---

## 2) Multi-UE mode (through bridge container)

Use this when running UE1 + UE2 (or more) at the same time.

1. In `.env`, keep:
   - `UE_ZMQ_MODE=bridge`
   - `ZMQ_BRIDGE_IP=10.10.3.236`
2. Ensure gNB `ru_sdr.device_args.rx_port` points to bridge: `10.10.3.236:2001`.
3. Start container and UE1:

```bash
docker compose up -d
docker compose exec -it srsran_ue_external bash
/srsran/config/start_ue.sh 1
```

What to check after attach:

```bash
ip netns exec ue1 ip a
ip netns exec ue1 ip route
ip netns exec ue1 ping -c3 10.41.0.1
ip netns exec ue1 ping -c3 google.com
```

If console stays on `Attaching UE...`, verify via AMF/SMF logs and `tun_srsue` presence.
