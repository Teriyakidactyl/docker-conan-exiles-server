# Stage 1: SteamCMD Install
FROM --platform=linux/amd64 debian:trixie-slim AS opt

ARG DEBIAN_FRONTEND=noninteractive

ENV STEAMCMD_PATH="/opt/steamcmd"

# Manual amd64 wine for Box64, https://dl.winehq.org/wine-builds > https://dl.winehq.org/wine-builds/debian/dists/trixie/main/binary-amd64/
## WINE_PATH from winehq debs
ENV WINE_BRANCH="staging" \
    WINE_PATH="/opt/wine-staging/bin" \
    WINE_VERSION="9.13" \
    WINE_ID="debian" \
    WINE_DIST="trixie" \
    WINE_TAG="-1" 

# Set Wine download links for amd64
ENV WINEHQ_LINK_AMD64="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-amd64/" \
    WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb" \
    # (required for wine64 / can work alongside wine_i386 main bin) 
    WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb" \
    WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/" \
    WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb" \
    # wine_i386 support files (required for wine_i386 if no wine64 / CONFLICTS WITH wine64 support files) 
    WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"    

RUN apt-get update; \
    apt-get install -y curl lib32gcc-s1; \
    mkdir -p $STEAMCMD_PATH; \
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C $STEAMCMD_PATH; \
    $STEAMCMD_PATH/steamcmd.sh +login anonymous +quit; \
    \
    # Wine, Windows Emulator, https://packages.debian.org/bookworm/wine, https://wiki.winehq.org/Debian , https://www.winehq.org/news/
    # Install wine amd64 in arm64 manually, needed for box64, https://github.com/ptitSeb/box64/blob/main/docs/X64WINE.md
    ## Wine only translates windows apps, but not arch. Windows apps are almost all x86, so wine:arm doesn't really help.
    TEMP_DIR="/tmp/wine_debs"; \
    mkdir -p "$TEMP_DIR"; \
    curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_64_MAIN_BIN}"; \
    curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}"; \
    # NOTE Skipping wine32 i386 
    #curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}"; \
    #curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}"; \
    dpkg-deb -x "${TEMP_DIR}/${WINE_64_MAIN_BIN}" /; \
    dpkg-deb -x "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" /; \
    #dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" /; \
    #dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" /; \
    chmod +x $WINE_PATH/wine64 $WINE_PATH/wineboot $WINE_PATH/winecfg $WINE_PATH/wineserver;
    ## $WINE_PATH/wine

# Stage 2: Final
# Refference: https://conanexiles.fandom.com/wiki/Dedicated_Server_Setup:_Linux_and_Wine
FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive \
    TARGETARCH \
    PACKAGES_AMD64_ONLY=" \
        # required for steamcmd, https://packages.debian.org/bookworm/lib32gcc-s1
        lib32gcc-s1" \ 
         \
    PACKAGES_ARM_ONLY=" \
        # required for Box86 > steamcmd, https://packages.debian.org/bookworm/libc6
        libc6:armhf" \
        \
    PACKAGES_ARM_BUILD=" \
        # repo keyring add, https://packages.debian.org/bookworm/gnupg
        gnupg" \
        \
    PACKAGES_BASE_BUILD=" \
        curl" \
        \
    PACKAGES_BASE=" \
        # Fake X-Server desktop for Wine https://packages.debian.org/bookworm/xvfb
        ## xauth needed with --no-install-recommends with wine
        xvfb \
        xauth \
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
    # Primary Variables
    APP_NAME="conan" \
    APP_FILES="/app" \
    APP_EXE="ConanSandboxServer.exe" \
    WORLD_FILES="/world" \
    STEAMCMD_PATH="/opt/steamcmd" \
    WINE_PATH="/opt/wine-staging/bin" \
    SCRIPTS="/usr/local/bin" \
    LOGS="/var/log" \
    TERM="xterm-256color" \
    DISPLAY=":0" \
    PUID="1000" \
    \
    # App Variables
    SERVER_PLAYER_PASS="MySecretPassword" \
    SERVER_ADMIN_PASS="MySecretPasswordAdmin" \
    SERVER_NAME="Teriyakolypse" \
    SERVER_REGION_ID="1" \
        # Explanation of numeric regions:
        # 0 - Europe
        # 1 - North America
        # 2 - Asia
        # 3 - Australia
        # 4 - South America
        # 5 - Japan
    \
    # Log settings
    # TODO move to file, get more comprehensive.  
    LOG_FILTER_SKIP=""

ENV \
    # Derivative Variables
    \
    # Steamcmd
    STEAMCMD_PROFILE="/home/$APP_NAME/Steam" \
    STEAM_LIBRARY="$APP_FILES/Steam" \
    \
    APP_LOGS="$LOGS/$APP_NAME" \
    WINEPREFIX="/app/Wine" \
    \
    # Volume Prep Directories
    WORLD_DIRECTORIES="\
    $WORLD_FILES/Saved/Logs \
    $WORLD_FILES/Config \
    $WORLD_FILES/Mods \
    $WORLD_FILES/Engine/Config \
    $APP_FILES/Engine \
    $APP_FILES/ConanSandbox"
    	
ENV \   
    STEAMCMD_LOGS="$STEAMCMD_PROFILE/logs" \ 
    DIRECTORIES="\
    $WINE_PATH \
    $WORLD_FILES \
    $WORLD_DIRECTORIES \
    $APP_FILES \
    $APP_LOGS \
    $LOGS \
    $STEAM_LIBRARY \
    $STEAMCMD_PATH \
    $STEAMCMD_LOGS \
    $SCRIPTS"

# Copy steamcmd and wine
COPY --from=opt /opt /opt

# Update package lists and install required packages
RUN set -eux; \
    \
    # Update and install common BASE_DEPENDENCIES
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PACKAGES_BASE $PACKAGES_BASE_BUILD $PACKAGES_DEV; \
    \
    # Create and set up $DIRECTORIES permissions
    # links to seperate save game files 'stateful' data from application.
    useradd -m -u $PUID -d "/home/$APP_NAME" -s /bin/bash $APP_NAME; \
    mkdir -p $DIRECTORIES; \
    ln -s "/home/$APP_NAME/Steam/logs" "$LOGS/steamcmd"; \
    ln -sf "$WORLD_FILES/Engine/Config" "$APP_FILES/Engine"; \
    ln -sf "$WORLD_FILES/Saved" "$APP_FILES/ConanSandbox"; \
    ln -sf "$WORLD_FILES/Config" "$APP_FILES/ConanSandbox"; \
    ln -sf "$WORLD_FILES/Mods" "$APP_FILES/ConanSandbox"; \
    touch "$APP_LOGS/ConanSandbox.log"; \
    ln -sf "$APP_LOGS/ConanSandbox.log" "$WORLD_FILES/Saved/Logs/ConanSandbox.log"; \
    \
    # Create symlinks for wine
    # NOTE Skipping wine32 i386
    # ln -sf "$WINE_PATH/wine" /usr/local/bin/wine; \
    ln -sf "$WINE_PATH/wine64" /usr/local/bin/wine64; \
    ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot; \
    ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg; \
    ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver; \    
    \
    chown -R $APP_NAME:$APP_NAME $DIRECTORIES; \    
    chmod 755 $DIRECTORIES; \  
    \
    # Architecture-specific setup for ARM
    if echo "$TARGETARCH" | grep -q "arm"; then \
        # Add ARM architecture and update
        dpkg --add-architecture armhf; \
        apt-get update; \
        \
        # Install ARM-specific packages
        apt-get install -y --no-install-recommends \
            $PACKAGES_ARM_ONLY $PACKAGES_ARM_BUILD; \
        \
        # Add and configure Box86: https://box86.debian.ryanfortner.dev/
        curl -fsSL https://itai-nelken.github.io/weekly-box86-debs/debian/box86.list -o /etc/apt/sources.list.d/box86.list; \
        curl -fsSL https://itai-nelken.github.io/weekly-box86-debs/debian/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box86-debs-archive-keyring.gpg; \
        \
        # Add and configure Box64: https://box64.debian.ryanfortner.dev/
        curl -fsSL https://ryanfortner.github.io/box64-debs/box64.list -o /etc/apt/sources.list.d/box64.list; \
        curl -fsSL https://ryanfortner.github.io/box64-debs/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box64-debs-archive-keyring.gpg; \
        \
        # Update and install Box86/Box64
        apt-get update; \
        apt-get install -y --no-install-recommends \
            box64 box86; \ 
        \
        # Clean up
        apt-get autoremove --purge -y $PACKAGES_ARM_BUILD; \
    else \ 
        # AMD64 specific packages
        apt-get install -y --no-install-recommends \
            $PACKAGES_AMD64_ONLY; \
    fi; \
    # Final cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get autoremove --purge -y $PACKAGES_BASE_BUILD

# Change to non-root APP_NAME
USER $APP_NAME

# Copy scripts after changing to APP_NAME(user)
COPY --chown=$APP_NAME:$APP_NAME scripts $SCRIPTS

# Copy steamcmd user profile (8mb)
COPY --from=opt --chown=$APP_NAME:$APP_NAME /root/Steam $STEAMCMD_PROFILE 

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
