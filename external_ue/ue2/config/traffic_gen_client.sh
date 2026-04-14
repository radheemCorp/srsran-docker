#!/bin/bash
# Usage example: 
# ./traffic_gen_client.sh -n ue1 -s 10.41.0.3 -t voip -b 64k -l 160 -p udp
# ./traffic_gen_client.sh -n ue1 -s 10.41.0.3 -t high_rate -b 3M -l 1280 -p tcp

while getopts n:s:t:b:l:p: flag
do
    case "${flag}" in
        n) NS=${OPTARG};;      # Namespace
        s) SERVER=${OPTARG};;  # Server IP
        t) NAME=${OPTARG};;    # Test Name (for Prometheus tag)
        b) BW=${OPTARG};;      # Bitrate (e.g. 64k, 3M)
        l) LEN=${OPTARG};;     # Packet Length
        p) PROTO=${OPTARG};;   # Protocol (tcp/udp)
    esac
done

# Defaults
PROM_DIR="/var/lib/node_exporter"
mkdir -p $PROM_DIR

# Construct iperf3 flags
IPERF_FLAGS="-c $SERVER -b $BW -l $LEN -t 10 --json"
[ "$PROTO" == "udp" ] && IPERF_FLAGS="$IPERF_FLAGS -u"

echo "Running Test [$NAME]: $BW over $PROTO in namespace $NS..."

# Run test
RESULT=$(ip netns exec "$NS" iperf3 $IPERF_FLAGS)

# Parse and Export
PROM_FILE="$PROM_DIR/ue_${NAME}.prom"

if [ "$PROTO" == "udp" ]; then
    JITTER=$(echo "$RESULT" | jq '.end.sum.jitter_ms' || echo 0)
    LOSS=$(echo "$RESULT" | jq '.end.sum.lost_percent' || echo 0)
    
    {
        echo "# HELP ue_voip_jitter_ms Jitter for $NAME"
        echo "ue_voip_jitter_ms{test=\"$NAME\",ns=\"$NS\"} $JITTER"
        echo "# HELP ue_voip_loss_percent Loss for $NAME"
        echo "ue_voip_loss_percent{test=\"$NAME\",ns=\"$NS\"} $LOSS"
    } > "${PROM_FILE}.tmp"
else
    THROUGHPUT=$(echo "$RESULT" | jq '.end.sum_sent.bits_per_second' || echo 0)
    {
        echo "# HELP ue_throughput_bps Throughput for $NAME"
        echo "ue_throughput_bps{test=\"$NAME\",ns=\"$NS\"} $THROUGHPUT"
    } > "${PROM_FILE}.tmp"
fi

mv "${PROM_FILE}.tmp" "$PROM_FILE"
echo "Metrics saved to $PROM_FILE"