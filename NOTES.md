# ZMQ vs UHD Config differences   
The ZMQ gNB config is set for band 3 with 20 MHz and uses 15 kHz SCS, while the UHD gNB config targets band 78 with 20 MHz and uses 30 kHz SCS. See gnb_zmq.yml and gnb_uhd.yml.

Why:
- **Band 3 (lower FR1)** commonly uses 15 kHz SCS in example configs; it yields more PRBs for the same bandwidth and is a typical “baseline” numerology.
- **Band 78 (higher FR1, mid-band)** often uses 30 kHz SCS; it shortens OFDM symbols and is a common choice in 3.5 GHz deployments.

Both still land on the same $23.04 Msps base rate because the FFT size shifts with SCS:  
- For 20 MHz at 15 kHz, srsRAN uses $N_FFT=1536, so $f_s = 1536 . 15 kHz = 23.04 MHz.  
- For 20 MHz at 30 kHz, srsRAN uses $N_FFT=768, so $f_s = 768 . 30 kHz = 23.04 MHz.

# **5G RAN Metrics Reference Table**

| Metric | Full Form | Meaning | Role in the Network |
| :--- | :--- | :--- | :--- |
| **MCS** | **Modulation and Coding Scheme** | The "density" of data (Modulation) and the amount of error correction (Coding). | Acts as the **Gearbox**. High MCS = High Speed; Low MCS = High Reliability. |
| **BLER** | **Block Error Rate** | The percentage of data blocks that arrived corrupted and couldn't be fixed. | Acts as the **Quality Score**. Used to trigger "downshifting" of MCS if errors exceed 10%. |
| **CQI** | **Channel Quality Indicator** | A 0–15 score sent by the UE to report how "good" the signal looks. | The **UE's Feedback**. It tells the gNB: "I have a great signal, feel free to use a high MCS." |
| **RI** | **Rank Indicator** | The number of independent data streams (layers) supported by the MIMO channel. | The **Capacity Multiplier**. RI 2 doubles throughput by sending two streams on the same frequency. |
| **SNR** | **Signal-to-Noise Ratio** | The ratio of the desired signal power to the background noise/interference. | The **Clarity Metric**. Determines if the signal is "clean" enough to decode high modulation (like 256QAM). |
| **RSRP** | **Reference Signal Received Power** | The absolute power level of the radio signal (measured in dBm). | The **Coverage Metric**. Primarily used to determine if the UE is "in range" or needs to handover. |
| **TA** | **Timing Advance** | The time offset (in microseconds) the UE must use to transmit "early." | The **Distance Compensator**. Ensures the UE's signal arrives at the gNB at the exact right nanosecond. |
| **PHR** | **Power Headroom Report** | The difference between the UE's max transmit power and its current power. | The **Battery/Power Gauge**. Tells the gNB if the UE has enough "strength" left to increase data rates. |
| **Thp (DL/UL)** | **Throughput** | The actual volume of user data successfully transmitted per second. | The **End-User Result**. The final measurement of how much "useful" data (Netflix, pings, etc.) is moving. |


# **How These Metrics Connect (The "Chain of Logic")**

To troubleshoot your setup, you can follow the logic the RIC uses:

1.  **Environment:** The **TA** and **RSRP** tell you if the UE is physically in a good spot.
2.  **Quality:** If the **SNR** and **CQI** are high, the radio link is "clean."
3.  **Potential:** The **RI** tells you if you can double your speed using multiple antennas.
4.  **Strategy:** Based on the above, the gNB picks an **MCS** (how fast to talk).
5.  **Execution:** If the **BLER** stays low, the strategy is working.
6.  **Result:** The **Throughput** is the final output of this entire process.
