# after initial setup
```bash
testbed@testbed:~/testbed/srsran-docker$ uhd_find_devices
[INFO] [UHD] linux; GNU C++ version 11.2.0; Boost_107400; UHD_4.1.0.5-3
--------------------------------------------------
-- UHD Device 0
--------------------------------------------------
Device Address:
    serial: 310C56E
    name: NI2901
    product: B210
    type: b200
```
# after pc restart 
```bash
testbed@testbed:~/testbed/srsran-docker$ uhd_find_devices
[INFO] [UHD] linux; GNU C++ version 11.2.0; Boost_107400; UHD_4.1.0.5-3
No UHD Devices Found
testbed@testbed:~/testbed/srsran-docker$ 
```