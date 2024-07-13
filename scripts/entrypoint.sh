#!/bin/bash

STEAM_CONAN_SERVER_APPID="443030"
STEAM_CONAN_CLIENT_APPID="440900"
STEAM_PATH="/app/Steam"

echo "Checking paths and links ------------------------------------------------------------------------------"
# Create directory structure
mkdir -p $STEAM_PATH /world/$SERVER_NAME/Saved /world/$SERVER_NAME/Config /world/$SERVER_NAME/Mods /world/$SERVER_NAME/Engine/Config /app/Engine /app/ConanSandbox 

# Create symbolic links based on the SERVER_NAME environment variable
ln -sf "$STEAM_PATH" "/root"
ln -sf "/world/$SERVER_NAME/Engine/Config" /app/Engine
ln -sf "/world/$SERVER_NAME/Saved" /app/ConanSandbox
ln -sf "/world/$SERVER_NAME/Config" /app/ConanSandbox
ln -sf "/world/$SERVER_NAME/Mods" /app/ConanSandbox

echo "SteamCMD: Updating and Validating Conan-Exiles and Mods--------------------------------------------------------------"
# Run initial SteamCMD commands to update the server, 'validate' required to regenerate empty config with shared app volume
steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir /app +login anonymous +app_update $STEAM_CONAN_SERVER_APPID validate +quit

# Mod Updates
# Check if $SERVER_MOD_IDS exists, then use steamcmd to download mods to /world/$SERVER_NAME/Mods
if [ -n "$SERVER_MOD_IDS" ]; then
    # Loop through the list of mod IDs and download each one
    rm -rd /world/$SERVER_NAME/Mods/*
    IFS=',' read -ra MOD_IDS <<<"$SERVER_MOD_IDS"
    for MOD_ID in "${MOD_IDS[@]}"; do
        echo "Downloading mod with ID: $MOD_ID"
        steamcmd +force_install_dir $STEAM_PATH +login anonymous +workshop_download_item $STEAM_CONAN_CLIENT_APPID $MOD_ID +quit
        # Find MOD_ID PAK files and create symbolic links to /world/$SERVER_NAME/Mods
        find "$STEAM_PATH" -path "*$MOD_ID*.pak" -exec ln -sf {} /world/$SERVER_NAME/Mods \;                
    done
    # Create the modlist.txt file, https://nodecraft.com/support/games/conan-exiles/adding-mods-to-your-conan-exiles-server#h-create-modlisttxt-config-file-ae46981fe6
    find "/world/$SERVER_NAME/Mods" -type l -name "*.pak" -exec basename {} \; | sed 's/^/*/' > "/world/$SERVER_NAME/Mods/modlist.txt"
    echo "Mods enabled: "
    cat /world/$SERVER_NAME/Mods/modlist.txt
else
    rm -rd /world/$SERVER_NAME/Mods/*
fi

update_config_element() {
    local element="$1"
    local new_value="$2"
    local search_dir="$3"

    # Usage example:
    # update_config_element "ServerName" "NewServerName" "/world"

    # Find and update the element in .ini files
    find "$search_dir" -type f -name "*.ini" -exec grep -q "$element" {} \; -exec sed -i "s/^$element=.*/$element=$new_value/" {} \; -exec awk -v element="$element" -v new_value="$new_value" 'BEGIN { FS = "=" } $1 == element { print FILENAME ":" NR ": " $0 }' {} \;
}

# Check first time wine run, this will force Wine config creation so that our server load won't fail on first run.
if [ ! -d "$WINEPREFIX" ]; then
    echo "First run detected, wait 15 seconds for wine config creation."
    xvfb-run --auto-servernum --server-args='-screen 0 640x480x24:32 -nolisten tcp' wine64 /app/ConanSandboxServer.exe -nosteamclient -game -server -log & # -MULTIHOME=$MULTI_HOME_IP 

    # Sleep for 5 seconds
    sleep 15
    
    echo "'Rebooting' Wine in 10 seconds"
    # https://wiki.winehq.org/Wineboot
    wineboot -esui &
    sleep 10
    wineserver -k
fi

# TODO Rcon / Discord event relay (System booting up shuting down, updating etc.)

# TODO add Map switching variable LINK - Docker\conan-exiles\hyperborea\siptah.sh

# TODO watch for updates

# Update the ServerName configuration element
update_config_element "ServerName" "$SERVER_NAME" "/world"

# Update the ServerPlayerPassword configuration element
update_config_element "ServerPassword" "$SERVER_PLAYER_PASS" "/world"

# Update the AdminPassword configuration element
update_config_element "AdminPassword" "$SERVER_ADMIN_PASS" "/world"

# Update the serverRegion configuration element
update_config_element "serverRegion" "$SERVER_REGION_ID" "/world"

echo "Configuration files updated successfully"

echo "Starting Conan-Exiles via WINE"
xvfb-run --auto-servernum --server-args='-screen 0 640x480x24:32 -nolisten tcp' wine64 /app/ConanSandboxServer.exe -nosteamclient -game -server -log & # -MULTIHOME=$MULTI_HOME_IP 

echo "Tailing: ConanSandbox.log ----------------------------------------------------------------------------"

# Tail the Conan Exiles server log
LOG_FILE="/world/$SERVER_NAME/Saved/Logs/ConanSandbox.log"

# Wait for the log file to exist
while [ ! -f "$LOG_FILE" ]; do
    echo "First run? Waiting for $LOG_FILE to exist..."
    sleep 30
done

# Once the file exists, tail it
tail -f "$LOG_FILE"

# //NOTE Portainer not supporting color yet
#  | sed \
#     -e 's/\(.*ERROR.*\)/\x1B[31m\1\x1B[39m/             # Set ERROR text to red' \
#     -e 's/\(.*LogServerStats.*\)/\x1B[32m\1\x1B[39m/  # Set LogServerStats text to green'


