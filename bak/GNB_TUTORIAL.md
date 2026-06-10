# srsRAN gNB with srsUE Tutorial

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Hardware and Software](#hardware-and-software)
4. [Over-the-Air Setup](#over-the-air-setup)
5. [ZeroMQ-based Setup](#zeromq-based-setup)
6. [Running the Network](#running-the-network)
7. [Testing the Network](#testing-the-network)

---

## Overview

This tutorial demonstrates how to create an end-to-end fully open-source 5G network using:
- **srsUE**: A prototype 5G User Equipment (from srsRAN 4G)
- **srsRAN Project gNodeB**: A 5G CU/DU solution
- **Open5GS 5G Core Network**: A 5G core network implementation

### Supported Use Cases
- Over-the-air setups using USRP hardware
- ZeroMQ-based software simulations
- Multi-UE emulation

### Important Limitations

The current srsUE implementation has the following feature limitations in 5G SA mode:
- Limited to 15 kHz Sub-Carrier Spacing (SCS) - only FDD bands can be used
- Limited to 5, 10, 15, or 20 MHz Bandwidth (BW)
- Handover is not supported

**Note**: 5G extensions in srsUE are no longer in active development but receive maintenance updates. It is intended for proof-of-concept and initial testing, not for deployment-ready solutions.

---

## Prerequisites

### Required Software
1. **srsRAN 4G** (23.11 or later)
   - Contains the srsUE implementation
   - [Installation guide](https://docs.srsran.com/projects/4g/en/latest/general/source/1_installation.html)

2. **srsRAN Project**
   - The 5G gNodeB implementation
   - [GitHub repository](https://github.com/srsran/srsRAN_project)

3. **Open5GS**
   - 5G Core Network implementation
   - [GitHub](https://github.com/open5gs/open5gs)
   - [Quickstart Guide](https://open5gs.org/open5gs/docs/guide/01-quickstart/)

4. **ZeroMQ** (for simulation-based setups)
   - Used for over-the-network RF driver
   - [Installation guide](https://zeromq.org/)

### Recommended Operating System
- Ubuntu 22.04.1 LTS or later

---

## Hardware and Software

### Over-the-Air Setup Requirements

#### Minimum Setup:
- PC with Ubuntu 22.04.1 LTS
- srsRAN Project (latest version)
- srsRAN 4G (23.11 or later)
- Two Ettus Research USRP B210s (connected over USB 3)
- Open5GS 5G Core
- ZeroMQ library

#### Optional but Recommended:
- 10 MHz external reference clock or GPSDO (e.g., Leo Bodnar GPSDO) for better clock accuracy
  - Provides time synchronization for accurate RF communication

---

## Over-the-Air Setup

### Architecture
```
Workstation PC
├── srsRAN gNB (with USRP B210)
│   └── Connected to: Open5GS 5G Core (Docker)
├── srsRAN 4G with srsUE (with USRP B210)
└── Open5GS 5G Core (Docker Container)
```

### Configuration

#### Download Configuration Files

You can find the configuration files in the [srsRAN Project repository](https://github.com/srsran/srsRAN_Project/tree/main/configs):
- **gNB FDD config**: `gnb_rf_b210_fdd_srsUE.yml`
- **srsUE config**: Download from the tutorial documentation

#### gNB Configuration

Update the following sections in your gNB configuration file:

##### 1. AMF Connection

The gNB must connect to the AMF in the 5G core network:

```yaml
cu_cp:
  amf:
    addr: 10.53.1.2                 # The address or hostname of the AMF
    port: 38412
    bind_addr: 10.53.1.1            # Local IP that the gNB binds to
    supported_tracking_areas:
      - tac: 7
        plmn_list:
          - plmn: "00101"
            tai_slice_support_list:
              - sst: 1
  inactivity_timer: 7200            # UE/PDU Session/DRB inactivity timer (1-7200)
```

##### 2. RF Front-End Configuration

Configure the USRP B210 device:

```yaml
ru_sdr:
  device_driver: uhd                # RF driver name
  device_args: type=b200            # Device-specific arguments
  clock: external                   # Use external reference clock with USRP B210
  srate: 23.04                      # RF sample rate (adjust based on bandwidth)
  tx_gain: 75                       # Transmit gain (may need adjustment)
  rx_gain: 75                       # Receive gain (may need adjustment)
```

##### 3. Cell Parameters

Configure the 5G cell characteristics:

```yaml
cell_cfg:
  dl_arfcn: 368500                  # Downlink carrier ARFCN (center frequency)
  band: 3                           # NR band
  channel_bandwidth_MHz: 20         # Bandwidth in MHz
  common_scs: 15                    # Subcarrier spacing in kHz
  plmn: "00101"                     # PLMN broadcasted by the gNB
  tac: 7                            # Tracking area code
  pdcch:
    common:
      ss0_index: 0                  # Search space zero index for srsUE
      coreset0_index: 12            # CORESET Zero index for srsUE
    dedicated:
      ss2_type: common              # Search Space type
      dci_format_0_1_and_1_1: false # DCI format (fallback)
  prach:
    prach_config_index: 1           # PRACH config for srsUE
```

#### srsUE Configuration

Update the following sections in your srsUE `ue_rf.conf` configuration file:

##### 1. RF Parameters

```ini
[rf]
freq_offset = 0
tx_gain = 50
rx_gain = 40
srate = 23.04e6
nof_antennas = 1

device_name = uhd
device_args = clock=external        # Use external reference clock with USRP B210
time_adv_nsamples = 300
```

##### 2. LTE Carrier Disable

Disable LTE to force 5G NR carrier usage:

```ini
[rat.eutra]
dl_earfcn = 2850
nof_carriers = 0                    # Disable LTE carriers
```

##### 3. NR Carrier Configuration

Configure 5G NR parameters:

```ini
[rat.nr]
bands = 3
nof_carriers = 1
max_nof_prb = 106
nof_prb = 106
```

**Bandwidth to PRB Mapping**:
| Bandwidth (MHz) | PRBs  |
|-----------------|-------|
| 5               | 25    |
| 10              | 52    |
| 15              | 79    |
| 20              | 106   |

##### 4. RRC Configuration

Set the release and UE category:

```ini
[rrc]
release = 15
ue_category = 4
```

##### 5. USIM Credentials

Default USIM credentials (used by Open5GS):

```ini
[usim]
mode = soft
algo = milenage
opc = 63BFA50EE6523365FF14C1F45F88737D
k = 00112233445566778899AABBCCDDEEFF
imsi = 001010123456780
imei = 353490069873319
```

##### 6. APN Configuration

Enable the APN:

```ini
[nas]
apn = internet
apn_protocol = ipv4
```

---

## ZeroMQ-based Setup

### Architecture
```
Single Host Machine
├── srsRAN gNB (with ZMQ RF driver)
│   └── Connected to: Open5GS 5G Core (Docker)
├── srsRAN 4G with srsUE (with ZMQ RF driver, network namespace)
└── Open5GS 5G Core (Docker Container)
```

### Benefits
- No hardware required (simulation-based)
- Run on a single host machine
- Easier debugging and development
- Lower latency than over-the-air

### Configuration

#### 1. Create Network Namespace for srsUE

```bash
sudo ip netns add ue1
```

Verify the network namespace:

```bash
sudo ip netns list
```

#### 2. gNB Configuration

Replace the `ru_sdr` section to use ZMQ:

```yaml
ru_sdr:
  device_driver: zmq
  device_args: tx_port=tcp://127.0.0.1:2000,rx_port=tcp://127.0.0.1:2001,base_srate=23.04e6
  srate: 23.04
  tx_gain: 75
  rx_gain: 75
```

#### 3. srsUE RF Configuration

Update the `[rf]` section:

```ini
[rf]
freq_offset = 0
tx_gain = 50
rx_gain = 40
srate = 23.04e6
nof_antennas = 1

device_name = zmq
device_args = tx_port=tcp://127.0.0.1:2001,rx_port=tcp://127.0.0.1:2000,base_srate=23.04e6
```

#### 4. srsUE Gateway Configuration

Update the `[gw]` section to use the network namespace:

```ini
[gw]
netns = ue1
ip_devname = tun_srsue
ip_netmask = 255.255.255.0
```

---

## Running the Network

### Startup Order

**Important**: Always start the components in this order:

1. **5G Core Network** (Open5GS)
2. **gNB**
3. **UE** (srsUE)

### 1. Start Open5GS 5G Core

Start the dockerized Open5GS from the srsRAN Project:

```bash
cd ./srsRAN_Project/docker
docker compose up --build 5gc
```

**Note**: The Open5GS configuration is pre-configured to work with srsRAN Project, and the UE database is pre-populated with the default srsUE credentials.

### 2. Start gNB

Run gNB from the build folder:

```bash
cd ./srsRAN_Project/build/apps/gnb/
sudo ./gnb -c ./gnb.yaml
```

#### Expected gNB Output

```
-- == srsRAN gNB (commit 374200dee) == --

Connecting to AMF on 10.53.1.2:38412
[INFO] [UHD] linux; GNU C++ version 9.2.1 20200304; Boost_107100; UHD_3.15.0.0-2build5
[INFO] [LOGGING] Fastpath logging disabled at runtime.
Making USRP object with args 'type=b200'
[INFO] [B200] Detected Device: B210
[INFO] [B200] Operating over USB 3.
[INFO] [B200] Initialize CODEC control...
[INFO] [B200] Initialize Radio control...
[INFO] [B200] Setting master clock rate selection to 'manual'.
[INFO] [B200] Asking for clock rate 23.040000 MHz...
[INFO] [B200] Actually got clock rate 23.040000 MHz.
Cell pci=1, bw=20 MHz, dl_arfcn=368500 (n3), dl_freq=1842.5 MHz, ul_freq=1747.5 MHz
```

**Successful Connection Indicator**:
The message "Connecting to AMF on 10.53.1.2:38412" indicates gNB initiated a connection to the core.

### 3. Start srsUE

Run srsUE from the build folder:

```bash
cd ./srsRAN_4G/build/srsue/
sudo ./srsue ue_rf.conf
```

#### Expected srsUE Output

```
Reading configuration file ./ue_rf.conf...
Built in Release mode using commit eea87b1d8 on branch master.
Opening 1 channels in RF device=default with args=clock=external
...
Opening USRP channels=1, args: type=b200,master_clock_rate=23.04e6
[INFO] [UHD RF] RF UHD Generic instance constructed
[INFO] [B200] Detected Device: B210
...
RF device 'UHD' successfully opened
Setting manual TX/RX offset to 300 samples
Waiting PHY to initialize ... done!
Attaching UE...
Random Access Transmission: prach_occasion=0, preamble_index=0, ra-rnti=0x39, tti=2094
Random Access Complete.     c-rnti=0x4602, ta=0
RRC Connected
PDU Session Establishment successful. IP: 10.45.1.2
RRC NR reconfiguration successful.
```

**Successful Connection Indicators**:
- `PDU Session Establishment successful. IP: 10.45.1.2`
- `RRC NR reconfiguration successful.`

### 4. Verify Open5GS Connection

Check the Open5GS console for gNB registration:

```
Open5GS | 04/17 10:00:43.567: [amf] INFO: gNB-N2 accepted [10.53.1.1]:41578 in ng-path module
Open5GS | 04/17 10:00:43.567: [amf] INFO: gNB-N2 accepted [10.53.1.1] in master_sm module
Open5GS | 04/17 10:00:43.567: [amf] INFO: [Added] Number of gNBs is now 1
```

---

## Testing the Network

### Routing Configuration (Over-the-Air Setup)

Before testing connectivity, configure routing on the **host machine** running Open5GS:

```bash
# Add route to UE network
sudo ip route add 10.45.0.0/16 via 10.53.1.2

# Verify routing table
route -n
```

Expected routing entries:

```
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         192.168.0.1     0.0.0.0         UG    100    0        0 eno1
10.45.0.0       10.53.1.2       255.255.0.0     UG    0      0        0 br-dfa5521eb807
10.53.1.0       0.0.0.0         255.255.255.0   U     0      0        0 br-dfa5521eb807
```

Add default route from UE network:

```bash
sudo ip route add default via 10.45.1.1 dev tun_srsue
```

### Routing Configuration (ZeroMQ Setup)

For ZeroMQ-based setup, configure routing in the UE's network namespace:

```bash
# Same host machine routing
sudo ip route add 10.45.0.0/16 via 10.53.1.2

# In UE's network namespace
sudo ip netns exec ue1 ip route add default via 10.45.1.1 dev tun_srsue
```

### 1. Ping Test

#### Uplink Test (from UE)

Test connectivity from the UE to the core network:

```bash
ping 10.45.1.1
```

#### Downlink Test (from Core)

Test connectivity from the core network to the UE (run on the host machine):

```bash
ping 10.45.1.2
```

**Note**: The UE IP address is displayed in the srsUE console output and may change on reconnection.

#### Example Ping Output

```
PING 10.45.1.1 (10.45.1.1) 56(84) bytes of data.
64 bytes from 10.45.1.1: icmp_seq=1 ttl=64 time=39.9 ms
64 bytes from 10.45.1.1: icmp_seq=2 ttl=64 time=38.9 ms
64 bytes from 10.45.1.1: icmp_seq=3 ttl=64 time=37.0 ms
64 bytes from 10.45.1.1: icmp_seq=4 ttl=64 time=36.1 ms

--- 10.45.1.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3004ms
rtt min/avg/max/mdev = 36.085/37.952/39.859/1.493 ms
```

### 2. iPerf3 Throughput Test

iPerf3 is a tool for generating traffic (TCP/UDP) and measuring network performance.

#### Setup Server (on Core Network Machine)

Start the iPerf3 server:

```bash
iperf3 -s -i 1
```

#### Setup Client (on UE Machine)

Run iPerf3 client from the UE:

```bash
# TCP test - 60 seconds
iperf3 -c 10.53.1.1 -i 1 -t 60

# UDP test - 10 Mbps for 60 seconds
iperf3 -c 10.53.1.1 -i 1 -t 60 -u -b 10M
```

#### Example Server Output

```
iperf3 -s -i 1
-----------------------------------------------------------
Server listening on 5201
-----------------------------------------------------------
Accepted connection from 10.45.1.2, port 40544
[  5] local 10.45.1.1 port 5201 connected to 10.45.1.2 port 40546
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-1.00   sec  1.20 MBytes  10.1 Mbits/sec
[  5]   1.00-2.00   sec  1.22 MBytes  10.2 Mbits/sec
[  5]   2.00-3.00   sec  1.16 MBytes  9.71 Mbits/sec
[  5]   3.00-4.00   sec  1.12 MBytes  9.44 Mbits/sec
[  5]   4.00-5.00   sec  1.25 MBytes  10.5 Mbits/sec
[  5]   5.00-6.00   sec  1.25 MBytes  10.5 Mbits/sec
```

#### Example Client Output

```
iperf3 -c 10.45.1.1 -i 1 -t 60 -u -b 10M
Connecting to host 10.45.1.1, port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec  1.20 MBytes  10.1 Mbits/sec    0    117 KBytes
[  5]   1.00-2.00   sec  1.25 MBytes  10.5 Mbits/sec    0    130 KBytes
[  5]   2.00-3.00   sec  1.25 MBytes  10.5 Mbits/sec    0    130 KBytes
[  5]   3.00-4.00   sec  1.12 MBytes  9.44 Mbits/sec    0    130 KBytes
[  5]   4.00-5.00   sec  1.25 MBytes  10.5 Mbits/sec    0    130 KBytes
[  5]   5.00-6.00   sec  1.12 MBytes  9.44 Mbits/sec    0    130 KBytes
```

### 3. Monitor Console Traces

#### srsUE Console Metrics

While running iPerf3, srsUE displays real-time metrics:

```
---------Signal-----------|--------DL--------|-------UL---------
rat  pci  rsrp  pl  cfo  | mcs  snr iter brate  bler  ta_us | mcs buff  brate bler
 nr   1    0    0  -457m |  27   43  1.3  274k   0%  0.0   |  27  136k  13M   0%
 nr   1    0    0  -122m |  27   43  1.4  285k   0%  0.0   |  27   0.0  13M   0%
 nr   1    0    0  -282m |  27   43  1.3  267k   0%  0.0   |  27   47k  13M   0%
```

**Key Metrics**:
- **rsrp**: Reference Signal Received Power
- **snr**: Signal-to-Noise Ratio
- **mcs**: Modulation and Coding Scheme
- **brate**: Bit rate (DL/UL)
- **bler**: Block Error Rate

#### gNB Console Metrics

The gNB also displays real-time per-UE metrics:

```
----------DL-------|----------UL-----------
pci rnti cqi mcs brate  ok nok (%) | pusch mcs brate  ok nok (%)  bsr
 1 4601  15  27  275k 328   0 0% | 23.2   28   13M 398   0 0% 55.5k
 1 4601  15  27  266k 336   0 0% | 23.1   28   13M 387   0 0%  0.0
 1 4601  15  27  284k 349   0 0% | 23.1   28   13M 410   1 0%  0.0
```

**Key Metrics**:
- **rnti**: Radio Network Temporary Identifier
- **cqi**: Channel Quality Indicator
- **mcs**: Modulation and Coding Scheme
- **ok/nok**: Successful/Failed transmissions
- **bsr**: Buffer Status Report

---

## Troubleshooting

### Common Issues

#### gNB Cannot Connect to AMF
- Check that Open5GS core is running
- Verify IP addresses in gNB configuration match Open5GS setup
- Check firewall rules allow traffic on port 38412

#### UE Cannot Find gNB
- Verify gNB is running and configured on the correct frequency
- Check USRP clock synchronization
- Ensure RF cables are properly connected (if using over-the-air)

#### Low Throughput
- Adjust TX/RX gain values based on signal conditions
- Check for clock drift or frequency offset
- Verify proper RF shielding and antenna placement

#### ZeroMQ Connection Issues
- Verify ports 2000 and 2001 are not in use
- Check that network namespace `ue1` is created
- Ensure both gNB and srsUE are using matching ZMQ port configurations

---

## References

- [srsRAN Project Documentation](https://docs.srsran.com)
- [srsRAN 4G GitHub Repository](https://github.com/srsran/srsRAN_4G)
- [srsRAN Project GitHub Repository](https://github.com/srsran/srsRAN_project)
- [Open5GS Documentation](https://open5gs.org)
- [ZeroMQ Documentation](https://zeromq.org/get-started)

---

**Last Updated**: April 12, 2026
**Based on**: srsRAN Project Documentation - srsRAN gNB with srsUE Tutorial
