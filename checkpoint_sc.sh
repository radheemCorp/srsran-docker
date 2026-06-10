#!/bin/bash
# Single-cell (2 UE) stability checkpoint: low-load bidirectional (UL+DL) stream
# on UE1+UE2 + ping mid-stream/idle + InfluxDB ue_traffic sample + RLC-wedge check.
# usage: checkpoint_sc.sh <label> <dur> <tail_sleep> <bitrate>
set -u
LABEL="${1:-cp}"; DUR="${2:-120}"; TAIL="${3:-165}"; BR="${4:-1M}"
UES="1 2"
cd /home/radr/pers/srsran-docker
ts() { date -u +%H:%M:%SZ; }
echo "############## CHECKPOINT $LABEL  (start $(ts) UTC) ##############"

# pre-run wedge-line counts (flag only NEW wedge spam this cycle)
declare -A PRE
for n in $UES; do
  PRE[$n]=$(docker exec multi_ue sh -c "grep -acE 'invalid length=-|Current SO larger' /tmp/ue$n.log 2>/dev/null" 2>/dev/null | head -1); PRE[$n]=${PRE[$n]:-0}
done

# 1) low-load bidirectional video stream on each UE
for n in $UES; do
  docker exec -d multi_ue /srsran/config/run_scenario.sh \
    --video-client --bidir --bitrate "$BR" --server-ip 10.45.0.1 --port $((5200+n)) --ue $n --duration "$DUR"
done
echo "[$(ts)] launched bidir UL+DL dur=${DUR}s bitrate=${BR}/dir on UE: $UES"

# 2) ping gateway WHILE the stream is active
sleep 70
echo "--- ping 10.45.0.1 (during active stream) ---"
for n in $UES; do
  r=$(docker exec multi_ue ip netns exec ue$n ping -c3 -W2 -I tun_srsue 10.45.0.1 2>&1 | grep -oE '[0-9]+% packet loss')
  echo "  UE$n: ${r:-NO REPLY}"
done

# 3) let the stream finish, sample metrics
sleep $((DUR-70+12))
echo "--- InfluxDB ue_traffic (count + max Mbps, last ~6 min; bidir => UL+DL rows) ---"
docker exec influxdb sh -c "curl -s -G 'http://localhost:8081/api/v3/query_sql' \
  --data-urlencode 'db=srsran' \
  --data-urlencode 'q=SELECT ue_id, count(*) AS n, round(max(throughput_mbps),3) AS max_mbps FROM ue_traffic WHERE time > now() - interval '\''6 minutes'\'' GROUP BY ue_id ORDER BY ue_id'" 2>&1 | head -c 500; echo
echo "--- InfluxDB ue_latency (avg RTT, last ~6 min) ---"
docker exec influxdb sh -c "curl -s -G 'http://localhost:8081/api/v3/query_sql' \
  --data-urlencode 'db=srsran' \
  --data-urlencode 'q=SELECT ue_id, round(avg(rtt_ms),1) AS avg_rtt_ms FROM ue_latency WHERE time > now() - interval '\''6 minutes'\'' GROUP BY ue_id ORDER BY ue_id'" 2>&1 | head -c 400; echo

# 4) RLC-wedge check (new wedge spam this cycle)
echo "--- RLC-wedge check ---"
for n in $UES; do
  post=$(docker exec multi_ue sh -c "grep -acE 'invalid length=-|Current SO larger' /tmp/ue$n.log 2>/dev/null" 2>/dev/null | head -1); post=${post:-0}
  d=$((post-${PRE[$n]}))
  [ "$d" -gt 0 ] && echo "  UE$n: WEDGE +$d lines" || echo "  UE$n: clean"
done

# 5) idle ping AFTER stream stops — real connectivity gate (mid-stream loss = bufferbloat)
sleep 12
echo "--- ping 10.45.0.1 (idle, ~12s after stream stopped) ---"
for n in $UES; do
  r=$(docker exec multi_ue ip netns exec ue$n ping -c3 -W3 -I tun_srsue 10.45.0.1 2>&1 | grep -oE '[0-9]+% packet loss')
  echo "  UE$n: ${r:-NO REPLY}"
done
echo "[$(ts)] checkpoint $LABEL done; spacing sleep $((TAIL-12))s"
sleep "$((TAIL-12))"
echo "############## CHECKPOINT $LABEL complete (end $(ts) UTC) ##############"
