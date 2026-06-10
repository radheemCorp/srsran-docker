Here is a summary of the two sequential problems you faced based on the logs and configurations provided:

---

## Problem 1: Network Slice Mismatch (`S_NSSAI` Error)

* **The Symptom:** The gNB attempted to connect to the AMF over the N2 interface, but the AMF repeatedly rejected the connection with an `NG-Setup failure` warning stating: `Cannot find S_NSSAI. Check 'amf.plmn_support.s_nssai' configuration`.
* **The Cause:** Open5GS expects the Network Slice Selection Assistance Information—specifically the **SST** (Slice/Service Type) and **SD** (Slice Differentiator)—broadcast by the gNB to perfectly match the slice info configured in the core network. The AMF could not find a matching slice configuration, resulting in a dropped connection (`connection refused!!!`).

---

## Problem 2: YAML Syntax Error & Core Crash

* **The Symptom:** After attempting to fix the slice mismatch, the Open5GS AMF failed to boot entirely, crashing with a `FATAL: Open5GS initialization failed. Aborted` log.
* **The Cause:** An accidental extra hyphen (`-`) was added before `s_nssai` in the `open5gs-5gc.yml` file. In YAML syntax, this extra hyphen split a single PLMN support profile into two separate, incomplete array items:
1. A PLMN ID with no slice information.
2. A slice configuration with no PLMN ID.
Because both were invalid, the AMF ignored them, threw an `ERROR: No amf.plmn_support`, and crashed.



---

## Ultimate Root Cause: Decimal vs. Hexadecimal Notation

* **The Bug:** Even with the syntax fixed, the slice mismatch returned because of how different software tools interpret data types.
* **The Breakdown:** Your srsRAN gNB configuration defined the Slice Differentiator (SD) as a decimal string: `"1118481"`. However, Open5GS expects the SD parameter in its configuration file to be written as a 6-digit **hexadecimal** string.
* **The Solution:** Converting the decimal value `1118481` into its hex equivalent (`111111`) and applying it to the AMF configuration allows both systems to successfully align and complete the 5G handshake.

Here is a concise summary of the chain reaction of problems occurring in your Open5GS deployment based on the provided logs:

---

## 1. Core Problem: IMS Parameter Negotiation Failure (Unknown PCOs)

Every connection attempt ultimately breaks down because the UE (phone) asks the core network for specific protocol configuration options related to **IMS/VoLTE services** (specifically, PCO IDs `0x2`, `0x23`, and `0x24`).

* Because the SMF does not natively answer or recognize these requested parameters in its current configuration, it fails to cleanly finish negotiating the session parameters.
* This leaves the phone in an unconfigured state, causing it to reject the data connection.

## 2. Secondary Problem: Session State Disconnection (`smContextRef [NULL]`)

Because the configuration parameters fail to exchange cleanly between the network and the phone, the AMF's internal session tracking breaks down.

* The Session Management Context Reference becomes empty (`smContextRef [NULL]`).
* When the AMF attempts to modify and finalize the radio path with the cell tower, it passes a `NULL` identifier. The process hangs for about 7 seconds and times out, resulting in a **UE Context Release** (the network dropping the phone completely).

## 3. Consequential Problem: Subscriber Authentication Out-of-Sync (Synch Failure)

Because the connection has been abruptly severed multiple times, the database's sequence counter and the SIM card's internal tracking counter fall completely out of sync.

* This triggers an `Authentication failure(Synch failure)` warning on subsequent attachment attempts.
* While the core automatically attempts to recover from this via a resynchronization procedure, it introduces timing delays into an already fragile environment.

## 4. Architectural Problem: Slow SBI Service Discovery

The logs show the AMF temporarily losing track of the SMF (`No SMF Instance`), forcing it to reach out to the NRF (Network Repository Function) to rediscover where the SMF lives (`127.0.0.4`). This discovery loop happens at the exact same moment the phone is requesting its data session, worsening the internal timeout loop.

---

### Summary of the Lifecycle Flow:

```text
[UE Resyncs Auth] ──> [Registers Successfully] ──> [Requests IMS Session]
                                                              │
[UE Dropped to 0] <── [Timeout / Context Release] <── [smContextRef drops to NULL] <── [SMF Fails PCO Negotiation]

```

---
Here is a summary of the connection lifecycle and the problems faced based on the logs and configuration files provided.

---

## 1. Phase 1: Cryptographic Out-of-Sync (Resolved)

### What the Log Showed:

```text
[gmm] WARNING: Authentication failure(Synch failure)

```

### The Problem:

When the UE first attempted to connect, the **Sequence Number (SQN)** inside the phone's USIM card did not match the tracking range expected by the Open5GS UDM/HSS database.

### The Outcome:

This was a minor hurdle. The 5G network automatically performed a re-synchronization procedure, updated the sequence numbers, and successfully registered the device on the very next attempt.

---

## 2. Phase 2: Immediate Radio Disconnection (The Main Issue)

### What the Log Showed:

```text
[gmm] INFO: [imsi-001010000000103] Registration complete
...
[amf] INFO: UE Context Release [Action:2]
[amf] INFO: [Removed] Number of gNB-UEs is now 0

```

### The Problem:

Exactly 2 to 3 seconds after successfully registering, the radio connection was abruptly torn down (`UE Context Release`). The UE successfully authenticated, but it could not establish a **PDU Session** (the actual data pipeline to get an IP address and browse the internet).

---

## 3. The Root Cause: Network Slicing Mismatch

The actual mismatch preventing data sessions from starting was found by cross-referencing your Subscriber Database configuration with your gNB (srsRAN/UHD) configuration file.

| Layer | Configuration Location | Configured Value | How the Core Interprets It |
| --- | --- | --- | --- |
| **Core Network** | Open5GS Subscriber Profile (MongoDB) | `sst: 1`, `sd: "111111"` | **SST:** 1 <br>

<br>**SD:** `0x111111` (Hexadecimal) |
| **Radio Network** | `gnb.yaml` (`tai_slice_support_list`) | `sst: 1`, `sd: "1118481"` | **SST:** 1 <br>

<br>**SD:** `0x111231` (Parsed incorrectly due to decimal string wrapper) |

### Summary of the Mismatch:

Because the gNB configuration attempted to convert the hexadecimal value `0x111111` into a decimal string (`"1118481"`), the Core Network viewed the base station and the subscriber profile as living on two completely different network slices.

The core successfully registers the user on the network, but the moment the user requests data routing, the core realizes the base station's broadcast slice doesn't match the user's allowed slice profile and rejects the session, triggering an immediate disconnect.


---
logs
open5gs_5gc  | 06/08 12:18:17.561: [amf] INFO: InitialUEMessage (../src/amf/ngap-handler.c:401)
open5gs_5gc  | 06/08 12:18:17.561: [amf] INFO: [Added] Number of gNB-UEs is now 1 (../src/amf/context.c:2550)
open5gs_5gc  | 06/08 12:18:17.561: [amf] INFO:     RAN_UE_NGAP_ID[0] AMF_UE_NGAP_ID[1] TAC[7] CellID[0x66c000] (../src/amf/ngap-handler.c:562)
open5gs_5gc  | 06/08 12:18:17.561: [amf] INFO: [suci-0-001-01-0-0-0-0000000103] Unknown UE by SUCI (../src/amf/context.c:1835)
open5gs_5gc  | 06/08 12:18:17.561: [amf] INFO: [Added] Number of AMF-UEs is now 1 (../src/amf/context.c:1616)
open5gs_5gc  | 06/08 12:18:17.561: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 06/08 12:18:17.561: [gmm] INFO: [suci-0-001-01-0-0-0-0000000103]    SUCI (../src/amf/gmm-handler.c:166)
open5gs_5gc  | 06/08 12:18:17.761: [gmm] WARNING: Authentication failure(Synch failure) (../src/amf/gmm-sm.c:1567)
open5gs_5gc  | 06/08 12:18:18.335: [gmm] INFO: [imsi-001010000000103] Registration complete (../src/amf/gmm-sm.c:2146)
open5gs_5gc  | 06/08 12:18:18.335: [amf] INFO: [imsi-001010000000103] Configuration update command (../src/amf/nas-path.c:612)
open5gs_5gc  | 06/08 12:18:18.335: [gmm] INFO:     UTC [2026-06-08T10:18:18] Timezone[0]/DST[0] (../src/amf/gmm-build.c:559)
open5gs_5gc  | 06/08 12:18:18.335: [gmm] INFO:     LOCAL [2026-06-08T12:18:18] Timezone[7200]/DST[1] (../src/amf/gmm-build.c:564)
open5gs_5gc  | 06/08 12:18:20.657: [amf] INFO: UE Context Release [Action:2] (../src/amf/ngap-handler.c:1698)
open5gs_5gc  | 06/08 12:18:20.657: [amf] INFO:     RAN_UE_NGAP_ID[0] AMF_UE_NGAP_ID[1] (../src/amf/ngap-handler.c:1699)
open5gs_5gc  | 06/08 12:18:20.657: [amf] INFO:     SUCI[suci-0-001-01-0-0-0-0000000103] (../src/amf/ngap-handler.c:1702)
open5gs_5gc  | 06/08 12:18:20.657: [amf] INFO: [Removed] Number of gNB-UEs is now 0 (../src/amf/context.c:2557)

--- 

open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })
open5gs_5gc  | 06/08 12:24:11.161: [amf] INFO: InitialUEMessage (../src/amf/ngap-handler.c:401)
open5gs_5gc  | 06/08 12:24:11.161: [amf] INFO: [Added] Number of gNB-UEs is now 1 (../src/amf/context.c:2550)
open5gs_5gc  | 06/08 12:24:11.161: [amf] INFO:     RAN_UE_NGAP_ID[1] AMF_UE_NGAP_ID[2] TAC[7] CellID[0x66c000] (../src/amf/ngap-handler.c:562)
open5gs_5gc  | 06/08 12:24:11.161: [amf] INFO: [suci-0-001-01-0-0-0-0000000103] Known UE by 5G-S_TMSI[AMF_ID:0x20040,M_TMSI:0xc000034f] (../src/amf/context.c:1849)
open5gs_5gc  | 06/08 12:24:11.161: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 06/08 12:24:11.161: [gmm] INFO: [suci-0-001-01-0-0-0-0000000103]    5G-S_GUTI[AMF_ID:0x20040,M_TMSI:0xc000034f] (../src/amf/gmm-handler.c:179)
open5gs_5gc  | 06/08 12:24:11.525: [pcf] WARNING: NF EndPoint(addr) updated [127.0.0.5:7777] (../src/pcf/npcf-handler.c:113)
open5gs_5gc  | 06/08 12:24:11.719: [gmm] INFO: [imsi-001010000000103] Registration complete (../src/amf/gmm-sm.c:2146)
open5gs_5gc  | 06/08 12:24:11.719: [amf] INFO: [imsi-001010000000103] Configuration update command (../src/amf/nas-path.c:612)
open5gs_5gc  | 06/08 12:24:11.719: [gmm] INFO:     UTC [2026-06-08T10:24:11] Timezone[0]/DST[0] (../src/amf/gmm-build.c:559)
open5gs_5gc  | 06/08 12:24:11.719: [gmm] INFO:     LOCAL [2026-06-08T12:24:11] Timezone[7200]/DST[1] (../src/amf/gmm-build.c:564)
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })
open5gs_5gc  | 06/08 12:24:14.257: [amf] INFO: UE Context Release [Action:2] (../src/amf/ngap-handler.c:1698)
open5gs_5gc  | 06/08 12:24:14.257: [amf] INFO:     RAN_UE_NGAP_ID[1] AMF_UE_NGAP_ID[2] (../src/amf/ngap-handler.c:1699)
open5gs_5gc  | 06/08 12:24:14.257: [amf] INFO:     SUCI[suci-0-001-01-0-0-0-0000000103] (../src/amf/ngap-handler.c:1702)
open5gs_5gc  | 06/08 12:24:14.257: [amf] INFO: [Removed] Number of gNB-UEs is now 0 (../src/amf/context.c:2557)
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 


----
explain the issue 
open5gs_5gc  | 06/08 12:45:41.722: [amf] INFO: InitialUEMessage (../src/amf/ngap-handler.c:401)
open5gs_5gc  | 06/08 12:45:41.722: [amf] INFO: [Added] Number of gNB-UEs is now 1 (../src/amf/context.c:2550)
open5gs_5gc  | 06/08 12:45:41.722: [amf] INFO:     RAN_UE_NGAP_ID[3] AMF_UE_NGAP_ID[4] TAC[7] CellID[0x66c000] (../src/amf/ngap-handler.c:562)
open5gs_5gc  | 06/08 12:45:41.722: [amf] INFO: [suci-0-001-01-0-0-0-0000000103] Known UE by 5G-S_TMSI[AMF_ID:0x20040,M_TMSI:0xc00001bf] (../src/amf/context.c:1849)
open5gs_5gc  | 06/08 12:45:41.722: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 06/08 12:45:41.722: [gmm] INFO: [suci-0-001-01-0-0-0-0000000103]    5G-S_GUTI[AMF_ID:0x20040,M_TMSI:0xc00001bf] (../src/amf/gmm-handler.c:179)
open5gs_5gc  | 06/08 12:45:41.918: [gmm] INFO: [imsi-001010000000103] Registration complete (../src/amf/gmm-sm.c:2146)
open5gs_5gc  | 06/08 12:45:41.918: [amf] INFO: [imsi-001010000000103] Configuration update command (../src/amf/nas-path.c:612)
open5gs_5gc  | 06/08 12:45:41.918: [gmm] INFO:     UTC [2026-06-08T10:45:41] Timezone[0]/DST[0] (../src/amf/gmm-build.c:559)
open5gs_5gc  | 06/08 12:45:41.918: [gmm] INFO:     LOCAL [2026-06-08T12:45:41] Timezone[7200]/DST[1] (../src/amf/gmm-build.c:564)
open5gs_5gc  | 06/08 12:45:42.762: [amf] INFO: [Added] Number of AMF-Sessions is now 1 (../src/amf/context.c:2571)
open5gs_5gc  | 06/08 12:45:42.762: [gmm] INFO: UE SUPI[imsi-001010000000103] DNN[ims] S_NSSAI[SST:1 SD:0x111111] smContextRef [NULL] (../src/amf/gmm-handler.c:1241)
open5gs_5gc  | 06/08 12:45:42.762: [gmm] INFO: SMF Instance [41302890-6325-41f1-a1a3-2b896d29e719] (../src/amf/gmm-handler.c:1280)
open5gs_5gc  | 06/08 12:45:42.762: [smf] INFO: [Added] Number of SMF-UEs is now 1 (../src/smf/context.c:1019)
open5gs_5gc  | 06/08 12:45:42.762: [smf] INFO: [Added] Number of SMF-Sessions is now 1 (../src/smf/context.c:3068)
open5gs_5gc  | 06/08 12:45:42.766: [smf] INFO: UE SUPI[imsi-001010000000103] DNN[ims] IPv4[10.46.0.2] IPv6[] (../src/smf/npcf-handler.c:539)
open5gs_5gc  | 06/08 12:45:42.766: [upf] INFO: [Added] Number of UPF-Sessions is now 1 (../src/upf/context.c:208)
open5gs_5gc  | 06/08 12:45:42.766: [upf] INFO: UE F-SEID[UP:0xeee CP:0xb45] APN[ims] PDN-Type[1] IPv4[10.46.0.2] IPv6[] (../src/upf/context.c:485)
open5gs_5gc  | 06/08 12:45:42.766: [upf] INFO: UE F-SEID[UP:0xeee CP:0xb45] APN[ims] PDN-Type[1] IPv4[10.46.0.2] IPv6[] (../src/upf/context.c:485)
open5gs_5gc  | 06/08 12:45:42.766: [smf] WARNING: Unknown PCO ID:(0x2) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:45:42.766: [smf] WARNING: Unknown PCO ID:(0x23) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:45:42.766: [smf] WARNING: Unknown PCO ID:(0x24) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:45:42.803: [amf] INFO: [imsi-001010000000103:6:11][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })
open5gs_5gc  | 06/08 12:45:49.067: [amf] INFO: [imsi-001010000000103:6:13][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | 06/08 12:45:49.205: [amf] INFO: UE Context Release [Action:2] (../src/amf/ngap-handler.c:1698)
open5gs_5gc  | 06/08 12:45:49.205: [amf] INFO:     RAN_UE_NGAP_ID[3] AMF_UE_NGAP_ID[4] (../src/amf/ngap-handler.c:1699)
open5gs_5gc  | 06/08 12:45:49.205: [amf] INFO:     SUCI[suci-0-001-01-0-0-0-0000000103] (../src/amf/ngap-handler.c:1702)
open5gs_5gc  | 06/08 12:45:49.205: [amf] INFO: [Removed] Number of gNB-UEs is now 0 (../src/amf/context.c:2557)
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })


----
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })
open5gs_5gc  | 06/08 12:48:01.883: [amf] INFO: InitialUEMessage (../src/amf/ngap-handler.c:401)
open5gs_5gc  | 06/08 12:48:01.883: [amf] INFO: [Added] Number of gNB-UEs is now 1 (../src/amf/context.c:2550)
open5gs_5gc  | 06/08 12:48:01.883: [amf] INFO:     RAN_UE_NGAP_ID[4] AMF_UE_NGAP_ID[5] TAC[7] CellID[0x66c000] (../src/amf/ngap-handler.c:562)
open5gs_5gc  | 06/08 12:48:01.883: [amf] INFO: [suci-0-001-01-0-0-0-0000000103] Known UE by 5G-S_TMSI[AMF_ID:0x20040,M_TMSI:0xc00006be] (../src/amf/context.c:1849)
open5gs_5gc  | 06/08 12:48:01.883: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 06/08 12:48:01.883: [gmm] INFO: [suci-0-001-01-0-0-0-0000000103]    5G-S_GUTI[AMF_ID:0x20040,M_TMSI:0xc00006be] (../src/amf/gmm-handler.c:179)
open5gs_5gc  | 06/08 12:48:02.054: [gmm] INFO: [imsi-001010000000103] Registration complete (../src/amf/gmm-sm.c:2146)
open5gs_5gc  | 06/08 12:48:02.054: [amf] INFO: [imsi-001010000000103] Configuration update command (../src/amf/nas-path.c:612)
open5gs_5gc  | 06/08 12:48:02.054: [gmm] INFO:     UTC [2026-06-08T10:48:02] Timezone[0]/DST[0] (../src/amf/gmm-build.c:559)
open5gs_5gc  | 06/08 12:48:02.054: [gmm] INFO:     LOCAL [2026-06-08T12:48:02] Timezone[7200]/DST[1] (../src/amf/gmm-build.c:564)
open5gs_5gc  | 06/08 12:48:02.203: [gmm] INFO: UE SUPI[imsi-001010000000103] DNN[ims] S_NSSAI[SST:1 SD:0x111111] smContextRef [2] (../src/amf/gmm-handler.c:1241)
open5gs_5gc  | 06/08 12:48:02.204: [upf] INFO: [Removed] Number of UPF-sessions is now 0 (../src/upf/context.c:252)
open5gs_5gc  | 06/08 12:48:02.205: [smf] INFO: Removed Session: UE IMSI:[imsi-001010000000103] DNN:[ims:6] IPv4:[10.46.0.2] IPv6:[] (../src/smf/context.c:1672)
open5gs_5gc  | 06/08 12:48:02.205: [smf] INFO: [Removed] Number of SMF-Sessions is now 0 (../src/smf/context.c:3076)
open5gs_5gc  | 06/08 12:48:02.205: [smf] INFO: [Removed] Number of SMF-UEs is now 0 (../src/smf/context.c:1080)
open5gs_5gc  | 06/08 12:48:02.205: [amf] WARNING: [imsi-001010000000103:6] Receive Update SM context(DUPLICATED_PDU_SESSION_ID) (../src/amf/nsmf-handler.c:602)
open5gs_5gc  | 06/08 12:48:02.205: [amf] INFO: [imsi-001010000000103:6:19][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | 06/08 12:48:02.206: [smf] INFO: [Added] Number of SMF-UEs is now 1 (../src/smf/context.c:1019)
open5gs_5gc  | 06/08 12:48:02.206: [smf] INFO: [Added] Number of SMF-Sessions is now 1 (../src/smf/context.c:3068)
open5gs_5gc  | 06/08 12:48:02.208: [smf] INFO: UE SUPI[imsi-001010000000103] DNN[ims] IPv4[10.46.0.3] IPv6[] (../src/smf/npcf-handler.c:539)
open5gs_5gc  | 06/08 12:48:02.209: [upf] INFO: [Added] Number of UPF-Sessions is now 1 (../src/upf/context.c:208)
open5gs_5gc  | 06/08 12:48:02.209: [upf] INFO: UE F-SEID[UP:0x60a CP:0xcc] APN[ims] PDN-Type[1] IPv4[10.46.0.3] IPv6[] (../src/upf/context.c:485)
open5gs_5gc  | 06/08 12:48:02.209: [upf] INFO: UE F-SEID[UP:0x60a CP:0xcc] APN[ims] PDN-Type[1] IPv4[10.46.0.3] IPv6[] (../src/upf/context.c:485)
open5gs_5gc  | 06/08 12:48:02.209: [smf] WARNING: Unknown PCO ID:(0x2) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:48:02.209: [smf] WARNING: Unknown PCO ID:(0x23) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:48:02.209: [smf] WARNING: Unknown PCO ID:(0x24) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:48:02.244: [amf] INFO: [imsi-001010000000103:6:11][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })
open5gs_5gc  | 06/08 12:48:08.349: [amf] INFO: [imsi-001010000000103:6:13][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | 06/08 12:48:08.487: [amf] INFO: UE Context Release [Action:2] (../src/amf/ngap-handler.c:1698)
open5gs_5gc  | 06/08 12:48:08.487: [amf] INFO:     RAN_UE_NGAP_ID[4] AMF_UE_NGAP_ID[5] (../src/amf/ngap-handler.c:1699)
open5gs_5gc  | 06/08 12:48:08.487: [amf] INFO:     SUCI[suci-0-001-01-0-0-0-0000000103] (../src/amf/ngap-handler.c:1702)
open5gs_5gc  | 06/08 12:48:08.487: [amf] INFO: [Removed] Number of gNB-UEs is now 0 (../src/amf/context.c:2557)
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })


----
now what 
pen5gs_5gc  | 06/08 12:49:04.944: [nrf] INFO: [ab072d52-6327-41f1-be22-f34852072c83] Subscription created until 2026-06-09T12:49:04.944476+02:00 [validity_duration:86400] (../src/nrf/nnrf-handler.c:445)
open5gs_5gc  | 06/08 12:49:04.944: [sbi] INFO: [ab072d52-6327-41f1-be22-f34852072c83] Subscription created until 2026-06-09T12:49:04.944476+02:00 [duration:86400,validity:86399.999716,patch:43199.999858] (../lib/sbi/nnrf-handler.c:708)
open5gs_5gc  | Client pings, but there's no entry for page: /
open5gs_5gc  | > Building page: /
open5gs_5gc  |  DONE  Compiled successfully in 1930ms12:49:06 PM
open5gs_5gc  | 
open5gs_5gc  |  WAIT  Compiling...12:49:07 PM
open5gs_5gc  | 
open5gs_5gc  |  DONE  Compiled successfully in 50ms12:49:08 PM
open5gs_5gc  | 
open5gs_5gc  | 06/08 12:49:09.627: [amf] INFO: gNB-N2 accepted[172.16.1.1]:47484 in ng-path module (../src/amf/ngap-sctp.c:113)
open5gs_5gc  | 06/08 12:49:09.627: [amf] INFO: gNB-N2 accepted[172.16.1.1] in master_sm module (../src/amf/amf-sm.c:741)
open5gs_5gc  | 06/08 12:49:09.630: [amf] INFO: [Added] Number of gNBs is now 1 (../src/amf/context.c:1231)
open5gs_5gc  | 06/08 12:49:09.630: [amf] INFO: gNB-N2[172.16.1.1] max_num_of_ostreams : 30 (../src/amf/amf-sm.c:780)
open5gs_5gc  | 06/08 12:49:22.609: [amf] INFO: InitialUEMessage (../src/amf/ngap-handler.c:401)
open5gs_5gc  | 06/08 12:49:22.609: [amf] INFO: [Added] Number of gNB-UEs is now 1 (../src/amf/context.c:2550)
open5gs_5gc  | 06/08 12:49:22.609: [amf] INFO:     RAN_UE_NGAP_ID[0] AMF_UE_NGAP_ID[1] TAC[7] CellID[0x66c000] (../src/amf/ngap-handler.c:562)
open5gs_5gc  | 06/08 12:49:22.609: [amf] INFO: Unknown UE by 5G-S_TMSI[AMF_ID:0x20040,M_TMSI:0xc0000668] (../src/amf/context.c:1853)
open5gs_5gc  | 06/08 12:49:22.609: [amf] INFO: [Added] Number of AMF-UEs is now 1 (../src/amf/context.c:1616)
open5gs_5gc  | 06/08 12:49:22.609: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 06/08 12:49:22.609: [gmm] INFO: [Unknown ID]    5G-S_GUTI[AMF_ID:0x20040,M_TMSI:0xc0000668] (../src/amf/gmm-handler.c:179)
open5gs_5gc  | 06/08 12:49:22.669: [gmm] INFO: Identity response (../src/amf/gmm-sm.c:1346)
open5gs_5gc  | 06/08 12:49:22.669: [gmm] INFO: [suci-0-001-01-0-0-0-0000000103]    SUCI (../src/amf/gmm-handler.c:921)
open5gs_5gc  | 06/08 12:49:22.889: [gmm] WARNING: Authentication failure(Synch failure) (../src/amf/gmm-sm.c:1567)
open5gs_5gc  | 06/08 12:49:23.423: [gmm] INFO: [imsi-001010000000103] Registration complete (../src/amf/gmm-sm.c:2146)
open5gs_5gc  | 06/08 12:49:23.423: [amf] INFO: [imsi-001010000000103] Configuration update command (../src/amf/nas-path.c:612)
open5gs_5gc  | 06/08 12:49:23.423: [gmm] INFO:     UTC [2026-06-08T10:49:23] Timezone[0]/DST[0] (../src/amf/gmm-build.c:559)
open5gs_5gc  | 06/08 12:49:23.423: [gmm] INFO:     LOCAL [2026-06-08T12:49:23] Timezone[7200]/DST[1] (../src/amf/gmm-build.c:564)
open5gs_5gc  | 06/08 12:49:23.629: [amf] INFO: [Added] Number of AMF-Sessions is now 1 (../src/amf/context.c:2571)
open5gs_5gc  | 06/08 12:49:23.629: [gmm] INFO: UE SUPI[imsi-001010000000103] DNN[ims] S_NSSAI[SST:1 SD:0x111111] smContextRef [NULL] (../src/amf/gmm-handler.c:1241)
open5gs_5gc  | 06/08 12:49:23.629: [gmm] INFO: No SMF Instance (../src/amf/gmm-handler.c:1278)
open5gs_5gc  | 06/08 12:49:23.631: [sbi] WARNING: [SMF] (NRF-discover) NF has already been added [aad3430c-6327-41f1-959f-91676c47d156:1] (../lib/sbi/nnrf-handler.c:1057)
open5gs_5gc  | 06/08 12:49:23.631: [sbi] WARNING: NF EndPoint(addr) updated [127.0.0.4:80] (../lib/sbi/context.c:2174)
open5gs_5gc  | 06/08 12:49:23.631: [sbi] WARNING: NF EndPoint(addr) updated [127.0.0.4:7777] (../lib/sbi/context.c:1917)
open5gs_5gc  | 06/08 12:49:23.631: [sbi] INFO: [SMF] (NF-discover) NF Profile updated [aad3430c-6327-41f1-959f-91676c47d156:1] (../lib/sbi/nnrf-handler.c:1095)
open5gs_5gc  | 06/08 12:49:23.631: [smf] INFO: [Added] Number of SMF-UEs is now 1 (../src/smf/context.c:1019)
open5gs_5gc  | 06/08 12:49:23.631: [smf] INFO: [Added] Number of SMF-Sessions is now 1 (../src/smf/context.c:3068)
open5gs_5gc  | 06/08 12:49:23.633: [sbi] INFO: [SMF] (SCP-discover) NF registered [aad3430c-6327-41f1-959f-91676c47d156:1] (../lib/sbi/path.c:211)
open5gs_5gc  | 06/08 12:49:23.635: [smf] INFO: UE SUPI[imsi-001010000000103] DNN[ims] IPv4[10.46.0.1] IPv6[] (../src/smf/npcf-handler.c:539)
open5gs_5gc  | 06/08 12:49:23.635: [upf] INFO: [Added] Number of UPF-Sessions is now 1 (../src/upf/context.c:208)
open5gs_5gc  | 06/08 12:49:23.635: [gtp] INFO: gtp_connect() [127.0.0.4]:2152 (../lib/gtp/path.c:60)
open5gs_5gc  | 06/08 12:49:23.635: [upf] INFO: UE F-SEID[UP:0xc86 CP:0xea8] APN[ims] PDN-Type[1] IPv4[10.46.0.1] IPv6[] (../src/upf/context.c:485)
open5gs_5gc  | 06/08 12:49:23.635: [upf] INFO: UE F-SEID[UP:0xc86 CP:0xea8] APN[ims] PDN-Type[1] IPv4[10.46.0.1] IPv6[] (../src/upf/context.c:485)
open5gs_5gc  | 06/08 12:49:23.635: [gtp] INFO: gtp_connect() [172.16.1.2]:2152 (../lib/gtp/path.c:60)
open5gs_5gc  | 06/08 12:49:23.635: [smf] WARNING: Unknown PCO ID:(0x2) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:49:23.635: [smf] WARNING: Unknown PCO ID:(0x23) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:49:23.635: [smf] WARNING: Unknown PCO ID:(0x24) (../src/smf/context.c:3011)
open5gs_5gc  | 06/08 12:49:23.690: [gtp] INFO: gtp_connect() [172.16.1.1]:2152 (../lib/gtp/path.c:60)
open5gs_5gc  | 06/08 12:49:23.692: [amf] INFO: [imsi-001010000000103:6:11][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | 06/08 12:49:30.320: [amf] INFO: [imsi-001010000000103:6:13][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | 06/08 12:49:30.459: [amf] INFO: UE Context Release [Action:2] (../src/amf/ngap-handler.c:1698)
open5gs_5gc  | 06/08 12:49:30.459: [amf] INFO:     RAN_UE_NGAP_ID[0] AMF_UE_NGAP_ID[1] (../src/amf/ngap-handler.c:1699)
open5gs_5gc  | 06/08 12:49:30.459: [amf] INFO:     SUCI[suci-0-001-01-0-0-0-0000000103] (../src/amf/ngap-handler.c:1702)
open5gs_5gc  | 06/08 12:49:30.459: [amf] INFO: [Removed] Number of gNB-UEs is now 0 (../src/amf/context.c:2557)