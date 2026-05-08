# 1. Start Server in ue0
./traffic_gen_server.sh -n ue0 -p 5201

# 2. Start all traffic types in background loops
while true; do
  # VoIP
  ./traffic_gen_client.sh -n ue1 -s 10.41.0.3 -t "voip" -b 64k -l 160 -p udp &
  
  # Heterogeneous TCP
  ./traffic_gen_client.sh -n ue1 -s 10.41.0.3 -t "high_rate" -b 3M -l 1280 -p tcp &
  ./traffic_gen_client.sh -n ue1 -s 10.41.0.3 -t "med_rate" -b 750k -l 1280 -p tcp &
  ./traffic_gen_client.sh -n ue1 -s 10.41.0.3 -t "low_rate" -b 150k -l 1280 -p tcp &

  wait # Wait for all 10-second tests to finish
  sleep 5
done