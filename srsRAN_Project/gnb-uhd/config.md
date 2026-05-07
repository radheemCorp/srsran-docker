# UHD gNB Configuration Guide

This document explains how the srsRAN Project gNB UHD configuration maps to the RF and NR cell settings used by a B210-class SDR.

## 1. Overview

The gNB configuration defines a UHD-based RF frontend and the 5G NR cell parameters. For UHD RF, the most important matches are:

- gNB `ru_sdr.device_driver = uhd`
- gNB `ru_sdr.device_args` matches the connected device serial and type
- gNB `srate` matches the SDR sample rate
- NR band, bandwidth, and SCS match the intended deployment

## 2. gNB configuration values

From `project-config/gnb/gnb_uhd.yml`:

- `ru_sdr.device_driver: uhd`
- `ru_sdr.device_args: type=b200,serial=310C56E,num_recv_frames=64,num_send_frames=64`
- `srate: 23.04`
- `cell_cfg.band: 78`
- `cell_cfg.channel_bandwidth_MHz: 20`
- `cell_cfg.common_scs: 30`
- `cell_cfg.dl_arfcn: 632628`
- `cell_cfg.plmn: "00101"`
- `cell_cfg.tac: 7`
- `cell_cfg.pci: 1`

This means the gNB is configured to use a 20 MHz NR cell on band 78 with 30 kHz subcarrier spacing, driven by a UHD B210 device running at 23.04 MHz sample rate.

## 3. How base sample rate is derived

srsRAN selects an FFT size that can carry the requested NR bandwidth at the chosen subcarrier spacing. The base sample rate follows:

- `base_srate_hz = fft_size * common_scs * 1000`

For 20 MHz at 30 kHz SCS, srsRAN uses an `fft_size` of `768` (enough bins to hold the 20 MHz carrier plus guard). So:

- `base_srate_hz = 768 * 30,000 = 23,040,000`

That is why the config uses `srate=23.04`.

## 4. Why 20 MHz matches 51 PRBs at 30 kHz

For 5G NR in FR1 with 30 kHz subcarrier spacing:

- Each PRB comprises `12` subcarriers.
- A 20 MHz carrier contains `51` PRBs at 30 kHz.

The formula is:

- `bandwidth_hz = channel_bandwidth_MHz * 1e6`
- `subcarrier_spacing_hz = common_scs * 1000`
- `resource_block_spacing_hz = 12 * subcarrier_spacing_hz`
- `approximate_prbs = bandwidth_hz / resource_block_spacing_hz`

Plugging in the values:

- `bandwidth_hz = 20 * 1e6 = 20,000,000`
- `subcarrier_spacing_hz = 30 * 1000 = 30,000`
- `resource_block_spacing_hz = 12 * 30,000 = 360,000`
- `approximate_prbs = 20,000,000 / 360,000 ≈ 55.56`

NR standard tables allocate `51` PRBs for 20 MHz at 30 kHz, after accounting for guard bands and bandwidth occupancy.

## 5. Practical advice

- If UHD initialization fails, verify the B210 serial in `device_args` and that the device is connected.
- Keep `srate=23.04` aligned with the UHD device configuration.
- Keep the NR band, bandwidth, and SCS consistent with the intended RF deployment.
