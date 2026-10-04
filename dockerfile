# Follow a supported shared-base alias instead of pinning a Wine version in the
# derivative. docker-steamcmd-server owns Wine/Box compatibility policy.
ARG BASE_IMAGE=ghcr.io/teriyakidactyl/docker-steamcmd-server
ARG BASE_TAG=trixie_wine-staging

FROM ${BASE_IMAGE}:${BASE_TAG}

ARG BASE_IMAGE
ARG BASE_TAG

# Build ARGs for metadata
ARG SOURCE_COMMIT
ARG BUILD_DATE
ARG BRANCH_NAME

# Labels
LABEL org.opencontainers.image.title="Conan Exiles Server" \
      org.opencontainers.image.description="Docker image for Conan Exiles dedicated server" \
      org.opencontainers.image.vendor="TeriyakiDactyl" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.base.name="${BASE_IMAGE}:${BASE_TAG}" \
      com.example.git.branch="${BRANCH_NAME}"

# Set game-specific environment variables
ENV \
    # Primary Variables
    # Conan CLI ARGS:    
    ## https://forums.funcom.com/t/conan-exiles-dedicated-server-launcher-official-version-1-7-8-beta-1-7-9/21699
    ## https://steamcommunity.com/sharedfiles/filedetails/?id=853969975
    APP_NAME="conan" \
    APP_EXE="ConanSandboxServer.exe" \
    APP_ARGS='\
    -nosteamclient \
    -game \
    -server \
    -log' \
    \
    # SteamCMD
    STEAM_SERVER_APPID="443030" \
    STEAM_CLIENT_APPID="440900" \
    STEAM_PLATFORM_TYPE="windows" \
    STEAM_ID_ALLOW_LIST_PATH="$WORLD_FILES/Saved/whitelist.txt" \
    \
    # App Variables
    SERVER_PLAYER_PASS="MySecretPassword" \
    SERVER_ADMIN_PASS="MySecretPasswordAdmin" \
    SERVER_NAME="Teriyakolypse" \
    SERVER_NUDITY_POLICY="0" \
        # 0: No nudity (characters are fully clothed).
        # 1: Partial nudity (minimal clothing or loincloths).
        # 2: Full nudity (characters are fully nude).
    SERVER_REGION_ID="1" \
    SERVER_MOD_IDS="" \
    SERVER_ALLOW_LIST="" \
        # 0 - Europe
        # 1 - North America
        # 2 - Asia
        # 3 - Australia
        # 4 - South America
        # 5 - Japan
    \
    # Log settings
    LOG_FILTER_SKIP=""

# Persistence links are created by the pre-start hook after SteamCMD updates.
# /app and /world are runtime mount points; baking links beneath them into the
# image makes those links disappear when a real volume or bind mount is used.
COPY --chown=${CONTAINER_USER}:${CONTAINER_USER} scripts ${SCRIPTS}

# Expose necessary ports
EXPOSE \
    # Game port (UDP): Default 7777, configurable in Engine.ini or via command line
    7777/udp \
    # Pinger port (UDP): Always game port + 1 (7778), not configurable
    7778/udp \
    # Server query port (UDP): Default 27015, configurable in Engine.ini or via command line
    27015/udp \
    # Mod download port (TCP): Default game port + offset (7777), configurable in Engine.ini
    7777/tcp \
    # RCON port (TCP): Default 25575, configurable in Game.ini or via command line
    25575/tcp
