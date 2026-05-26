
## VOIP traffic between two UEs
- start iperf server in ue1 
```
docker compose exec srsran_ue_host  ip netns exec ue1 iperf3 -s
``` 
- start a iperf client in the ue 
```
docker compose exec srsran_ue_host  ip netns exec ue2 iperf3 -c 10.45.0.2 -t 3600 -b 64k -l 160
```

