# Conan Exiles Enhanced Server - Based on docker-steamcmd-server
# The shared base owns SteamCMD, architecture adaptation, process supervision,
# and lifecycle hooks. This image supplies Conan's native Linux contract.

ARG BASE_IMAGE=ghcr.io/teriyakidactyl/docker-steamcmd-server
ARG BASE_TAG=trixie
FROM ${BASE_IMAGE}:${BASE_TAG}

ARG BASE_IMAGE
ARG BASE_TAG
ARG SOURCE_COMMIT
ARG BUILD_DATE
ARG BRANCH_NAME

LABEL org.opencontainers.image.title="Conan Exiles Enhanced Server" \
      org.opencontainers.image.description="Native Linux Conan Exiles Enhanced dedicated server" \
      org.opencontainers.image.vendor="TeriyakiDactyl" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.base.name="${BASE_IMAGE}:${BASE_TAG}" \
      com.example.git.branch="${BRANCH_NAME}"

ENV APP_NAME="conan" \
    APP_EXE="ConanSandbox/Binaries/Linux/ConanSandboxServer-Linux-Shipping" \
    APP_PROCESS_NAME="ConanSandboxServer-Linux-Shipping" \
    APP_LOG_NAME="conan-server" \
    APP_ARGS_FILE="/usr/local/bin/container/conan.args" \
    APP_STOP_SIGNAL="INT" \
    SHUTDOWN_TIMEOUT="120" \
    STEAM_SERVER_APPID="443030" \
    STEAM_CLIENT_APPID="440900" \
    STEAM_PLATFORM_TYPE="linux" \
    STEAM_ID_ALLOW_LIST_PATH="$WORLD_FILES/Saved/whitelist.txt" \
    SERVER_PLAYER_PASS="MySecretPassword" \
    SERVER_ADMIN_PASS="MySecretPasswordAdmin" \
    SERVER_NAME="Teriyakolypse" \
    SERVER_NUDITY_POLICY="0" \
    SERVER_REGION_ID="1" \
    SERVER_PORT="7777" \
    SERVER_QUERY_PORT="27015" \
    SERVER_MAX_PLAYERS="40" \
    SERVER_MOD_IDS="" \
    SERVER_ALLOW_LIST="" \
    LOG_FILTER_SKIP=""

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libatomic1 \
        libgcc-s1 \
        libicu-dev \
        libpulse0 \
        libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

COPY scripts ${SCRIPTS}

RUN chown root:root \
        "$SCRIPTS/container/conan.args" \
        "${HOOK_DIRECTORIES}/pre-startup/30_conan_functions.sh" \
    && chmod 0644 "$SCRIPTS/container/conan.args" \
    && chmod 0755 "${HOOK_DIRECTORIES}/pre-startup/30_conan_functions.sh"

USER ${CONTAINER_USER}

# The native launcher changes to the server root before invoking the shipping
# binary. Match that contract while allowing the shared base to prepend Box64
# on arm64 to the actual x86_64 game executable.
WORKDIR /app

EXPOSE 7777/udp 7778/udp 27015/udp 7777/tcp 25575/tcp
