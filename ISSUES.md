
# Issue1: SRSUE segmentation fault 

The srsUE experienced a **Segmentation Fault (Signal 11)** followed by a **Double Free or Corruption** error, which effectively caused the program to "panic" and crash.

### 1.1. The Trigger: RLC Layer Logic Error

The very first line is the most informative:
`srsLog error - Invalid format string: "%s: Current SO larger than SO_start + segment_length..."`

* **What it means:** This is a logic check in the **RLC (Radio Link Control)** layer. In LTE, data is broken into segments. "SO" stands for **Segment Offset**.
* **The Problem:** The software detected that the current data segment it was processing was mathematically impossible (it was larger than the defined start point plus the total length of the segment).
* **The Bug:** Ironically, the logger itself failed because it had an "Invalid format string," likely trying to pass a string where it expected an integer or vice-versa, which often happens when the internal state of the program is already becoming corrupted.

### 2. The Crash: Segmentation Fault (Signal 11)

Immediately after the logic error, the program received `signal=11`.

* **Definition:** A Segmentation Fault occurs when the program tries to access a memory location that it doesn't "own" or that doesn't exist.
* **Context:** Because the RLC layer was dealing with invalid offsets (as seen in the first error), it likely tried to read or write data to a memory address calculated from those bad offsets. This caused the CPU to halt the process to prevent system-wide instability.

### 3. The Final Blow: Double Free or Corruption

The log ends with `double free or corruption (!prev)`.

* **What it means:** This is a memory management error. The program tried to "free" (release) a piece of memory that had already been freed, or the metadata tracking the memory heap was overwritten by bad data.
* **Why it happened:** This often occurs during a crash-handling routine. As the program tried to shut down after the first crash, it likely tried to clean up its resources, but because the internal state was already "corrupt," it tried to delete the same object twice.

---

### Summary of the Flow

1. **Protocol Error:** The UE received or generated an LTE RLC PDU with invalid segment offsets.
2. **Memory Corruption:** The UE tried to process this invalid data, leading to an out-of-bounds memory access.
3. **Process Termination:** The Linux kernel sent `SIGSEGV` (Signal 11) to kill the process.
4. **Heap Cleanup Failure:** During exit, the C library detected memory corruption (double free) and aborted the exit process (`signal=6`).

### logs 
```log
testbed@testbed:~/testbed/docker-srsran/ue/ue2$ docker compose exec srsran_ue_host bash
root@b2ff83928a49:/# /srsran/config/start_ue.sh 2
Configuration for UE2 written to /tmp/ue_2.conf
Active RF plugins: libsrsran_rf_zmq.so
Inactive RF plugins: 
Reading configuration file /tmp/ue_2.conf...

Built in Release mode using commit ec29b0c1f on branch master.

Opening 1 channels in RF device=zmq with args=tx_port=tcp://10.10.3.235:2102,rx_port=tcp://10.10.3.237:2202,base_srate=23.04e6
Supported RF device list: zmq file
CHx base_srate=23.04e6
Current sample rate is 1.92 MHz with a base rate of 23.04 MHz (x12 decimation)
CH0 rx_port=tcp://10.10.3.237:2202
CH0 tx_port=tcp://10.10.3.235:2102
Current sample rate is 23.04 MHz with a base rate of 23.04 MHz (x1 decimation)
Current sample rate is 23.04 MHz with a base rate of 23.04 MHz (x1 decimation)
Waiting PHY to initialize ... done!
Attaching UE...
Random Access Transmission: prach_occasion=0, preamble_index=0, ra-rnti=0x39, tti=174
Random Access Transmission: prach_occasion=0, preamble_index=0, ra-rnti=0x39, tti=334
Random Access Transmission: prach_occasion=0, preamble_index=0, ra-rnti=0x39, tti=494
Random Access Complete.     c-rnti=0x4603, ta=0
RRC Connected
PDU Session Establishment successful. IP: 10.45.0.3
RRC NR reconfiguration successful.
srsLog error - Invalid format string: "%s: Current SO larger than SO_start + segment_length. SN=%d, current SO=%d, SO_start=%d, segment_length=%s"
--- command='/opt/srsRAN_4G/build/srsue/src/srsue /tmp/ue_2.conf' version=23.04.0 signal=11 date='11/05/2026 10:51:21' ---
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x330867) [0x63b7d58fd867]
        /lib/x86_64-linux-gnu/libc.so.6(+0x43090) [0x717b473d5090]
        /lib/x86_64-linux-gnu/libc.so.6(+0x18ba80) [0x717b4751da80]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x4ea438) [0x63b7d5ab7438]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x4eb414) [0x63b7d5ab8414]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x4eb8cc) [0x63b7d5ab88cc]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x4c49b5) [0x63b7d5a919b5]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x49f283) [0x63b7d5a6c283]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x31c082) [0x63b7d58e9082]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x31d7b6) [0x63b7d58ea7b6]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x3263a7) [0x63b7d58f33a7]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x326d97) [0x63b7d58f3d97]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x30a297) [0x63b7d58d7297]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0xcf6c8) [0x63b7d569c6c8]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0xd655c) [0x63b7d56a355c]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x339d8a) [0x63b7d5906d8a]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0xa0ae5) [0x63b7d566dae5]
        /lib/x86_64-linux-gnu/libpthread.so.0(+0x8609) [0x717b47c0e609]
        /lib/x86_64-linux-gnu/libc.so.6(clone+0x43) [0x717b474b1353]
srsRAN crashed. Please send this backtrace to the developers ...
---  exiting  ---
--- command='/opt/srsRAN_4G/build/srsue/src/srsue /tmp/ue_2.conf' version=23.04.0 signal=11 date='11/05/2026 10:51:21' ---
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x330867) [0x63b7d58fd867]
        /lib/x86_64-linux-gnu/libc.so.6(+0x43090) [0x717b473d5090]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x49b0df) [0x63b7d5a680df]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x308a01) [0x63b7d58d5a01]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x309384) [0x63b7d58d6384]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x12d1f7) [0x63b7d56fa1f7]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x12b4dd) [0x63b7d56f84dd]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0xa0ae5) [0x63b7d566dae5]
        /lib/x86_64-linux-gnu/libpthread.so.0(+0x8609) [0x717b47c0e609]
        /lib/x86_64-linux-gnu/libc.so.6(clone+0x43) [0x717b474b1353]
srsRAN crashed. Please send this backtrace to the developers ...
---  exiting  ---
double free or corruption (!prev)
--- command='/opt/srsRAN_4G/build/srsue/src/srsue /tmp/ue_2.conf' version=23.04.0 signal=6 date='11/05/2026 10:51:21' ---
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x330867) [0x63b7d58fd867]
        /lib/x86_64-linux-gnu/libc.so.6(+0x43090) [0x717b473d5090]
        /lib/x86_64-linux-gnu/libc.so.6(gsignal+0xcb) [0x717b473d500b]
        /lib/x86_64-linux-gnu/libc.so.6(abort+0x12b) [0x717b473b4859]
        /lib/x86_64-linux-gnu/libc.so.6(+0x8d26e) [0x717b4741f26e]
        /lib/x86_64-linux-gnu/libc.so.6(+0x952fc) [0x717b474272fc]
        /lib/x86_64-linux-gnu/libc.so.6(+0x96fac) [0x717b47428fac]
        /lib/x86_64-linux-gnu/libc.so.6(+0x46953) [0x717b473d8953]
        /lib/x86_64-linux-gnu/libc.so.6(on_exit+0) [0x717b473d8a60]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x33089d) [0x63b7d58fd89d]
        /lib/x86_64-linux-gnu/libc.so.6(+0x43090) [0x717b473d5090]
        /lib/x86_64-linux-gnu/libc.so.6(+0x18ba80) [0x717b4751da80]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x4ea438) [0x63b7d5ab7438]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x4eb414) [0x63b7d5ab8414]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x4eb8cc) [0x63b7d5ab88cc]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x4c49b5) [0x63b7d5a919b5]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x49f283) [0x63b7d5a6c283]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x31c082) [0x63b7d58e9082]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x31d7b6) [0x63b7d58ea7b6]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x3263a7) [0x63b7d58f33a7]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x326d97) [0x63b7d58f3d97]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x30a297) [0x63b7d58d7297]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0xcf6c8) [0x63b7d569c6c8]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0xd655c) [0x63b7d56a355c]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0x339d8a) [0x63b7d5906d8a]
        /opt/srsRAN_4G/build/srsue/src/srsue(+0xa0ae5) [0x63b7d566dae5]
        /lib/x86_64-linux-gnu/libpthread.so.0(+0x8609) [0x717b47c0e609]
        /lib/x86_64-linux-gnu/libc.so.6(clone+0x43) [0x717b474b1353]
srsRAN crashed. Please send this backtrace to the developers ...
---  exiting  ---

```


# Issue2: The Connection between gNB and UE (android device) keeps droping 

# Issue3: SRSUE long running sessions fail 
- same as issue1 the gnb drops the connection with the ue
- In this case we have a additional problem the zmq, the zmq statet does not update it still shows port already in use when the ie tries to reconnect.  