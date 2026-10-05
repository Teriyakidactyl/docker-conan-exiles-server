#!/bin/bash

set -Eeuo pipefail

CONTAINER_NAME="conan-server"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/teriyakidactyl/docker-conan-exiles-server:trixie_dev}"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

docker run --rm -it \
    --name "$CONTAINER_NAME" \
    --entrypoint /bin/bash \
    "$IMAGE_NAME"
