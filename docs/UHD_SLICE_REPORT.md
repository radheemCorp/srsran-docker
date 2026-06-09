# Report — UHD testbed slice/core problems: analysis, reproduction, and fixes

## Summary

The failures captured in [problems_uhd.md](problems_uhd.md) on the B200/UHD testbed
(UE registers, then drops ~2–7 s later with no data) are **5G-core / configuration**
faults, not radio problems. The chain was traced to network-slice (S-NSSAI)
misconfiguration plus one YAML syntax slip. Because the faults are RF-independent,
they were reproduced deterministically on the **ZMQ** stack (no SDR) and the
**fixes were applied to the UHD configs**.

See [UHD_SLICE_TROUBLESHOOTING.md](UHD_SLICE_TROUBLESHOOTING.md) for the exact errors,
reproduction steps, and verification commands.

## Root causes

| # | Problem (symptom) | Root cause |
|---|---|---|
| 1 | `NG-Setup failure: Cannot find S_NSSAI`, `connection refused!!!` | gNB and core advertised different S-NSSAI |
| 2 | AMF won't boot: `No amf.plmn_support`, `FATAL ... Aborted` | stray `-` split the PLMN profile into two invalid YAML items |
| 3 | (root of #1) slices differ despite "same" digits | **Open5GS reads `sd` as hex, srsRAN reads `sd` as decimal** |
| 5 | registers but no PDU session (`smContextRef [NULL]`, 7 s release) | cell never declared the SD slice (`cell_cfg.slicing` missing) + IMS/DNN gap |
| 4 | `Unknown PCO 0x2/0x23/0x24` | phone requests IMS PCOs the SMF doesn't echo — **benign**, not the drop cause |
| 6 | `Authentication failure(Synch failure)` | USIM SQN out of sync with UDM — auto-recovers |

**The pivotal insight (#3):** `0x111111` (hex, what Open5GS wants) equals `1118481`
in decimal (what srsRAN wants). Writing `sd: 111111` in the gNB selects
`0x01B207` — a different slice — so NG Setup is rejected with `slice-not-supported`.

## Fixes applied (this commit)

All in `srsRAN_Project/gnb-uhd/`:

1. **`project-config/gnb/gnb_uhd.yml`** — added the missing `cell_cfg.slicing` block
   (`sst: 1`, `sd: 1118481`). The gNB already advertised the right slice to the AMF
   via `tai_slice_support_list` (`sd: "1118481"`), but the **cell** never declared it,
   so a PDU session on `sst=1,sd=0x111111` was not admitted even after NG Setup
   succeeded. This is the slice dimension of problem #5.
2. **`project-config/open5gs.env`** — `SD_VALUE` was already correct (`0x111111`);
   added a comment documenting the hex(core)/decimal(gNB) rule so the trap can't recur.

> The reference variant `project-config/gnb/gnb_rf_b200_tdd_n78_20mhz.yml` (band n78,
> **not deployed** — kept only as a reference) carries `sd: 16777215` (`0xFFFFFF`, the
> no-SD wildcard). It is left as-is; if it is ever mounted against this core it must
> first be set to `sd: 1118481` and given a matching `cell_cfg.slicing` block.

The core (`open5gs-5gc.yml.in`) was already syntactically clean (no stray hyphen) and
sources its slice from `SST_VALUE`/`SD_VALUE` — no change needed beyond the comment.

## What was verified

Reproduced and then resolved on the single-cell ZMQ stack (`branch
repro/uhd-slice-problems`, isolated worktree):

- **#2** stray hyphen → `No amf.plmn_support` / `FATAL ... Aborted` (exit 139); removing
  it → `AMF initialize...done`, healthy.
- **#1/#3** core `sd: 0x111111` + gNB `sd: 111111` → gNB `"NG Setup Procedure" failed.
  AMF NGAP cause: "slice-not-supported"`; AMF `Cannot find S_NSSAI`. Setting gNB
  `sd: 1118481` → `Connected to AMF`, `Cell was activated`, AMF accepts the gNB.

## Open items — require the UHD testbed (cannot be reproduced with srsUE)

These are tied to a real COTS phone + USIM:

- **#4 PCO / #5 IMS-DNN:** the failing UE uses `DNN[ims]` while `subscriber_db.csv`
  provisions `apn=internet`. After the slice fix above, if the phone still drops,
  verify the subscriber is provisioned with the DNN the phone actually requests (and a
  matching session/UPF subnet), or force the phone's APN to `internet`. The
  `Unknown PCO` warnings are benign.
- **#6 SQN synch:** harmless if `Registration complete` follows; if it loops, reset the
  subscriber `sqn` in mongo / re-provision the USIM.

Verification commands for each are in the troubleshooting doc.
