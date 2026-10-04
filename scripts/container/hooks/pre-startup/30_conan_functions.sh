#!/bin/bash

# Whitelist: https://forums.funcom.com/t/conan-and-the-whitelist-dilema-a-funcom-story/107376

# SteamCMD updates /app before this hook runs. A game update can therefore
# recreate real directories where persistence symlinks existed on the previous
# start. Reconcile these paths every time rather than relying on image-layer
# links that are hidden by /app and /world mounts.
#
# Existing persistent files win during migration. An unexpected symlink is an
# ownership conflict and fails loudly instead of being silently overwritten.
persist_directory() {
    local source_path="$1"
    local target_path="$2"
    local current_target
    local current_target_path

    mkdir -p "$(dirname "$source_path")" "$target_path"

    if [ -L "$source_path" ]; then
        current_target="$(readlink "$source_path")"
        if [[ "$current_target" = /* ]]; then
            current_target_path="$(realpath -m "$current_target")"
        else
            current_target_path="$(realpath -m "$(dirname "$source_path")/$current_target")"
        fi

        if [ "$current_target_path" != "$(realpath -m "$target_path")" ]; then
            log "ERROR: $source_path points to $current_target; expected $target_path" "30_conan_functions.sh"
            return 1
        fi
        return 0
    fi

    if [ -e "$source_path" ]; then
        if [ ! -d "$source_path" ]; then
            log "ERROR: $source_path exists but is not a directory" "30_conan_functions.sh"
            return 1
        fi
        cp -a -n "$source_path/." "$target_path/"
        rm -rf "$source_path"
    fi

    ln -s "$target_path" "$source_path"
}

mkdir -p \
    "$WORLD_FILES/Saved/Logs" \
    "$WORLD_FILES/Config" \
    "$WORLD_FILES/Mods" \
    "$WORLD_FILES/Engine/Config"

persist_directory "$APP_FILES/Engine/Config" "$WORLD_FILES/Engine/Config"
persist_directory "$APP_FILES/ConanSandbox/Saved" "$WORLD_FILES/Saved"
persist_directory "$APP_FILES/ConanSandbox/Config" "$WORLD_FILES/Config"
persist_directory "$APP_FILES/ConanSandbox/Mods" "$WORLD_FILES/Mods"

update_config_element() {
    local element="$1"
    local new_value="$2"

    # Usage example:
    # update_config_element "ServerName" "NewServerName" "$WORLD_FILES"

    # Find and update the element in .ini files
    find "$WORLD_FILES" -type f -name "*.ini" -exec grep -q "$element" {} \; -exec sed -i "s/^$element=.*/$element=$new_value/" {} \; -exec awk -v element="$element" -v new_value="$new_value" 'BEGIN { FS = "=" } $1 == element { print FILENAME ":" NR ": " $0 }' {} \;
}

mod_updates() {
    
    # https://forums.funcom.com/t/conan-exiles-dedicated-server-launcher-official-version-1-7-8-beta-1-7-9/21699#mods
    # force_install_dir "$WORLD_FILES/Mods" > /Mods/steamapps/workshop/conent/$MOD_ID

    # mod_updates(): Manages mods for Conan Exiles server
    # - Downloads specified mods via SteamCMD
    # - Removes unspecified mods
    # - Updates modlist.txt
    # Logic:
    # 1. If mods specified:
    #    - Download each mod
    #    - Link .pak files to server mod directory
    #    - Remove obsolete mods
    #    - Update modlist.txt
    # 2. If no mods: Clear mod directory, create empty modlist.txt

    # Keep the older SERVER_MOD_IDS operator API working while preferring the
    # shared base's STEAM_WORKSHOP_MOD_IDS variable when it is supplied.
    local requested_mod_ids="${STEAM_WORKSHOP_MOD_IDS:-${SERVER_MOD_IDS:-}}"

    if [ -n "$requested_mod_ids" ]; then
        IFS=',' read -ra MOD_IDS <<< "$requested_mod_ids"
        rm -rf "$WORLD_FILES/Mods"/*
        # Download and update mods
        for MOD_ID in "${MOD_IDS[@]}"; do
            log "Downloading mod with ID: $MOD_ID"
            # Always use STEAMCMD_EXEC. On arm64 this is the base-owned wrapper
            # that preserves Valve's self-update behavior while invoking the
            # 32-bit client through Box64/Box32.
            "$STEAMCMD_EXEC" \
            +force_install_dir "$STEAM_LIBRARY" \
            +login anonymous \
            +workshop_download_item $STEAM_CLIENT_APPID $MOD_ID \
            +quit | log_stdout
            find "$STEAM_LIBRARY" -path "*$MOD_ID*.pak" -exec ln -sf {} /world/Mods \; 
        done

        # Remove mods that are no longer in the list
        for MOD_DIR in "$WORLD_FILES/Mods"/*; do
            if [ -d "$MOD_DIR" ]; then
                MOD_ID=$(basename "$MOD_DIR")
                if ! [[ " ${MOD_IDS[@]} " =~ " ${MOD_ID} " ]]; then
                    log "Removing mod with ID: $MOD_ID"
                    rm -rf "$MOD_DIR"
                fi
            fi
        done

        # Create the modlist.txt file
        find "$WORLD_FILES/Mods" -type l -name "*.pak" -exec basename {} \; | sed 's/^/*/' > "$WORLD_FILES/Mods/modlist.txt"
        log "Mods enabled: "
        cat $WORLD_FILES/Mods/modlist.txt | log_stdout
    else
        rm -rf $WORLD_FILES/Mods/*
        > "$WORLD_FILES/Mods/modlist.txt"  # Create empty modlist.txt
    fi

}

check_whitelist() {
    local requested_allow_list="${STEAM_ID_ALLOW_LIST:-${SERVER_ALLOW_LIST:-}}"

    if [ -n "$requested_allow_list" ]; then
        update_config_element "EnableWhitelist" "True"
        
        # Remove existing whitelist file if it exists
        if [ -f "$STEAM_ID_ALLOW_LIST_PATH" ]; then
            rm "$STEAM_ID_ALLOW_LIST_PATH" || { log "Failed to remove existing whitelist file: $STEAM_ID_ALLOW_LIST_PATH"; return 1; }
        fi
        
        # Create an empty whitelist file
        touch "$STEAM_ID_ALLOW_LIST_PATH" || { log "Failed to create whitelist file: $STEAM_ID_ALLOW_LIST_PATH"; return 1; }
        
        # Populate whitelist file with STEAM_IDs
        # Split STEAMID_ALLOW_LIST on commas and iterate over each part
        IFS=", " read -r -a STEAM_IDS <<< "$requested_allow_list"
        for STEAM_ID in "${STEAM_IDS[@]}"; do
            echo "$STEAM_ID" >> "$STEAM_ID_ALLOW_LIST_PATH" || { log "Failed to write to whitelist file: $STEAM_ID_ALLOW_LIST_PATH"; return 1; }
        done
        
        log "Allow list created:"
        cat "$STEAM_ID_ALLOW_LIST_PATH" | log_stdout
    fi
}

# Display server configuration
log "+----------------------------------+"
log "SERVER_NAME: $SERVER_NAME"
log "SERVER_PLAYER_PASS: $SERVER_PLAYER_PASS"
log "+----------------------------------+"
sleep 1

# Execute the server command, reff: https://www.valheimgame.com/support/a-guide-to-dedicated-servers/

# Update game configs, https://www.bestconanhosting.com/guides/how-to-configure-your-conan-exiles-server-all-options-explained/
update_config_element "ServerName" "$SERVER_NAME"
update_config_element "ServerPassword" "$SERVER_PLAYER_PASS"
update_config_element "AdminPassword" "$SERVER_ADMIN_PASS"
update_config_element "serverRegion" "$SERVER_REGION_ID"
update_config_element "MaxNudity" "$SERVER_NUDITY_POLICY"

check_whitelist
mod_updates