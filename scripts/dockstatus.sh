#!/bin/bash

if ! command -v docker >/dev/null 2>&1; then
  echo "docker: command not found" >&2
  return 1
fi

# Header
printf "%-30s %-30s %-40s\n" "NETWORK" "IPv4 SUBNETS" "IPv6 SUBNETS"
printf "%-30s %-30s %-40s\n" "-------" "------------" "------------"

# Iterate networks
docker network ls --format '{{.Name}}' | while IFS= read -r name; do
  # Get all Subnet entries joined by '|' (empty if none)
  subnets=$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}|{{end}}' "$name" 2>/dev/null || echo "")
  # Split into array on '|'
  IFS='|' read -r -a parts <<< "$subnets"

  ipv4=""
  ipv6=""
  for p in "${parts[@]}"; do
    [ -z "$p" ] && continue
    if [[ "$p" == *:* ]]; then
      ipv6+="$p "
    else
      ipv4+="$p "
    fi
  done

  # Show '-' when empty
  [ -z "$ipv4" ] && ipv4="-"
  [ -z "$ipv6" ] && ipv6="-"

  printf "%-30s %-30s %-40s\n" "$name" "$ipv4" "$ipv6"
done
