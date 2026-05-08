# host_ue_bridge setup and runbook

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

Ensure shared Docker network exists:

```bash
docker network create -d macvlan --subnet=10.10.3.0/24 --gateway=10.10.3.254 -o parent=n3br ue_n3
```

---

## 1) Start bridge in multi-UE mode

Bridge is used for simultaneous multi-UE operation.

Defaults come from `.env`:
- `NUM_UES=10`
- `UE_IDS=1,2`
- `GNB_IP=10.10.3.231`
- `BRIDGE_IP=10.10.3.236`
- `UE_IP_BASE=233`

Start:

```bash
docker compose up -d
```

---

## 2) What to check after bridge start

1. Bridge sockets:

```bash
docker exec srsran_zmq_bridge ss -ltnp
docker exec srsran_zmq_bridge ss -tnp
```

Expected:
- LISTEN on `10.10.3.236:2001`
- LISTEN on UE downlink ports `2201`, `2202` (or more if `UE_IDS` expanded)
- ESTAB with gNB on `2000/2001`

2. Optional logs:

```bash
docker compose logs
```

Note:
- GNU Radio lines about `vmcircbuf` are expected and non-fatal.

---

## 3) Single-UE mode note

- Bridge is not required in direct single-UE mode.
- For single mode, run UE from `host_ue1` or `host_ue2` with `UE_ZMQ_MODE=direct` and point gNB directly to that UE IP (`:2001`).
