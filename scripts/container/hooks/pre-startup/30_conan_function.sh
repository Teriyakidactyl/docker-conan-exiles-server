#!/bin/bash

update_config_element() {
    local element="$1"
    local new_value="$2"

    # Usage example:
    # update_config_element "ServerName" "NewServerName" "$WORLD_FILES"

    # Find and update the element in .ini files
    find "$WORLD_FILES" -type f -name "*.ini" -exec grep -q "$element" {} \; -exec sed -i "s/^$element=.*/$element=$new_value/" {} \; -exec awk -v element="$element" -v new_value="$new_value" 'BEGIN { FS = "=" } $1 == element { print FILENAME ":" NR ": " $0 }' {} \;
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