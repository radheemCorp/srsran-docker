## 1. What is happening?
When the Android UE tries to connect to the Open5GS AMF, they perform a "Mutual Authentication" dance. The goal is for the UE to prove it is a valid subscriber, and for the Core to prove it is a real network.

1.  **The Identity Exchange:** The UE sends its identity (concealed as a SUCI) to the Core.
2.  **The Challenge:** Open5GS looks up that subscriber in its database. It sees the **K** and **OPc** keys in tracks/successful_uhd_ue_connect/gnb-uhd/project-config/subscriber_db.csv. It then generates a random number ($RAND$) and uses a complex cryptographic algorithm (Milenage or Tuak) to calculate an Authentication Token ($AUTN$) and an expected response ($XRES$).
3.  **The UE Verification:** The Core sends $RAND$ and $AUTN$ to the phone. The phone passes these to the SIM card.
4.  **The SIM Math:** The SIM card uses its own internal **K** and **OPc** to "solve" the math. 
    * If the SIM’s internal $AUTN$ matches the Core’s $AUTN$, the phone trusts the network.
    * The SIM then sends back its own response ($RES$).
5.  **The Final Match:** If the UE's $RES$ matches the Core's $XRES$, the phone is "authenticated" and encryption keys are created.



---

## 2. Why it is likely failing
When using a physical Android device, the failure usually stems from one of two "Security Walls":

### A. The "Secret Key" Mismatch (K and OPc)
* **The Problem:** The **K** and **OPc** keys are never transmitted over the air. They are only stored inside the SIM card's secure hardware and the Open5GS database.

### B. SQN (Sequence Number) Out of Sync
* **The Problem:** The SIM and the Core keep a counter of how many times they have authenticated to prevent "replay attacks" (where a hacker records an old handshake and tries to reuse it).
* **Why it fails:** If the Open5GS database has been resetting or switching between different Cores, the Core's counter might be `1` while the SIM is expecting `100`. This causes a **Sync Failure**.

---

## 3. Summary of the Current State
Logs show that the Open5GS Core is active and the Network Functions (AUSF and UDM) are ready to perform these checks. However, because we are using a commercial Android device, the connection is failing at the "Trust" level.

**To fix this, you must ensure:**
1.  **Hardware:** we are using **Programmable SIM card** we nweed to know the exact K and OPc.
2.  **Software:** You must enter those exact values into the Open5GS. 
3.  **Network:** The Android APN must match the DNN (e.g., `internet`).
