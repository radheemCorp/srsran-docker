### **Performance Summary Report: srsRAN Real-Time Failure**


## **1. Summary**
Despite applying standard Linux performance optimizations—including setting the CPU governor to `performance`, disabling KMS polling, and increasing network socket buffers (32MB)—the srsRAN gNB application is experiencing critical real-time failures. These manifest as constant **RF Underflows** and **Late** packets, indicating the system cannot process radio samples within the strict timing windows required for 5G/LTE operation.

---

## **2. System Specifications (Guest VM)**
*   **Host CPU:** Intel(R) Core(TM) i9-13900K (24 Cores / High-performance Raptor Lake)
*   **Architecture:** x86_64 (KVM Hypervisor)
*   **Allocated Resources:** 24 Virtual CPUs (vCPUs)
*   **Virtualization Type:** Full Virtualization (VT-x)
*   **Relevant Flags:** AVX2, AVX_VNNI (Crucial for PHY processing)

---

## **3. Problem Analysis**
The logs show a recurring pattern of `[RF] [W] Real-time failure in RF: underflow/late`. This is highly specific to the **Virtual Machine (VM)** environment and the **Intel Hybrid Architecture** (P-cores vs E-cores).

### **Key Bottlenecks Identified:**
1.  **Hypervisor Jitter:** Even with a powerful i9-13900K, the KVM abstraction layer introduces micro-latencies. In SDR, if a sample is delayed by even a few microseconds, the hardware sees it as "Late," and the link drops.
2.  **Buffer Saturation vs. Latency:** Increasing `rmem/wmem` to 32MB ensures enough space exists for data, but it does not guarantee the CPU will process that data fast enough. The failure is a **Latency** issue, not a **Throughput** issue.
3.  **PRACH Depletion:** The log `PRACH buffer pool depleted` suggests the PHY layer is falling so far behind that it cannot even initialize the buffers for incoming random access requests from UEs.

---

## **4. Applied Optimizations (Status)**
| Optimization | Status | Result |
| :--- | :--- | :--- |
| **CPU Governor** | **Enabled** | Set to `performance` (Successfully updated all 24 vCPUs). |
| **KMS Polling** | **Disabled** | Reduced interrupt interference from display drivers. |
| **Net Buffers** | **Enabled** | Set to 32MB (`net.core.wmem_max = 33554432`). |
| **Outcome** | **FAILED** | Underflows persist; real-time requirements not met. |

---

## **5. Root Cause & Recommendations**
The i9-13900K is a powerhouse, but its **Hybrid Architecture** (Performance-cores and Efficient-cores) often causes issues in VMs. If the hypervisor schedules the gNB process on an **E-core**, it will fail real-time deadlines regardless of the governor setting.

### **Next steps options:**
1.  **CPU Pinning (Host Side):** On the host machine, pin the VM's vCPUs specifically to the i9's **P-Cores** (Cores 0-15) and isolate them from host OS tasks.
2.  **Disable Mitigations:** The `lscpu` output shows active mitigations for **Spectre v1/v2**. These significantly slow down system calls. Adding `mitigations=off` to the VM's GRUB command line can provide a ~15-20% performance boost.
3.  **Real-Time Kernel:** Switch the guest OS to a **Low-Latency** kernel to reduce the scheduling quantum.