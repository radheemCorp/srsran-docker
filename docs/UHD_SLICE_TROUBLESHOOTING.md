# Troubleshooting — slice (S-NSSAI) & core config on the UHD/ZMQ stack

Error → cause → fix for the problems in [problems_uhd.md](problems_uhd.md). All of
them are 5G-core/config issues (RF-independent), so they were reproduced on the ZMQ
stack with no SDR. See [UHD_SLICE_REPORT.md](UHD_SLICE_REPORT.md) for the summary and
the list of fixes applied to `srsRAN_Project/gnb-uhd/`.

## The one rule that prevents most of this

**Open5GS parses `sd` as HEXADECIMAL; srsRAN parses `sd` as DECIMAL.**
They only agree when the gNB's decimal value equals the core's hex value:

| Core (Open5GS) `SD_VALUE` | gNB (srsRAN) `sd` | Same slice? |
|---|---|---|
| `0x111111` | `1118481` | ✅ yes (`0x111111 == 1118481`) |
| `0x111111` | `111111` | ❌ no (`111111 == 0x01B207`) |
| `0x111111` | `16777215` | ❌ no (`0xFFFFFF`, no-SD wildcard) |

Convert: `printf '%d\n' 0x111111` → `1118481`; `printf '0x%X\n' 1118481` → `0x111111`.

A gNB declares its slice in **three** places, all of which must agree with the core:
`cu_cp...tai_slice_support_list` (advertised in NG Setup) **and** `cell_cfg.slicing`
(what the cell actually admits). Missing the second one lets NG Setup pass but blocks
PDU sessions.

---

## Symptom: AMF won't start — `No amf.plmn_support`, `FATAL ... Aborted`

```
[amf] WARNING: Ignore plmn : s_nssai(0) mcc(001), mnc(01)
[amf] WARNING: Ignore plmn : s_nssai(2) mcc((null)), mnc((null))
[amf] ERROR:   No amf.plmn_support in 'open5gs-5gc.yml'
[app] FATAL:   Open5GS initialization failed. Aborted        (container exits 139)
```
**Cause:** a stray `-` made `s_nssai` its own list item, splitting one PLMN profile
into `{plmn_id}` (no slice) + `{s_nssai}` (no PLMN). Both invalid → zero profiles.

**Fix:** `s_nssai` must be a key inside the same map as `plmn_id` (aligned under it,
not under the list dash):
```yaml
  plmn_support:
    - plmn_id:
        mcc: 001
        mnc: 01
      s_nssai:            # same indent as plmn_id  (NOT "    - s_nssai:")
        - sst: 1
          sd: 0x111111
```

---

## Symptom: gNB rejected at NG Setup — `slice-not-supported`

gNB:
```
N2: Connection to AMF on <ip>:38412 completed
"NG Setup Procedure" failed. AMF NGAP cause: "slice-not-supported"
srsRAN ERROR: CU-CP failed to connect to AMF
```
AMF:
```
[amf] WARNING: NG-Setup failure:
[amf] WARNING:     Cannot find S_NSSAI. Check 'amf.plmn_support.s_nssai' configuration
[amf] INFO:    gNB-N2[<ip>] connection refused!!!
```
**Cause:** the gNB's advertised S-NSSAI (`tai_slice_support_list`) doesn't match the
core's `plmn_support.s_nssai`. Almost always the hex/decimal `sd` mistake above.

**Fix:** make `cu_cp...tai_slice_support_list.sd` the decimal of the core's hex SD
(`0x111111` → `1118481`). In the UHD config that is `gnb_uhd.yml`.

---

## Symptom: UE registers, then dropped after ~2–7 s, no data plane

```
[gmm] Registration complete
[gmm] UE SUPI[...] DNN[ims] S_NSSAI[SST:1 SD:0x111111] smContextRef [NULL]
...
[amf] UE Context Release [Action:2]   (~7 s later)
```
**Two independent causes — check both:**

1. **Cell doesn't admit the SD slice.** NG Setup uses `tai_slice_support_list`, but the
   PDU session also needs `cell_cfg.slicing` to declare the same `sst`+`sd`. If that
   block is missing the cell defaults to `sst=1`/no-SD and rejects the session.
   **Fix:** add to the cell (done in `gnb_uhd.yml`):
   ```yaml
   cell_cfg:
     ...
     slicing:
       - sst: 1
         sd: 1118481
   ```
2. **DNN/IMS gap (needs the testbed + phone).** The phone requests `DNN[ims]`, but
   `subscriber_db.csv` provisions `apn=internet`. Provision the subscriber with the DNN
   the phone requests (and a matching `smf`/`upf` session subnet), or force the phone's
   APN to `internet`. *Verify:* if `internet` attaches and `ims` doesn't, it is a DNN
   provisioning gap, not RF. Packet-check N3: `tcpdump -i <n3> udp port 2152` during
   the 7 s window.

---

## Benign / self-healing (don't chase these)

- `[smf] WARNING: Unknown PCO ID:(0x2|0x23|0x24)` — the phone asking for IMS PCOs the
  SMF doesn't echo. Harmless; an IP is still assigned. Not the drop cause.
- `[gmm] WARNING: Authentication failure(Synch failure)` — USIM SQN out of sync;
  Open5GS resynchronizes and the next attempt shows `Registration complete`. Only act
  if it loops (reset subscriber `sqn` in mongo / re-provision the USIM).

---

## Reproduce on ZMQ (no SDR)

Single-cell ZMQ stack, `srsRAN_Project/gnb-zmq/`, `open5gs_5gc` + `srsran_gnb` only:

```bash
# #2 AMF crash: add a stray '-' before s_nssai in open5gs-5gc.yml.in, then
docker compose up -d 5gc --force-recreate
docker logs open5gs_5gc 2>&1 | grep -iE "No amf.plmn_support|Aborted"

# #1/#3 slice mismatch: core sd: 0x111111, gNB sd: 111111 (the bug), then
docker compose up -d 5gc gnb --force-recreate
docker exec srsran_gnb sh -c 'grep -aE "slice-not-supported|NG Setup" /tmp/gnb.log'
docker logs open5gs_5gc 2>&1 | grep -iE "Cannot find S_NSSAI"
# fix: gNB sd: 1118481  -> "Connected to AMF", "Cell was activated"
```

## Quick verification

```bash
docker exec srsran_gnb sh -c 'grep -aE "NG Setup|Connected to AMF|Cell was activated|slice-not-supported" /tmp/gnb.log'
docker logs open5gs_5gc 2>&1 | grep -aiE "NG-Setup failure|Cannot find S_NSSAI|Added.*gNB|No amf.plmn_support"
```
