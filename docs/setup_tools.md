# install ovs-ctl 
```bash
sudo apt update
sudo apt install -y openvswitch-switch

sudo systemctl status openvswitch-switch
ovs-vsctl --version
```

# install uhd tools

```bash 
sudo apt update
sudo apt install libuhd-dev uhd-host -y
sudo /usr/lib/uhd/utils/uhd_images_downloader.py
```

# find device 
```bash
uhd_find_devices
```


# benchmark 
```bash 
/usr/lib/uhd/examples/benchmark_rate --args="type=b200" --duration 10 --rx_rate 23.04e6 --tx_rate 23.04e6
```

# additional performance configurations for gnb uhd 
2. Increase Transmit Queue Length (txqueuelen)

Your output shows qlen 1000. This is the "waiting room" for outgoing packets. For a gNB, this is too small and is likely why you saw "outgoing packets dropped" earlier.

    Command: sudo ifconfig enp2s0 txqueuelen 10000


1. Maximize the Ring Buffers

Run the following command to tell the hardware to use its full capacity:
Bash

sudo ethtool -G enp2s0 rx 4096 tx 4096
- verify change 
ethtool -g enp2s0