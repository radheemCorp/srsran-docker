# Slice configuration 
## Open5gs 
- the slice configuration in the open5gs is set in hexadecimal format (currently set to 111111)
- the open5gs runs in privilged mode but has its own docker network 
- the open5gs server is assigned a static ip so the gnb can be configured to connec to that ip.

## gnb 
- the slice configuration in the gnb is set in decimal format (currently set to 1118481)
- the gnb runs in network mode host to simplify network configuration since it was becoming difficult to manage docker netwroks  

## UE connection process
- the UE name,imsi,key,op_type,op_c,amf,qci,ip_alloc,apn are set in the srsRAN_Project/gnb-uhd/project-config/subscriber_db.csv
- the open5gs is not configured to set the ue network slice using subscriber csv, the sst value defaults to 1 and the sd is set empty.
- In our case teh UE device requests the sd 111111 hence we use the open5gs UI (available at localhost:9999) to set the sd value. This can be improved in the future by configuring srsRAN_Project/docker/open5gs/add_users.py to setting the nework slice configuration using the subscriber csv.




sub1,001010000000101,0C0A34601D4F07677303652C0462535B,opc,63BFA50EE6523365FF14C1F45F88737B,8000,9,10.45.0.2,internet
sub2,001010000000102,0C0A34601D4F07677303652C0462535D,opc,63BFA50EE6523365FF14C1F45F88737D,8000,9,10.45.0.3,internet



