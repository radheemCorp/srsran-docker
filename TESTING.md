### Notes 

- for all commands ensure the desired ue netns is used.
- for all command ensure the ip is correct 
- the open5gs ip in our case is 10.45.0.1

---
# Connecting to a public iperf server 
```
ip netns exec ue1 iperf3 -c paris.bbr.iperf.bytel.fr -p 9200 -t 3600
```

# Testing locally
## between open5gs UE gateway and ue   
- start iperf server in the open5gs server 
```
iperf3 -s 
``` 
- start a iperf client in the ue 
```
ip netns exec ue1 iperf3 -c 10.45.0.1 -t 3600
```
## between two UEs
- start iperf server in ue1 
```
ip netns exec ue1 iperf3 -s -p 5201
``` 
- start a iperf client in the ue 
```
ip netns exec ue2 iperf3 -c 10.45.0.2 -p 5202 -b 64k -l 160 
```


# ping test
```bash 
ip netns exec ue1 ping 8.8.8.8
```

```bash 
ip netns exec ue1 ping google.com
```


# iperf3 Simulation Parameters

| Scenario | Protocol | Suggested Bandwidth (`-b`) | Packet Size/Buffer (`-l`) | Key Characteristics |
| --- | --- | --- | --- | --- |
| **VoIP (G.711)** | UDP | 80k - 100k | 160 bytes | Low bandwidth, extremely sensitive to jitter/latency. |
| **VoIP (G.729)** | UDP | 24k - 32k | 20 bytes | Highly compressed, very small packets. |
| **Video Call (HD)** | UDP | 2M - 5M | 1450 bytes | Consistent stream, needs low packet loss. |
| **SD Streaming** | TCP | 3M | Default | Burstier than UDP, relies on window scaling. |
| **4K UHD Stream** | TCP | 25M - 50M | Default | High throughput, sensitive to TCP congestion. |
| **IoT / Sensor** | UDP | 1k - 10k | 50 - 100 bytes | Infrequent, tiny bursts of data. |
| **File Transfer** | TCP | Max (Unlimited) | Default | Aims to saturate the link completely. |

---

## Command Breakdown & Logic

### 1. VoIP Simulation (G.711)

VoIP is tricky because it sends small packets very frequently. If you use the default `iperf3` packet size, you aren't accurately testing the "packets per second" (PPS) load on the router.
`iperf3 -c <server_ip> -u -b 100k -l 160 -p 5201 -t 60`

* **`-u`**: Uses UDP (Standard for real-time voice).
* **`-l 160`**: Sets the length of the buffer to match a standard 20ms voice payload.

### 2. High-Quality Video Streaming (UDP)

For live streaming (like Twitch or Zoom), UDP is often used to prioritize speed over perfect recovery.
`iperf3 -c <server_ip> -u -b 5M -l 1450 -t 60`

* **`-l 1450`**: This keeps the packet just under the standard Ethernet MTU (1500) to avoid fragmentation.

### 3. Bulk Data Transfer (TCP)

To test the maximum "pipe" capacity for things like OS updates or large downloads:
`iperf3 -c <server_ip> -P 4 -t 30`

* **`-P 4`**: Runs 4 parallel streams. This helps saturate the link if a single TCP window is being throttled by latency (BDP).

### Metrics to Watch

When you run these tests, look at the following in your output:

* **Jitter (ms):** For VoIP, you want this **< 30ms**.
* **Lost/Total Datagrams:** For video/voice, anything over **1% loss** will result in noticeable clipping or artifacts.
* **Retransmits (TCP only):** High retransmits indicate congestion or a noisy physical line.
