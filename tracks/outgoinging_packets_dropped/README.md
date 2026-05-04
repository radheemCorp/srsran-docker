## 1. The Core Problem
Running a **5G gNB (Base Station)** using srsRAN, which is a real-time, high-throughput application. Even small delays in how the PC handles data (latency) or small "waiting rooms" for data (buffers) cause the system to drop packets. 

**Symptoms observed:**
*   **Outgoing packets dropped:** 20 packets were dropped at the network interface level.
*   **Buffer limitations:** The hardware was significantly under-utilizing its available memory.
*   **Timing sensitivity:** "Late" or "Underflow" errors during radio transmission.

- The Incoming traffic arrives just fine. The outgoing traffic faces some delays, by the time it arrives to the desired interface to be published to the SDR, the time window it is requesting to be published on is in the past hence the interface (or kernel) drops the packet.
- After running the ./srsRAN_Project/scripts/srsran_performance I no longer see the "Late" or "Underflow" errors. But there are still 20 outgoing packets being dropped, I still cant browse the internet from the UE 

---

## 2. Hardware Profile
*   **SDR Device:** **USRP B210** (NI2901).
    *   **Interface:** USB 3.0 (verified "Operating over USB 3").
    *   **Capabilities:** Dual-channel, up to 56 MHz bandwidth, 6 GHz frequency range.
*   **PC Interface:** **enp2s0** (Intel-based Ethernet).
    *   **Role:** Likely handles the connection to the 5G Core Network (Open5GS) or external data traffic.
    *   **Original State:** Small ring buffers (256) and standard MTU (1500).

---

## 3. Solutions & Optimizations Attempted

We have addressed the bottlenecks across three layers: the **Operating System**, the **Network Interface**, and the **SDR Transport**.

### A. Network Interface (`enp2s0`)
| Optimization | Action Taken | Purpose |
| :--- | :--- | :--- |
| **Ring Buffers** | Increased RX/TX from **256 to 4096** | Maximize hardware-level memory to prevent drops during CPU spikes. |
| **Transmit Queue** | Increased `txqueuelen` to **10000** | Prevents "Outgoing packets dropped" by giving the kernel a larger exit queue. |
| **Offloads** | Disabled `gro`, `gso`, and `tso` | Prevents the NIC from "batching" packets, ensuring immediate transmission for radio timing. |
| **Flow Control** | Disabled `rx/tx` pause frames | Ensures the data stream is never paused by the network stack. |



### B. Linux Kernel & System
| Optimization | Action Taken | Purpose |
| :--- | :--- | :--- |
| **Performance Mode** | Set CPU scaling governor to `performance` | Forces CPU to max clock speed to eliminate "wake-up" latency. |
| **USB Power** | Disabled `usbcore` autosuspend | Prevents the B210 from entering power-save mode during operation. |
| **Memory Buffers** | Set `rmem`/`wmem` max to **32 MB** | Expands the OS socket buffers for high-speed UDP radio data. |
| **Swappiness** | Reduced `vm.swappiness` to **10** | Forces the PC to keep gNB data in RAM instead of slow disk swap. |
| **KMS Polling** | Disabled DRM KMS polling | Removes periodic background interruptions from the graphics driver. |

### C. srsRAN & UHD Transport (B210 Specific)
*   **Frame Buffering:** Recommended increasing `num_recv_frames` and `num_send_frames` to **128** in `gnb.yml`.
*   **Clock Alignment:** Recommended setting `master_clock_rate` to **23.04 MHz** to match 5G NR sampling requirements.

---

## 4. Current Status
*   We have successfully expanded the system memory and USB power constraints. 
*   The hardware does not support "Interrupt Coalescing" (`ethtool -C` error), but we bypassed this by using a larger `txqueuelen` and disabling offloads.
*   **Next Step:** Monitor gNB console for **"L" (Late)** or **"U" (Underflow)**. If those appear, the next step is **CPU Core Isolation** to protect the radio threads from the rest of the OS.

# Problem logs 
## get sdr specs 
```
uhd_usrp_probe --args="type=b200"
``` 

## the internet interface in use 
- The SDR is connected over usb i dont understand why the interface needs to be optimized
- Gemini response, will look into this further 
```
A 5G Base Station doesn't operate in a vacuum. It sits between two different "worlds":
    The Radio World (USB): The gNB sends/receives raw "IQ" samples to the B210.
    The Core World (Ethernet): The gNB sends/receives actual internet traffic (IP packets) to the 5G Core Network (like Open5GS or srsEPC).
If your enp2s0 interface is dropping packets, it means the connection between your gNB and the Core Network is failing. Even if the radio link is perfect, the user (phone) will experience a "dead" connection because the data can't get past the PC's ethernet port to the internet. 
```
```
$ ip a show enp2s0
3: enp2s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 10000
    link/ether 00:1b:21:ed:fc:2a brd ff:ff:ff:ff:ff:ff
    inet 141.24.211.31/24 brd 141.24.211.255 scope global noprefixroute enp2s0
       valid_lft forever preferred_lft forever
    inet6 fe80::1a86:e53d:1eae:89e6/64 scope link noprefixroute 
       valid_lft forever preferred_lft forever
```

## problem evidence 
```log 
$ watch -d "netstat -s | grep -i 'buffer errors\|drop'"
    20 outgoing packets dropped
    0 receive buffer errors
    0 send buffer errors
```