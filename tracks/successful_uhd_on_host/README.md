# Configuration 
## Open5gs 
- available at [open5gs.yaml](../../srsRAN_Project/gnb-uhd/project-config/open5gs-5gc.yml.in) and [open5gs.env](../../srsRAN_Project/gnb-uhd/project-config/open5gs.env)
- the slice configuration in the open5gs is set in hexadecimal format (currently set to 111111)
- the open5gs runs in privilged mode but has its own docker network. This is done so the gnb and open5gs dont have any port contentions.  
- the open5gs server is assigned a static IP so the gnb can be configured to connec to that IP.

## gNB 
- the slice configuration in the gnb is set in decimal format (currently set to 1118481)
- the gnb runs in network mode host to simplify network configuration since it was becoming difficult to manage docker netwroks  

## UE connection process
- the UE name,imsi,key,op_type,op_c,amf,qci,ip_alloc,apn are set in the srsRAN_Project/gnb-uhd/project-config/subscriber_db.csv
- the open5gs is not configured to set the ue network slice using subscriber csv, the sst value defaults to 1 and the sd is set  to empty.
- In our case teh UE device requests the sst 1 and sd 111111 hence we use the open5gs UI (available at localhost:9999) to set the sd value. This can be improved in the future by configuring [add_user.py](../../srsRAN_Project/docker/open5gs/add_users.py) to setting the nework slice configuration using the subscriber csv.
- To set the sst and the sd for the UE do the following:
    1. go to localhost:9999
    2. select your UE 
    3. click on edit 
    4. scroll down to slice configuration section 
    5. fill in the SD value and set SST if required 
- Once the open5gs is configured, try connecting the UE to the gNB as follows:
    1. Goto settings > sim card & mobile networks 
    2. Now you should see SIM 1 & 2. Click on the testbed SIM 
    3. Now you should see Mobile networks click on it 
    4. Click on Automatically select network and opt Yes for all prompts 
    5. the device will search for all 5G netowrks 
    6. once the saerch is complete, you should see srsRan 5G or Gradient 5G network 
    7. Select the one of the available 5G network 
- This process is the happy case. I case of problems review the [gnb.logs](srsRAN_Project/gnb-uhd/gnb-storage/gnb.log) and [open5gs.log](srsRAN_Project/gnb-uhd/5gc.log) 



## current subscribers  
sub1,001010000000101,0C0A34601D4F07677303652C0462535B,opc,63BFA50EE6523365FF14C1F45F88737B,8000,9,10.45.0.2,internet
sub2,001010000000102,0C0A34601D4F07677303652C0462535D,opc,63BFA50EE6523365FF14C1F45F88737D,8000,9,10.45.0.3,internet


# Current Known Issues 
## Hardware/kernel processing issues
- srsRAN provides a [script](../../srsRAN_Project/scripts/srsran_performance) to configure OS to switch to performance mode and optimise it for real time processing.
- Despite executing this script and configuring the PC we still see 
```log
2026-04-27T10:43:56.555904 [RF      ] [W] Real-time failure in RF: underflow
2026-04-27T10:43:56.556313 [RF      ] [W] Real-time failure in RF: underflow
2026-04-27T10:43:56.557899 [RF      ] [W] Real-time failure in RF: late
2026-04-27T10:43:56.557956 [RF      ] [W] Real-time failure in RF: late
2026-04-27T10:43:56.558004 [RF      ] [W] Real-time failure in RF: late
2026-04-27T10:43:56.558083 [RF      ] [W] Real-time failure in RF: late
2026-04-27T10:43:56.558162 [RF      ] [W] Real-time failure in RF: late
```

### What the script configures 
- Sets CPU Governor to Performance: Forces all CPU cores to run at their maximum clock speed. This prevents the CPU from "sleeping" or down-clocking, which is a major cause of "late" radio packets.

- Disables DRM KMS Polling: Turns off the background "polling" that the graphics driver uses to check for new displays. This reduces "jitter" (micro-interruptions) in the CPU that can interfere with real-time signal processing.

- Increases Network Buffer Sizes: Expands the Linux kernel's memory limits for sending and receiving data (rmem and wmem) to 32MB. This is vital if you are using an Ethernet-based SDR (like a USRP N210/N310) to prevent packets from being dropped at the network card level.

- Interactive Safety: Uses a "prompt-and-apply" approach, asking for your permission before modifying system files, and requires sudo privileges to write to protected kernel parameters.

### Problems 
1. The "Late" Error
    The computer sent a packet of data to the SDR, but it arrived after the scheduled time for it to be transmitted over the air.
    The Result: The radio drops that packet entirely because it can't "transmit in the past." This causes sudden drops in throughput and potentially disconnects the UE if too many signaling messages are missed.

2. The "Underflow" Error (U)
    This means the SDR’s internal buffer ran out of samples to transmit because the computer didn't send them fast enough.
    The Result: The radio literally "runs dry" and stops transmitting for a split second. To the UE, this looks like a sudden, sharp fade in signal or a momentary radio link failure.

## Repeated UE context modification
The network is forcing the UE to disconnect its data session

### Why it is related to the RF problems
When the SDR hits "RF late" or "underflow" errors, the following chain reaction occurs:
    - Missing Signaling: The RRC Reconfiguration or Keep-Alive messages are dropped or corrupted because the radio didn't transmit them in time.
    - Timer Expiry: The 5G Core (Open5GS) or the gNB (srsRAN) waits for an acknowledgment (ACK) from the UE. Because of the RF failure, that ACK never arrives.
    - Session Release: The AMF/SMF assumes the UE has lost its radio link or is no longer responsive. It then sends the PDUSessionResourceReleaseCommand (seen in your logs) to tear down the tunnel because it thinks the connection is dead.

```log
2026-04-27T11:25:31.257118 [RRC     ] [I] ue=16 c-rnti=0x4611: DCCH UL ulInformationTransfer
2026-04-27T11:25:31.257130 [NGAP    ] [I] Tx PDU ue=16 ran_ue=16 amf_ue=17: UplinkNASTransport
2026-04-27T11:25:31.257380 [SCHED   ] [I] [    30.6] Slot decisions pci=1 t=26us (1 PDSCH, 0 PUSCHs, 0 PUCCHs): DL: ue=1 c-rnti=0x4611 h_id=3 ss_id=2 rb=[0..2) k1=11 newtx=true rv=0 tbs=36 ri=1 dl_bo=0
2026-04-27T11:25:31.257396 [RLC     ] [I] du=0 ue=1 SRB2 DL: TX status PDU. pdu_len=3 grant_len=4
2026-04-27T11:25:31.257399 [MAC     ] [I] [    30.6] DL PDU: ue=1 rnti=0x4611 size=36: SDU: lcid=2 nof_sdus=1 total_size=5
2026-04-27T11:25:31.257422 [PHY     ] [I] [    30.6] PDCCH: rnti=0x4611 ss_id=2 format=1_1 cce=12 al=2 t=17.6us
2026-04-27T11:25:31.257435 [PHY     ] [I] [    30.6] PDSCH: rnti=0x4611 h_id=3 k1=11 prb=[0, 2) symb=[2, 8) mod=16QAM rv=0 tbs=36 t=19.5us
2026-04-27T11:25:31.259450 [NGAP    ] [I] Rx PDU ue=16 ran_ue=16 amf_ue=17: PDUSessionResourceReleaseCommand
2026-04-27T11:25:31.259471 [CU-CP-E1] [I] Tx PDU ue=16 cu_cp_ue=13 cu_up_ue=13: BearerContextReleaseCommand
2026-04-27T11:25:31.259476 [CU-UP-E1] [I] Rx PDU ue=1 cu_cp_ue=13 cu_up_ue=13: BearerContextReleaseCommand
2026-04-27T11:25:31.259485 [GTPU    ] [I] Tunnel removed. teid=0x000001
2026-04-27T11:25:31.260190 [CU-UP   ] [I] ue=1: Disconnecting PDU session with psi=10
2026-04-27T11:25:31.261153 [CU-UP-E1] [I] Tx PDU cu_cp_ue=13 cu_up_ue=13: BearerContextReleaseComplete
2026-04-27T11:25:31.261159 [CU-CP-E1] [I] Rx PDU ue=16 cu_cp_ue=13 cu_up_ue=13: BearerContextReleaseComplete
2026-04-27T11:25:31.261182 [CU-CP-F1] [I] Tx PDU du=0 ue=16 cu_ue=16 du_ue=16: UEContextModificationRequest
2026-04-27T11:25:31.261210 [DU-F1   ] [I] Rx PDU du=0 ue=1 cu_ue=16 du_ue=16: UEContextModificationRequest
2026-04-27T11:25:31.261220 [DU-MNG  ] [I] ue=1 rnti=0x4611 proc="UE Configuration": Procedure started....
2026-04-27T11:25:31.261879 [MAC     ] [I] [   30.15] ue=1 crnti=0x4611 proc="Sched UE Config": successfully finished
2026-04-27T11:25:31.261886 [MAC     ] [I] [   30.15] ue=1 crnti=0x4611 proc="MAC UE Reconfiguration": finished successfully
2026-04-27T11:25:31.261891 [DU-MNG  ] [I] ue=1 rnti=0x4611 proc="UE Configuration": Procedure finished successfully.
2026-04-27T11:25:31.261945 [DU-F1   ] [I] Tx PDU du=0 ue=1 cu_ue=16 du_ue=16: UEContextModificationResponse
2026-04-27T11:25:31.261986 [CU-CP-F1] [I] Rx PDU du=0 ue=16 cu_ue=16 du_ue=16: UEContextModificationResponse
2026-04-27T11:25:31.261992 [CU-CP-F1] [I] ue=16 du_ue=16 cu_ue=16 proc="UE Context Modification Procedure": Procedure finished successfully
2026-04-27T11:25:31.262034 [RRC     ] [I] ue=16 c-rnti=0x4611: DCCH DL rrcReconfiguration
2026-04-27T11:25:31.262043 [PDCP    ] [I] ue=16 SRB1 DL: TX PDU. type=data pdu_len=40 sn=7 count=7 is_retx=false
2026-04-27T11:25:31.262049 [CU-CP-F1] [I] Tx PDU du=0 ue=16 cu_ue=16 du_ue=16: DLRRCMessageTransfer
2026-04-27T11:25:31.262053 [DU-F1   ] [I] Rx PDU du=0 ue=1 cu_ue=16 du_ue=16: DLRRCMessageTransfer
``` 