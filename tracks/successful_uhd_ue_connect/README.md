testbed@testbed:~/testbed/srsran-docker/srsRAN_Project/gnb-uhd$ docker compose logs -f 5gc | grep --line-buffered -i -E '001010000000101|001010000000102|imsi|registration|attach'
open5gs_5gc  | Mongoose: subscribers.ensureIndex({ imsi: 1 }, { unique: true, background: true })
open5gs_5gc  | 04/24 11:14:37.740: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 04/24 11:14:38.533: [gmm] INFO: [imsi-001010000000101] Registration complete (../src/amf/gmm-sm.c:2146)
open5gs_5gc  | 04/24 11:14:38.533: [amf] INFO: [imsi-001010000000101] Configuration update command (../src/amf/nas-path.c:612)
open5gs_5gc  | 04/24 11:14:42.685: [gmm] INFO: UE SUPI[imsi-001010000000101] DNN[ims] S_NSSAI[SST:1 SD:0xffffff] smContextRef [NULL] (../src/amf/gmm-handler.c:1241)
open5gs_5gc  | 04/24 11:14:42.694: [smf] INFO: UE SUPI[imsi-001010000000101] DNN[ims] IPv4[10.45.0.1] IPv6[] (../src/smf/npcf-handler.c:539)
open5gs_5gc  | 04/24 11:14:42.742: [amf] INFO: [imsi-001010000000101:5:11][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | 04/24 11:14:48.913: [amf] INFO: [imsi-001010000000101:5:13][0:0:NULL] /nsmf-pdusession/v1/sm-contexts/{smContextRef}/modify (../src/amf/nsmf-handler.c:837)
open5gs_5gc  | 04/24 11:23:09.088: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 04/24 11:23:09.090: [smf] INFO: Removed Session: UE IMSI:[imsi-001010000000101] DNN:[ims:5] IPv4:[10.45.0.1] IPv6:[] (../src/smf/context.c:1672)
open5gs_5gc  | 04/24 11:23:09.091: [amf] INFO: [imsi-001010000000101:5] Release SM context [204] (../src/amf/amf-sm.c:491)
open5gs_5gc  | 04/24 11:23:09.091: [amf] INFO: [imsi-001010000000101:5] Release SM Context [state:31] (../src/amf/nsmf-handler.c:1027)
open5gs_5gc  | 04/24 11:23:09.488: [amf] WARNING: [suci-0-001-01-0-0-0-0000000101] Registration reject [62] (../src/amf/nas-path.c:219)
open5gs_5gc  | 04/24 11:23:19.573: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 04/24 11:23:19.953: [amf] WARNING: [suci-0-001-01-0-0-0-0000000101] Registration reject [62] (../src/amf/nas-path.c:219)
open5gs_5gc  | 04/24 11:23:30.073: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 04/24 11:23:30.433: [amf] WARNING: [suci-0-001-01-0-0-0-0000000101] Registration reject [62] (../src/amf/nas-path.c:219)
open5gs_5gc  | 04/24 11:23:40.533: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 04/24 11:23:40.893: [amf] WARNING: [suci-0-001-01-0-0-0-0000000101] Registration reject [62] (../src/amf/nas-path.c:219)
open5gs_5gc  | 04/24 11:23:50.978: [gmm] INFO: Registration request (../src/amf/gmm-sm.c:1165)
open5gs_5gc  | 04/24 11:23:51.338: [amf] WARNING: [suci-0-001-01-0-0-0-0000000101] Registration reject [62] (../src/amf/nas-path.c:219)
^C

1. Phase 1: Successful Attach (11:14:37)

At the start, the UE (IMSI ...101) connects perfectly.

    Registration Request & Complete: The UE talks to the AMF, authenticates, and is accepted into the network.

    PDU Session Establishment: The SMF assigns the IP 10.45.0.1 and establishes a session for the ims DNN.

    At this point, the UE has data/voice connectivity.

2. Phase 2: The Sudden Drop (11:23:09)

About 9 minutes later, the connection is torn down.

    Removed Session: The SMF explicitly deletes the session and releases the "SM Context."

    The Trigger: This usually happens because either the UE moved out of coverage, the gNB lost the connection, or the UE sent a "De-registration" request to try and restart the connection.

3. Phase 3: The "Reject 62" Loop (11:23:09 – 11:23:51)

This is where your current problem lies. The UE is trying to re-register every 10 seconds, but the AMF is flat-out rejecting it.

    Registration Reject [62]: In 5G (3GPP TS 24.501), Cause #62 means "No network slices available."

    The Conflict:

        Your UE is requesting a specific slice (S-NSSAI).

        Earlier logs showed it was using SST:1 SD:0xffffff.

        After the drop, the AMF decided that this slice is no longer valid for this subscriber or is not supported on this Tracking Area (TAC).
Why is this happening?

There are two likely culprits for a Reject 62:

    Configuration Mismatch: Your subscriber_db.csv defines the user, but perhaps the slice information in your open5gs-5gc.yml or the gNB config doesn't perfectly match what the UE is requesting.

    State Mismatch: The Core might still think a session exists in a "zombie" state for that IMSI, and it's blocking new registrations until the old one fully clears from the database.