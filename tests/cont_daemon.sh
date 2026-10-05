#!/bin/bash

set -Eeuo pipefail

CONTAINER_NAME="conan-server"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/teriyakidactyl/docker-conan-exiles-server:trixie_dev}"
DATA_ROOT="${DATA_ROOT:-$PWD/.conan-test-data}"

mkdir -p "$DATA_ROOT/app" "$DATA_ROOT/world"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

docker run -d \
    --name "$CONTAINER_NAME" \
    --stop-timeout 135 \
    -p 7777:7777/udp \
    -p 7778:7778/udp \
    -p 27015:27015/udp \
    -p 7777:7777/tcp \
    -p 25575:25575/tcp \
    -e SERVER_NAME="TestServer" \
    -e SERVER_PLAYER_PASS="testpassword" \
    -e SERVER_ADMIN_PASS="testadminpassword" \
    -v "$DATA_ROOT/world:/world" \
    -v "$DATA_ROOT/app:/app" \
    "$IMAGE_NAME"
