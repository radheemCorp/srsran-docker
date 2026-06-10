#!/bin/bash
set -e

CONTAINER_NAME="open5gs_5gc"
DB_NAME="open5gs"

# Construct MongoDB update payload
# 1. network_access_mode = 0 (PACKET_AND_CIRCUIT_SWITCHED_ALLOWED)
# 2. ambr units optimized for stable data throughput bounds (Mbps range)
# 3. Unsets static 'ue.ipv4' to allow the SMF to handle dynamic IP allocation
MONGO_CMD="db.subscribers.updateMany({}, { 
  \$set: { 
    'network_access_mode': 0,
    'ambr.downlink.value': 3333,
    'ambr.downlink.unit': 1,
    'ambr.uplink.value': 2222,
    'ambr.uplink.unit': 4,
    'slice.0.session.0.ambr.downlink.value': 3333,
    'slice.0.session.0.ambr.downlink.unit': 1,
    'slice.0.session.0.ambr.uplink.value': 2222,
    'slice.0.session.0.ambr.uplink.unit': 4
  },
  \$unset: {
    'slice.0.session.0.ue': ''
  }
})"

echo "Applying core standard network parameters to all subscribers..."

if docker exec "$CONTAINER_NAME" which mongosh > /dev/null 2>&1; then
    docker exec -i "$CONTAINER_NAME" mongosh "$DB_NAME" --eval "$MONGO_CMD"
else
    docker exec -i "$CONTAINER_NAME" mongo "$DB_NAME" --eval "$MONGO_CMD"
fi

echo "Database fields corrected successfully."