tmux kill-session -t gnb
tmux kill-session -t gnbw

kubectl -n open5gs delete -k ../configs/srsRAN/srsran-gnb

echo "Waiting for gNB to be deleted..."
# wait for gnb to be deleted
sleep 30


echo "Restarting gNB and gNB wrapper..."

kubectl -n open5gs apply -k ../configs/srsRAN/srsran-gnb

tmux new-session -d -s gnbw "kubectl -n open5gs exec -it \$(kubectl -n open5gs get pods -l app=srsran,component=gnb -o name) -- sh -c 'apt update && apt-get install -y python3-pip && /srsran/config/wrapper.sh'"
tmux ls 
echo "Waiting for gNB wrapper to be ready..."
# wait for gnbw to be ready
sleep 15
tmux new-session -d -s gnb "kubectl -n open5gs exec -it \$(kubectl -n open5gs get pods -l app=srsran,component=gnb -o name) -- sh -c '/srsran/config/start_gnb.sh'"
tmux ls 