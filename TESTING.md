'''
for all commands ensure the desired ue netns is used.
'''

---


# connecting to a public iperf server 
```
ip netns exec ue1 iperf3 -c paris.bbr.iperf.bytel.fr -p 9200 -t 3600
```

# testing locally 
- start iperf server in the open5gs server 
```
iperf3 -s 
``` 
- start a iperf client in the ue 
```
ip netns exec ue1 iperf3 -c 10.45.0.1 -t 3600
```