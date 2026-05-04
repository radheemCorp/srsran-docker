2. Increase Transmit Queue Length (txqueuelen)

Your output shows qlen 1000. This is the "waiting room" for outgoing packets. For a gNB, this is too small and is likely why you saw "outgoing packets dropped" earlier.

    Command: sudo ifconfig enp2s0 txqueuelen 10000


1. Maximize the Ring Buffers

Run the following command to tell the hardware to use its full capacity:
Bash

sudo ethtool -G enp2s0 rx 4096 tx 4096
- verify change 
ethtool -g enp2s0