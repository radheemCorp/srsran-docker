#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker-compose.yml"

echo "Parsing images from compose file $COMPOSE_FILE..."

mapfile -t svc_images < <(docker compose -f "$COMPOSE_FILE" config | awk 'BEGIN{svc=""} /^[[:space:]]{2}[a-zA-Z0-9_-]+:/{svc=$1; sub(":","",svc);} /^[[:space:]]+image:/ {print svc " " $2}')

if [ ${#svc_images[@]} -eq 0 ]; then
  echo "No services found in compose or parsing failed." >&2
  exit 1
fi

for entry in "${svc_images[@]}"; do
  svc=${entry%% *}
  image=${entry#* }
  echo "\nService: $svc -> image: $image"

  if docker image inspect "$image" > /dev/null 2>&1; then
    echo "Image $image found locally."
    continue
  fi

  echo "Image $image not found locally; attempting to pull..."
  if docker pull "$image"; then
    echo "Pulled $image"
    continue
  fi

  echo "Pull failed for $image; building service $svc locally..."
  docker compose -f "$COMPOSE_FILE" build --no-cache "$svc"
done

echo "Bringing up the stack..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Done. Use 'docker compose logs -f <service>' to follow logs." 
