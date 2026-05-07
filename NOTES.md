# ZMQ vs UHD Config differences   
The ZMQ gNB config is set for band 3 with 20 MHz and uses 15 kHz SCS, while the UHD gNB config targets band 78 with 20 MHz and uses 30 kHz SCS. See gnb_zmq.yml and gnb_uhd.yml.

Why:
- **Band 3 (lower FR1)** commonly uses 15 kHz SCS in example configs; it yields more PRBs for the same bandwidth and is a typical “baseline” numerology.
- **Band 78 (higher FR1, mid-band)** often uses 30 kHz SCS; it shortens OFDM symbols and is a common choice in 3.5 GHz deployments.

Both still land on the same $23.04 Msps base rate because the FFT size shifts with SCS:  
- For 20 MHz at 15 kHz, srsRAN uses $N_FFT=1536, so $f_s = 1536 . 15 kHz = 23.04 MHz.  
- For 20 MHz at 30 kHz, srsRAN uses $N_FFT=768, so $f_s = 768 . 30 kHz = 23.04 MHz.
