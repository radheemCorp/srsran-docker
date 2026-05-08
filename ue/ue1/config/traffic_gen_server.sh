#!/bin/bash
# Usage: ./traffic_gen_server.sh -n ue0 -p 5201

while getopts n:p: flag
do
    case "${flag}" in
        n) NS=${OPTARG};;
        p) PORT=${OPTARG};;
    esac
done

# Defaults
NS=${NS:-"ue0"}
PORT=${PORT:-5201}

echo "Starting iperf3 server in namespace $NS on port $PORT..."
ip netns exec "$NS" pkill iperf3
ip netns exec "$NS" iperf3 -s -p "$PORT" -D

if [ $? -eq 0 ]; then
    echo "Server is running in background (PID: $(ip netns exec $NS pgrep iperf3))"
else
    echo "Error starting server"
    exit 1
fi