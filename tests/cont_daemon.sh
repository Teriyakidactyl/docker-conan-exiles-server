#!/bin/bash

# Container name
CONTAINER_NAME="conan-server"

# Image name
IMAGE_NAME="ghcr.io/teriyakidactyl/docker-conan-exiles-server:bookworm-20250407-slim_wine-stable-10.0.0.0_dev"

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Container ${CONTAINER_NAME} already exists, stopping and removing it..."
  docker stop ${CONTAINER_NAME} >/dev/null 2>&1
  docker rm ${CONTAINER_NAME} >/dev/null 2>&1
fi

# Run the container detached
echo "Starting Conan Exiles server container in detached mode..."
docker run -d \
  --name ${CONTAINER_NAME} \
  -p 7777:7777/udp \
  -p 7778:7778/udp \
  -p 27015:27015/udp \
  -p 7777:7777/tcp \
  -p 25575:25575/tcp \
  -e SERVER_NAME="Teriyakolypse" \
  -e SERVER_PLAYER_PASS="MySecretPassword" \
  -e SERVER_ADMIN_PASS="MySecretPasswordAdmin" \
  -e SERVER_NUDITY_POLICY="0" \
  -e SERVER_REGION_ID="1" \
  ${IMAGE_NAME}