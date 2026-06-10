# 20260426 — USRP B210 disappears after PC restart (No UHD Devices Found)

- **Date:** 2026-04-26 (approx — track is undated; placed in the late-Apr SDR window)
- **Area:** SDR / hardware
- **Status:** Investigating
- **Components:** USRP B210 (NI2901), UHD 4.1.0.5, host USB

> Source: `tracks/sdr-device-lost.md`.

## Summary
- After initial setup, `uhd_find_devices` saw the B210 fine. **After a PC restart,
  `uhd_find_devices` reported "No UHD Devices Found."**
- Classic B210/USB enumeration loss across a reboot — typically USB power/enumeration or
  missing firmware load, not a dead device.

## Context / setup
- Host `testbed@testbed`, UHD `4.1.0.5-3`, device B210 / NI2901, serial `310C56E`,
  USB-3 attached.

## Investigation / what was determined
- Before restart:
  ```
  $ uhd_find_devices
  -- UHD Device 0 : serial 310C56E, name NI2901, product B210, type b200
  ```
- After restart:
  ```
  $ uhd_find_devices
  No UHD Devices Found
  ```

## Root cause
- **Not determined in the track.** The usual culprits for a B210 vanishing after reboot:
  - USB autosuspend / power-save re-enabled on boot (the device drops off the bus).
  - The B210 FX3 firmware/FPGA image not (re)loaded — UHD images missing or
    `uhd_images_downloader` not run after an update.
  - A USB-3 port/cable re-enumeration issue (try re-plugging / a different port).

## Resolution / workaround
- Open. Suggested recovery order:
  1. Re-plug the B210 (different USB-3 port/cable) and re-run `uhd_find_devices`.
  2. `uhd_usrp_probe --args="type=b200"` to force enumeration / surface a firmware error.
  3. Ensure UHD images are present (`uhd_images_downloader`).
  4. Disable USB autosuspend (`usbcore.autosuspend=-1`) — same fix noted in the
     outgoing-packets-dropped track for keeping the B210 awake.

## Lessons / gotchas
- A B210 that worked then shows "No UHD Devices Found" after reboot is almost always
  USB power-save / firmware-load, not hardware death — check the bus before assuming a
  failed radio.

## References
- `tracks/sdr-device-lost.md`.
- Related USB-autosuspend note: [20260427-host-sdr-outgoing-packets-dropped.md](./20260427-host-sdr-outgoing-packets-dropped.md).
