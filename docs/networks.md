# Requirements
N2 (Control Plane): Between the gNB and the AMF.

N3 (User Plane): Between the gNB and the UPF (carries GTP-U packets).

N4 (Control/User Split): Between the SMF and the UPF. N4 is the PFCP control link between SMF and UPF. In our case both are co‑located in one container/process they can talk over localhost or the container IP, so don’t need a separate macvlan network for N4.

N6 (Data Network): Between the UPF and the Internet/Data Network.

The "Type": macvlan
Instead of using a standard bridge (which can be slow due to the Linux bridge's overhead), you are using macvlan.

What it does: It creates a "sub-interface" directly off your physical card (eth0 or the default interface on host with internet access).

Why use it: It gives each container its own unique MAC address on the physical network. This is high-performance and allows the container to act like a physical device on the host's wire.

The "Master": eth0
This tells the CNI that all these virtual networks (N2, N3, etc.) will physically exit the machine through the eth0 port of your Kubernetes worker node.

The "Mode": bridge
In macvlan bridge mode, the virtual interfaces created on the same host can talk to each other directly through the master interface without the packets needing to leave the physical network card.

The "IPAM": static
IP Address Management (IPAM) is set to static.

This is critical for 5G components. In a gNB or UPF, you cannot rely on DHCP. You need to manually assign specific IPs (e.g., in your Pod spec annotations) so that the different 5G components know exactly where to find each other.



## Configuration checklist and expected values

### Networks
- `ran` network
  - Significance: RAN/OAM control plane network for gNB and Open5GS signaling.
  - Expected value: `10.53.1.0/24`
  - Current use: `srsran_gnb` `10.53.1.3`, `open5gs_5gc` `10.53.1.2`, `srsran_zmq_bridge` `10.53.1.6`
- `ue-net` network
  - Significance: ZMQ transport network between UE containers and the bridge.
  - Expected value: `10.54.1.0/24`
  - Current use: `srsran_ue_host` `10.54.1.234`, `srsran_ue_host2` `10.54.1.235`, `srsran_zmq_bridge` `10.54.1.6`
- `metrics` network
  - Significance: Monitoring/metrics traffic only.
  - Expected value: `172.19.1.0/24`
  - Current use: `srsran_gnb`, `srsran_zmq_bridge`

### gNB configuration
- `gNB N3 IP`
  - Significance: source address for gNB ZMQ TX and RX control.
  - Expected value: `10.53.1.3`
- `gNB ZMQ TX endpoint` (`tx_port`)
  - Significance: where gNB publishes downlink samples for the bridge to receive.
  - Expected value: `tcp://10.53.1.3:2000`
- `gNB ZMQ RX endpoint` (`rx_port`)
  - Significance: where gNB receives uplink samples from the bridge.
  - Expected value: `tcp://10.53.1.6:2001`

### Bridge configuration
- `GNB_IP`
  - Significance: gNB listen address for bridge-side ZMQ forwarding.
  - Expected value: `10.53.1.3`
- `BRIDGE_IP`
  - Significance: bridge address on the `ran` network and the endpoint UEs use for `rx_port`?
  - Expected value: `10.53.1.6` on `ran` for gNB-facing RX, and `10.54.1.6` on `ue-net` for UE-facing RX.
- `UE_IP_PREFIX`
  - Significance: compute UE container ZMQ host IPs for the bridge.
  - Expected value: `10.54.1.`
- `UE_IP_BASE`
  - Significance: base offset for UE host IP mapping.
  - Expected value: `233` → UE1 `10.54.1.234`, UE2 `10.54.1.235`
- `BIND_ALL=1`
  - Significance: ensure bridge reply sockets accept connections on all attached interfaces.

### UE configuration
- `GNB_IP`
  - Significance: gNB ZMQ address the UE uses in bridge mode.
  - Expected value: `10.53.1.3`
- `ZMQ_BRIDGE_IP`
  - Significance: bridge address the UE uses for its ZMQ `rx_port`.
  - Expected value: `10.54.1.6`
- `UE_ZMQ_MODE=bridge`
  - Significance: enables bridge mode instead of direct UE<->gNB ZMQ.
- `UE_USE_NETNS=true`
  - Significance: create `tun_srsue` inside a private namespace and route traffic through it.

### Open5GS / UE subscriber configuration
- `OPEN5GS_IP`
  - Significance: core control-plane IP on `ran`.
  - Expected value: `10.53.1.2`
- `UE_IP_BASE`
  - Significance: base for the UE PDN subnet assigned to subscribers.
  - Expected value: `10.41.0`
- `UE_IP_RANGE`
  - Significance: subnet used by Open5GS for UE PDN addresses.
  - Expected value: `10.41.0.0/24`
- `UE_GATEWAY_IP`
  - Significance: UPF gateway for UE PDN traffic inside Open5GS.
  - Expected value: `10.41.0.1`
- Subscriber `ip_alloc`
  - Significance: the actual UE PDN IP assigned during attach.
  - Expected values:
    - IMSI `001010000000001` → `10.41.0.2`
    - IMSI `001010000000002` → `10.41.0.3`

### Current mismatch risk
- The UE transport network (`ue-net`) and the UE PDN subnet (`10.41.0.0/24`) must remain separate.
- The UE container ZMQ host IPs `10.54.1.234` / `10.54.1.235` are only for ZMQ transport, not for subscriber `ip_alloc`.
- The current configuration matches that principle.

### Significance summary
- `ran`: gNB + core signaling path; must carry N2/N3 control traffic.
- `ue-net`: ZMQ bridge transport path for UE RF samples; must not be reused as UE subscriber IP space.
- `10.41.0.0/24`: UE PDN subnet managed by Open5GS; must be reachable from UPF and not overlap `ue-net`.
- `10.54.1.6`: bridge address on `ue-net`; the UE must use this for ZMQ `rx_port`.
- `10.53.1.6`: bridge address on `ran`; gNB uses this for ZMQ uplink.

root@50699e22dafd:/# 