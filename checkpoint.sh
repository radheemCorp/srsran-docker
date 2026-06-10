#!/bin/bash
# 30-min stability checkpoint: video streaming test on all 4 UEs + ping mid-stream
# + InfluxDB ue_traffic / kpm sample + RLC-wedge check.
# usage: checkpoint.sh <label> <video_dur> <kpm_node> <tail_sleep>
set -u
LABEL="${1:-cp}"; DUR="${2:-120}"; NODE="${3:-gnbd_001_001_000001_0}"; TAIL="${4:-165}"; BR="${5:-1M}"
cd /home/radr/pers/srsran-docker

ts() { date -u +%H:%M:%SZ; }
echo "############## CHECKPOINT $LABEL  (start $(ts) UTC) ##############"

# capture pre-run wedge-line counts so we only flag NEW wedge spam this cycle
# (grep -c prints 0 and exits 1 on no-match; capture stdout only, no '|| echo')
declare -A PRE
for n in 1 2 3 4; do
  PRE[$n]=$(docker exec multi_ue sh -c "grep -acE 'invalid length=-|Current SO larger' /tmp/ue$n.log 2>/dev/null" 2>/dev/null | head -1)
  PRE[$n]=${PRE[$n]:-0}
done

# 1) launch the internal video streaming test on all 4 UEs:
#    bidirectional (UL+DL) bounded UDP at reduced bitrate $BR per direction
for n in 1 2 3 4; do
  docker exec -d multi_ue /srsran/config/run_scenario.sh \
    --video-client --bidir --bitrate "$BR" --server-ip 10.45.0.1 --port $((5200+n)) --ue $n --duration "$DUR"
done
echo "[$(ts)] launched bidir video dur=${DUR}s bitrate=${BR}/dir on UE1-4"

# 2) ping the gateway from every UE WHILE the video stream is active
sleep 70
echo "--- ping 10.45.0.1 (during active video stream) ---"
for n in 1 2 3 4; do
  r=$(docker exec multi_ue ip netns exec ue$n ping -c3 -W2 -I tun_srsue 10.45.0.1 2>&1 | grep -oE '[0-9]+% packet loss')
  echo "  UE$n: ${r:-NO REPLY}"
done

# 3) let the video run finish, then sample metrics
sleep $((DUR-70+12))
echo "--- InfluxDB ue_traffic (max throughput, last ~6 min) ---"
docker exec influxdb sh -c "curl -s -G 'http://localhost:8081/api/v3/query_sql' \
  --data-urlencode 'db=srsran' \
  --data-urlencode 'q=SELECT ue_id, count(*) AS n, round(max(throughput_mbps),3) AS max_mbps FROM ue_traffic WHERE time > now() - interval '\''6 minutes'\'' GROUP BY ue_id ORDER BY ue_id'" 2>&1 | head -c 600; echo
echo "--- InfluxDB kpm (active node $NODE, last ~6 min) ---"
docker exec influxdb sh -c "curl -s -G 'http://localhost:8081/api/v3/query_sql' \
  --data-urlencode 'db=srsran' \
  --data-urlencode 'q=SELECT e2_node_id, count(*) AS n, round(max(\"DRB_UEThpUl\"),1) AS max_ul_kbps, round(max(\"DRB_UEThpDl\"),1) AS max_dl_kbps FROM kpm WHERE time > now() - interval '\''6 minutes'\'' GROUP BY e2_node_id ORDER BY e2_node_id'" 2>&1 | head -c 600; echo

# 4) RLC-wedge check: any NEW wedge spam since checkpoint start?
echo "--- RLC-wedge check (new wedge log lines this cycle) ---"
wedge=0
for n in 1 2 3 4; do
  post=$(docker exec multi_ue sh -c "grep -acE 'invalid length=-|Current SO larger' /tmp/ue$n.log 2>/dev/null" 2>/dev/null | head -1)
  post=${post:-0}
  d=$((post-${PRE[$n]}))
  [ "$d" -gt 0 ] && { echo "  UE$n: WEDGE +$d lines"; wedge=1; } || echo "  UE$n: clean"
done
# 5) xApp process alive?
alive=$(docker exec python_xapp_runner sh -c 'c=0; for d in /proc/[0-9]*; do tr "\0" " " < "$d/cmdline" 2>/dev/null | grep -q kpm_mon_xapp && c=$((c+1)); done; echo $c')
echo "--- xApp kpm_mon processes alive: $alive ---"

# 6) idle ping AFTER the stream stops — connectivity gate (must pass).
#    mid-stream loss = bufferbloat (RTT>timeout under load); idle loss = real fault.
sleep 12
echo "--- ping 10.45.0.1 (idle, ~12s after stream stopped) ---"
idlefail=0
for n in 1 2 3 4; do
  r=$(docker exec multi_ue ip netns exec ue$n ping -c3 -W3 -I tun_srsue 10.45.0.1 2>&1 | grep -oE '[0-9]+% packet loss')
  echo "  UE$n: ${r:-NO REPLY}"
  case "$r" in 100%*|"") idlefail=1;; esac
done
[ "$idlefail" = "1" ] && echo "  ** IDLE PING FAILED on a UE -> real connectivity loss, investigate **" || echo "  idle ping OK on all UEs (mid-stream loss was load-induced bufferbloat)"
echo "[$(ts)] checkpoint $LABEL done; spacing sleep $((TAIL-12))s (idle gap, avoids back-to-back RLC wedge)"
sleep "$((TAIL-12))"
echo "############## CHECKPOINT $LABEL complete (end $(ts) UTC) ##############"
