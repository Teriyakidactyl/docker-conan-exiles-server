# Set ARG for building
ARG BASE_TAG=trixie-20250407-slim_wine-staging-10.5

# Use the base SteamCMD server image
FROM ghcr.io/teriyakidactyl/docker-steamcmd-server:${BASE_TAG}

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
      com.example.git.branch="${BRANCH_NAME}"

# Set game-specific environment variables
ENV \
    # Primary Variables
    APP_NAME="conan" \
    APP_EXE="xvfb-run" \
    APP_EXE_2="ConanSandboxServer.exe" \
    STEAM_SERVER_APPID="443030" \
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
        # 0 - Europe
        # 1 - North America
        # 2 - Asia
        # 3 - Australia
        # 4 - South America
        # 5 - Japan
    \
    # Log settings
    LOG_FILTER_SKIP=""

# Create additional directories and links specific to Conan Exiles
RUN mkdir -p $WORLD_FILES/Saved/Logs \
             $WORLD_FILES/Config \
             $WORLD_FILES/Mods \
             $WORLD_FILES/Engine/Config \
             $APP_FILES/Engine \
             $APP_FILES/ConanSandbox && \
    ln -sf "$WORLD_FILES/Engine/Config" "$APP_FILES/Engine" && \
    ln -sf "$WORLD_FILES/Saved" "$APP_FILES/ConanSandbox" && \
    ln -sf "$WORLD_FILES/Config" "$APP_FILES/ConanSandbox" && \
    ln -sf "$WORLD_FILES/Mods" "$APP_FILES/ConanSandbox" && \
    # FIXME APP_LOGS don't exist yet
    # touch "$APP_LOGS/ConanSandbox.log" && \
    # ln -sf "$APP_LOGS/ConanSandbox.log" "$WORLD_FILES/Saved/Logs/ConanSandbox.log" && \
    chown -R $APP_USER:$APP_USER $WORLD_FILES $APP_FILES $APP_LOGS

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
