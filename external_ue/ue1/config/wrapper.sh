mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

while true; do sleep 30; done;
