To verify the connection between your gNB and the Open5GS core, you need to focus on two primary interfaces: the **Control Plane (N2)** and the **User Plane (N3)**.

### 1. Control Plane: NGAP (N2 Interface)
This is the most critical first step. The gNB must establish an SCTP association with the Access and Mobility Management Function (**AMF**) of Open5GS.

* **Protocol:** **SCTP** (Stream Control Transmission Protocol)
* **Port:** **38412**
* **Verification:**
    * **Logs:** Check the AMF logs (`tail -f /var/log/open5gs/amf.log`). You should see a message like `NG-Setup-Request received` and `NG-Setup-Response sent`.
    * **Network:** Run `netstat -tunlp | grep 38412` on the core machine to ensure the AMF is listening.
    * **Packet Capture:** Use Wireshark or `tcpdump` to look for **SCTP** traffic. You want to see the "SCTP INIT" and "INIT ACK" handshake.

### 2. User Plane: GTP-U (N3 Interface)
Once a UE (User Equipment) tries to connect and browse data, the gNB communicates with the User Plane Function (**UPF**).

* **Protocol:** **GTP-U** (GPRS Tunneling Protocol User Plane over UDP)
* **Port:** **2152**
* **Verification:**
    * **Logs:** Check the UPF logs (`tail -f /var/log/open5gs/upf.log`).
    * **Traffic:** This port only becomes active when there is actual user data flowing. You can verify this by attempting to ping from the UE to an external network (e.g., `8.8.8.8`).

---

### Quick Verification Summary Table

| Interface | Function | Protocol | Port | Open5GS Component |
| :--- | :--- | :--- | :--- | :--- |
| **N2** | Control/Signaling | **SCTP** | **38412** | AMF |
| **N3** | User Data | **UDP** | **2152** | UPF |
| **SBI** | Service Based Architecture | **HTTP/2** | **7777** | NRF/AMF/SMF (Internal) |

### Troubleshooting Checklist
* **Firewalls:** Ensure your OS firewall (ufw/iptables) isn't blocking **SCTP 38412** or **UDP 2152**. 
* **IP Binding:** In your `amf.yaml` and `upf.yaml`, ensure the `ngap` and `gtpu` addresses are set to the actual IP address of your network interface (e.g., `192.168.x.x`) rather than `127.0.0.1` if the gNB is on a different machine.
* **SCTP Support:** If you are running in a container (Docker/Kubernetes), ensure the kernel has the SCTP module loaded (`lsmod | grep sctp`).

Would you like the specific `tcpdump` commands to capture this traffic while you restart your gNB?