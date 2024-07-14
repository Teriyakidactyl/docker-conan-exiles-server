# Stage 1: SteamCMD Install
FROM --platform=linux/amd64 debian:trixie-slim AS steamcmd

ARG DEBIAN_FRONTEND=noninteractive

ENV STEAMCMD_PATH="/usr/lib/games/steam/steamcmd"

RUN apt-get update \
    && apt-get install -y curl lib32gcc-s1 \
    && mkdir -p $STEAMCMD_PATH \
    && curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C $STEAMCMD_PATH \
    && $STEAMCMD_PATH/steamcmd.sh +login anonymous +quit

# Stage 2: Final
FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive \
    TARGETARCH \
    PACKAGES_WINE=" \
        # Fake X-Server desktop for Wine https://packages.debian.org/bookworm/xvfb
        xvfb \
        # Wine, Windows Emulator, https://packages.debian.org/bookworm/wine, https://wiki.winehq.org/Debian , https://www.winehq.org/news/
        # NOTE: WineHQ repository only offers packages for AMD64 and i386. If you need the ARM version, you can use the Debian packages. 
        wine \
        wine32 \
        ## Fix for 'ntlm_auth was not found'
        winbind" \
        \
    PACKAGES_BASE_BUILD=" \
        curl" \
        \
    PACKAGES_BASE=" \
        # curl, steamcmd, https://packages.debian.org/bookworm/ca-certificates
        ca-certificates \
        # timezones, https://packages.debian.org/bookworm/tzdata
        tzdata" \
        \
    PACKAGES_DEV=" \
        # disk space analyzer: https://packages.debian.org/trixie/ncdu
        ncdu \
        # top replacement: https://packages.debian.org/trixie/btop
        btop"
    
ENV \
    # Container Varaibles
    APP_NAME="conan" \
    APP_FILES="/app" \
    APP_EXE="ConanSandboxServer.exe" \
    WORLD_FILES="/world" \
    STEAMCMD_PATH="/usr/lib/games/steam/steamcmd" \
    SCRIPTS="/usr/local/bin" \
    LOGS="/var/log" \
    TERM=xterm-256color \
    \
    # App Variables
    SERVER_PLAYER_PASS="MySecretPassword" \
    SERVER_ADMIN_PASS="" \
    SERVER_NAME="Teriyakolypse" \
    SERVER_REGION_ID="1" \
    \
    # Log settings 
    # TODO move to file, get more comprehensive.   
    LOG_FILTER_SKIP=""     

# Update package lists and install required packages
RUN set -eux; \
    \
    # Update and install common BASE_DEPENDENCIES
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PACKAGES_BASE $PACKAGES_BASE_BUILD $PACKAGES_DEV; \
    apt-get install -y \
        $PACKAGES_WINE; \
    \
    # Set local build variables
    STEAMCMD_PROFILE="/home/$APP_NAME/Steam" ;\
    STEAMCMD_LOGS="$STEAMCMD_PROFILE/logs" ;\
    APP_LOGS="$LOGS/$APP_NAME" ;\
    PUID=1000 \
    \
    WORLD_DIRECTORIES=" \
        $WORLD_FILES/Saved/Logs \
        $WORLD_FILES/Config \
        $WORLD_FILES/Mods \
        $WORLD_FILES/Engine/Config \
        $APP_FILES/Engine \
        $APP_FILES/ConanSandbox" ;\
    \
    DIRECTORIES=" \
        $WORLD_FILES \
        $WORLD_DIRECTORIES \
        $APP_FILES \
        $LOGS \
        $STEAMCMD_PATH \
        $STEAMCMD_LOGS \
        $APP_LOGS \
        $SCRIPTS" ;\
    \
    # Create and set up $DIRECTORIES permissions
    # links to seperate save game files 'stateful' data from application.
    useradd -m -u $PUID -d /home/$APP_NAME -s /bin/bash $APP_NAME; \
    mkdir -p $DIRECTORIES; \
    ln -s /home/$APP_NAME/Steam/logs $LOGS/steamcmd; \
    ln -sf "$WORLD_FILES/Engine/Config" "$APP_FILES/Engine" ;\
    ln -sf "$WORLD_FILES/Saved" "$APP_FILES/ConanSandbox" ;\
    ln -sf "$WORLD_FILES/Config" "$APP_FILES/ConanSandbox" ;\
    ln -sf "$WORLD_FILES/Mods" "$APP_FILES/ConanSandbox";\
    touch "$APP_LOGS/ConanSandbox.log" ;\
    ln -sf "$APP_LOGS/ConanSandbox.log" "$WORLD_FILES/Saved/Logs/ConanSandbox.log";\
    \
    chown -R $APP_NAME:$APP_NAME $DIRECTORIES; \    
    chmod 755 $DIRECTORIES; \  
    \
    # Final cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get autoremove --purge -y $PACKAGES_BASE_BUILD

# Change to non-root APP_NAME
USER $APP_NAME

# Copy scripts after changing to APP_NAME(user)
COPY --chown=$APP_NAME:$APP_NAME scripts $SCRIPTS
COPY --from=steamcmd \
    --chown=$APP_NAME:$APP_NAME \
    # Copy user profile (8mb)
    /root/Steam $STEAMCMD_PROFILE \
    # Copy executables (714mb)
    $STEAMCMD_PATH $STEAMCMD_PATH 

# https://docs.docker.com/reference/dockerfile/#volume
VOLUME ["$APP_FILES"]
VOLUME ["$WORLD_FILES"]

# Expose necessary ports: (https://www.conanexiles.com/dedicated-servers/)
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


# TODO Find PID
#HEALTHCHECK --interval=1m --timeout=3s CMD pidof $APP_EXE || exit 1

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["conan_up.sh"]
