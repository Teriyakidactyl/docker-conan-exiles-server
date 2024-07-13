# Stage 1: SteamCMD Install
FROM --platform=linux/amd64 debian:bookworm-slim AS steamcmd

ARG DEBIAN_FRONTEND=noninteractive

ENV STEAMCMD_PATH="/usr/lib/games/steam/steamcmd"

RUN apt-get update \
    && apt-get install -y curl lib32gcc-s1 \
    && mkdir -p $STEAMCMD_PATH \
    && curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C $STEAMCMD_PATH \
    && $STEAMCMD_PATH/steamcmd.sh +login anonymous +quit

# Stage 2: Final
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive \
    TARGETARCH \
    PACKAGES_ARM_STEAMCMD=" \
        # required for Box86 > steamcmd, https://packages.debian.org/bookworm/libc6
        libc6:armhf" \
        \
    PACKAGES_AMD64_STEAMCMD=" \
        # required for steamcmd, https://packages.debian.org/bookworm/lib32gcc-s1-amd64-cross
        lib32gcc-s1" \
        \
    PACKAGES_CONAN=" \
        xvfb \
        wine \
        gnutls-bin" \
        \
    PACKAGES_ARM_BUILD=" \
        # repo keyring add, https://packages.debian.org/bookworm/gnupg
        gnupg" \
        \
    PACKAGES_BASE_BUILD=" \
        curl" \
        \
    PACKAGES_BASE=" \
        # curl, steamcmd, https://packages.debian.org/bookworm/ca-certificates
        ca-certificates \
        # timezones, https://packages.debian.org/bookworm/tzdata
        tzdata"
    
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
    SERVER_PUBLIC="0" \
    SERVER_PLAYER_PASS="MySecretPassword" \
    SERVER_NAME="MyValheimServer" \
    WORLD_NAME="Teriyakolypse" \
    \
    # Log settings 
    # TODO move to file, get more comprehensive.   
    LOG_FILTER_SKIP=""     

# Update package lists and install required packages
RUN set -eux; \
    \
    # Update and install common BASE_DEPENDENCIES
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PACKAGES_BASE $PACKAGES_BASE_BUILD $PACKAGES_CONAN; \
    \
    # Set local build variables
    STEAMCMD_PROFILE="/home/$APP_NAME/Steam" ;\
    STEAMCMD_LOGS="$STEAMCMD_PROFILE/logs" ;\
    APP_LOGS="$LOGS/$APP_NAME" ;\
    PUID=1000 \
    GUID=1000 \
    WORLD_DIRECTORIES="$STEAM_PATH $WORLD_FILES/$SERVER_NAME/Saved $WORLD_FILES/$SERVER_NAME/Config $WORLD_FILES/$SERVER_NAME/Mods $WORLD_FILES/$SERVER_NAME/Engine/Config $APP_FILES/Engine $APP_FILES/ConanSandbox" ;\
    DIRECTORIES="$WORLD_FILES $APP_FILES $LOGS $STEAMCMD_PATH $STEAMCMD_LOGS $APP_LOGS $SCRIPTS $WORLD_DIRECTORIES" ;\
    \
    # Create and set up $DIRECTORIES permissions
    useradd -m -u $PUID -d /home/$APP_NAME -s /bin/bash $APP_NAME; \
    mkdir -p $DIRECTORIES; \
    ln -s /home/$APP_NAME/Steam/logs $LOGS/steamcmd; \
    # Link Library for Wine
    ln -s /usr/lib/x86_64-linux-gnu/libgcc_s.so.1 /usr/lib/wine/libgcc_s.so.1 \
    # Create symbolic links based on the SERVER_NAME environment variable
    ln -sf "$WORLD_FILES/$SERVER_NAME/Engine/Config" $APP_FILES/Engine ;\
    ln -sf "$WORLD_FILES/$SERVER_NAME/Saved" $APP_FILES/ConanSandbox ;\
    ln -sf "$WORLD_FILES/$SERVER_NAME/Config" $APP_FILES/ConanSandbox ;\
    ln -sf "$WORLD_FILES/$SERVER_NAME/Mods" $APP_FILES/ConanSandbox ;\
    chown -R $APP_NAME:$APP_NAME $DIRECTORIES; \    
    chmod 755 $DIRECTORIES; \  
    # Architecture-specific setup for ARM
    if echo "$TARGETARCH" | grep -q "arm"; then \
        # Add ARM architecture and update
        dpkg --add-architecture armhf; \
        apt-get update; \
        \
        # Install ARM-specific packages
        apt-get install -y --no-install-recommends \
            $PACKAGES_ARM_STEAMCMD $PACKAGES_ARM_BUILD; \
        \
        # Add and configure Box64: https://box86.debian.ryanfortner.dev/
        curl -fsSL https://ryanfortner.github.io/box64-debs/box64.list -o /etc/apt/sources.list.d/box64.list; \
        curl -fsSL https://ryanfortner.github.io/box64-debs/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box64-debs-archive-keyring.gpg; \
        \
        # Update and install Box86/Box64
        apt-get update; \
        apt-get install -y --no-install-recommends \
            box86; \ 
        \
        # Clean up
        apt-get autoremove --purge -y $PACKAGES_ARM_BUILD; \
    else \ 
        # AMD64 specific packages
        apt-get install -y --no-install-recommends \
            $PACKAGES_AMD64_STEAMCMD; \
    fi; \
    \
    # Final cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get autoremove --purge -y $PACKAGES_BASE_BUILD

# Change to non-root APP_NAME
USER $APP_NAME

# Copy scripts after changing to APP_NAME(user)
COPY --chown=$APP_NAME:$APP_NAME scripts $SCRIPTS
COPY \
    --from=steamcmd \
    --chown=$APP_NAME:$APP_NAME \
    # Copy user profile (8mb)
    /root/Steam $STEAMCMD_PROFILE \
    # Copy executables (300mb)
    $STEAMCMD_PATH $STEAMCMD_PATH 

# https://docs.docker.com/reference/dockerfile/#volume
VOLUME ["$APP_FILES"]
VOLUME ["$WORLD_FILES"]

# Expose necessary ports
EXPOSE 7777/udp 7777/tcp 7778/udp 27015/udp 25575/tcp

HEALTHCHECK --interval=1m --timeout=3s CMD pidof $APP_EXE || exit 1

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["conan_up.sh"]
