#!/bin/bash

set -Eeuo pipefail

HOOK_NAME="30_conan_functions.sh"
CONAN_CONFIG_DIR="${CONAN_CONFIG_DIR:-$WORLD_FILES/Saved/Config/LinuxServer}"
CONAN_NATIVE_EXECUTABLE="${CONAN_NATIVE_EXECUTABLE:-$APP_FILES/ConanSandbox/Binaries/Linux/ConanSandboxServer-Linux-Shipping}"
CONAN_STATE_DIR="${CONAN_STATE_DIR:-$WORLD_FILES/.docker-conan-exiles-server}"

fail() {
    log "ERROR: $*" "$HOOK_NAME"
    return 1
}

warn() {
    log "WARNING: $*" "$HOOK_NAME"
}

validate_integer_range() {
    local name="$1"
    local value="$2"
    local min="$3"
    local max="$4"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < min || value > max )); then
        fail "$name must be an integer from $min through $max; got '$value'"
        return 1
    fi
}

validate_positive_integer() {
    local name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
        fail "$name must be a positive integer; got '$value'"
        return 1
    fi
}

validate_single_line() {
    local name="$1"
    local value="$2"

    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        fail "$name may not contain newlines"
        return 1
    fi
}

set_ini_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    local tmp

    mkdir -p "$(dirname "$file")"
    touch "$file"
    tmp="$(mktemp "${file}.rewrite.XXXXXX")"

    CONAN_INI_VALUE="$value" awk -v target="[$section]" -v key="$key" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }

        BEGIN {
            value = ENVIRON["CONAN_INI_VALUE"]
            in_target = 0
            section_seen = 0
            key_written = 0
        }

        /^\[[^]]+\][[:space:]]*$/ {
            if (in_target && !key_written) {
                print key "=" value
                key_written = 1
            }

            header = $0
            sub(/[[:space:]]+$/, "", header)
            in_target = (header == target)
            if (in_target) {
                section_seen = 1
            }
            print
            next
        }

        {
            if (in_target) {
                separator = index($0, "=")
                if (separator > 0) {
                    existing_key = trim(substr($0, 1, separator - 1))
                    if (existing_key == key) {
                        if (!key_written) {
                            print key "=" value
                            key_written = 1
                        }
                        next
                    }
                }
            }
            print
        }

        END {
            if (in_target && !key_written) {
                print key "=" value
            } else if (!section_seen) {
                if (NR > 0) {
                    print ""
                }
                print target
                print key "=" value
            }
        }
    ' "$file" > "$tmp"

    chmod --reference="$file" "$tmp" 2>/dev/null || true
    if cmp -s "$tmp" "$file"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$file"
    fi
}

persist_directory() {
    local source_path="$1"
    local target_path="$2"
    local current_target current_target_path

    mkdir -p "$(dirname "$source_path")" "$target_path"

    if [ -L "$source_path" ]; then
        current_target="$(readlink "$source_path")"
        if [[ "$current_target" = /* ]]; then
            current_target_path="$(realpath -m "$current_target")"
        else
            current_target_path="$(realpath -m "$(dirname "$source_path")/$current_target")"
        fi

        if [ "$current_target_path" != "$(realpath -m "$target_path")" ]; then
            fail "$source_path points to $current_target; expected $target_path"
            return 1
        fi
        return 0
    fi

    if [ -e "$source_path" ]; then
        if [ ! -d "$source_path" ]; then
            fail "$source_path exists but is not a directory"
            return 1
        fi

        # Persistent /world state is authoritative. Copy only source entries
        # that are missing from the target before replacing the install path
        # with its stable symlink.
        cp -a -n "$source_path/." "$target_path/"
        rm -rf "$source_path"
    fi

    ln -s "$target_path" "$source_path"
}

migrate_windows_settings() {
    local legacy_dir="$WORLD_FILES/Saved/Config/WindowsServer"
    local filename source target

    [ -d "$legacy_dir" ] || return 0
    mkdir -p "$CONAN_CONFIG_DIR"

    for source in "$legacy_dir"/*.ini; do
        [ -f "$source" ] || continue
        filename="$(basename "$source")"
        target="$CONAN_CONFIG_DIR/$filename"
        if [ ! -e "$target" ]; then
            cp -p "$source" "$target"
            log "Migrated legacy WindowsServer setting $filename to LinuxServer" "$HOOK_NAME"
        fi
    done
}

migrate_database_case() {
    local suffix legacy native

    for suffix in "" "-wal" "-shm"; do
        legacy="$WORLD_FILES/Saved/Game.db${suffix}"
        native="$WORLD_FILES/Saved/game.db${suffix}"

        if [ -e "$legacy" ] && [ -e "$native" ]; then
            fail "both $legacy and $native exist; refusing to choose between database copies"
            return 1
        fi

        if [ -e "$legacy" ]; then
            mv "$legacy" "$native"
            log "Renamed $(basename "$legacy") to $(basename "$native") for native Linux" "$HOOK_NAME"
        fi
    done
}

reconcile_allow_list() {
    local requested_allow_list="${STEAM_ID_ALLOW_LIST:-${SERVER_ALLOW_LIST:-}}"
    local target_path="${STEAM_ID_ALLOW_LIST_PATH:-$WORLD_FILES/Saved/whitelist.txt}"
    local tmp

    case "$target_path" in
        /*) ;;
        *)
            fail "STEAM_ID_ALLOW_LIST_PATH must be absolute; got '$target_path'"
            return 1
            ;;
    esac

    if [ -z "$requested_allow_list" ]; then
        set_ini_value "$CONAN_CONFIG_DIR/ServerSettings.ini" "ServerSettings" "EnableWhitelist" "False"
        log "Conan allow list disabled" "$HOOK_NAME"
        return 0
    fi

    mkdir -p "$(dirname "$target_path")"
    tmp="$(mktemp "${target_path}.candidate.XXXXXX")"
    printf '%s\n' "$requested_allow_list" \
        | tr ',' '\n' \
        | sed 's/\r$//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
        | awk 'NF' \
        > "$tmp"

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        fail "allow-list input did not contain any IDs"
        return 1
    fi

    if [ ! -f "$target_path" ] || ! cmp -s "$tmp" "$target_path"; then
        cat "$tmp" > "$target_path"
        log "Updated Conan allow list at $target_path" "$HOOK_NAME"
    fi
    rm -f "$tmp"

    set_ini_value "$CONAN_CONFIG_DIR/ServerSettings.ini" "ServerSettings" "EnableWhitelist" "True"
}

remove_previous_managed_mod_links() {
    local state_file="$CONAN_STATE_DIR/managed-mod-files.txt"
    local relative target

    [ -f "$state_file" ] || return 0

    while IFS= read -r relative || [ -n "$relative" ]; do
        [ -n "$relative" ] || continue
        target="$WORLD_FILES/Mods/$relative"
        if [ -L "$target" ]; then
            rm -f "$target"
        elif [ -e "$target" ]; then
            warn "Preserving operator-owned mod file that replaced managed link: $target"
        fi
    done < "$state_file"

    rm -f "$state_file"
}

link_managed_mod_file() {
    local source="$1"
    local target_name="$2"
    local state_file="$3"
    local target="$WORLD_FILES/Mods/$target_name"
    local existing_target

    if [ -L "$target" ]; then
        existing_target="$(readlink "$target")"
        if [ "$existing_target" != "$source" ]; then
            fail "mod filename collision at $target: points to $existing_target, wanted $source"
            return 1
        fi
    elif [ -e "$target" ]; then
        fail "mod filename collision at $target; refusing to overwrite operator-owned file"
        return 1
    else
        ln -s "$source" "$target"
    fi

    printf '%s\n' "$target_name" >> "$state_file"
}

reconcile_mods() {
    local requested_mod_ids="${STEAM_WORKSHOP_MOD_IDS:-${SERVER_MOD_IDS:-}}"
    local state_file="$CONAN_STATE_DIR/managed-mod-files.txt"
    local modlist="$WORLD_FILES/Mods/modlist.txt"
    local mod_id item_dir pak companion base companion_name
    local -a mod_ids=()
    local -a paks=()
    local candidate_modlist

    mkdir -p "$WORLD_FILES/Mods" "$CONAN_STATE_DIR"
    remove_previous_managed_mod_links

    if [ -z "$requested_mod_ids" ]; then
        set_ini_value "$CONAN_CONFIG_DIR/ServerSettings.ini" "ServerSettings" "ServerModList" ""
        log "No container-managed Conan mods requested" "$HOOK_NAME"
        return 0
    fi

    while IFS= read -r mod_id; do
        [ -n "$mod_id" ] || continue
        if [[ ! "$mod_id" =~ ^[0-9]+$ ]]; then
            fail "Workshop mod ID must be numeric; got '$mod_id'"
            return 1
        fi
        mod_ids+=("$mod_id")
    done < <(
        printf '%s\n' "$requested_mod_ids" \
            | tr ', ' '\n' \
            | awk 'NF'
    )

    if (( ${#mod_ids[@]} == 0 )); then
        fail "mod input did not contain any Workshop IDs"
        return 1
    fi

    : > "$state_file"
    candidate_modlist="$(mktemp "${modlist}.candidate.XXXXXX")"

    for mod_id in "${mod_ids[@]}"; do
        log "Downloading Conan Workshop item $mod_id" "$HOOK_NAME"
        "$STEAMCMD_EXEC" \
            +force_install_dir "$STEAM_LIBRARY" \
            +login anonymous \
            +workshop_download_item "$STEAM_CLIENT_APPID" "$mod_id" \
            +quit | log_stdout

        item_dir="$STEAM_LIBRARY/steamapps/workshop/content/$STEAM_CLIENT_APPID/$mod_id"
        if [ ! -d "$item_dir" ]; then
            rm -f "$candidate_modlist"
            fail "Workshop item $mod_id did not download to $item_dir"
            return 1
        fi

        mapfile -t paks < <(find "$item_dir" -type f -name '*.pak' -print | sort)
        if (( ${#paks[@]} == 0 )); then
            rm -f "$candidate_modlist"
            fail "Workshop item $mod_id does not contain a .pak file"
            return 1
        fi

        for pak in "${paks[@]}"; do
            link_managed_mod_file "$pak" "$(basename "$pak")" "$state_file"
            printf '*%s\n' "$(basename "$pak")" >> "$candidate_modlist"

            base="${pak%.pak}"
            for companion in "$base".utoc "$base".ucas; do
                if [ -f "$companion" ]; then
                    companion_name="$(basename "$companion")"
                    link_managed_mod_file "$companion" "$companion_name" "$state_file"
                fi
            done
        done
    done

    if ! cmp -s "$candidate_modlist" "$modlist"; then
        cat "$candidate_modlist" > "$modlist"
        log "Updated Conan mod list at $modlist" "$HOOK_NAME"
    fi
    rm -f "$candidate_modlist"

    set_ini_value "$CONAN_CONFIG_DIR/ServerSettings.ini" "ServerSettings" "ServerModList" "modlist.txt"
}

server_name="${SERVER_NAME:-Teriyakolypse}"
server_player_pass="${SERVER_PLAYER_PASS:-MySecretPassword}"
server_admin_pass="${SERVER_ADMIN_PASS:-MySecretPasswordAdmin}"
server_region="${SERVER_REGION_ID:-1}"
server_nudity="${SERVER_NUDITY_POLICY:-0}"
server_port="${SERVER_PORT:-7777}"
server_query_port="${SERVER_QUERY_PORT:-27015}"
server_max_players="${SERVER_MAX_PLAYERS:-40}"

validate_single_line SERVER_NAME "$server_name"
validate_single_line SERVER_PLAYER_PASS "$server_player_pass"
validate_single_line SERVER_ADMIN_PASS "$server_admin_pass"
validate_integer_range SERVER_REGION_ID "$server_region" 0 5
validate_integer_range SERVER_NUDITY_POLICY "$server_nudity" 0 2
validate_integer_range SERVER_PORT "$server_port" 1 65534
validate_integer_range SERVER_QUERY_PORT "$server_query_port" 1 65535
validate_positive_integer SERVER_MAX_PLAYERS "$server_max_players"

mkdir -p \
    "$WORLD_FILES/Saved/Logs" \
    "$WORLD_FILES/Config" \
    "$WORLD_FILES/Mods" \
    "$WORLD_FILES/Engine/Config" \
    "$CONAN_STATE_DIR"

persist_directory "$APP_FILES/Engine/Config" "$WORLD_FILES/Engine/Config"
persist_directory "$APP_FILES/ConanSandbox/Saved" "$WORLD_FILES/Saved"
persist_directory "$APP_FILES/ConanSandbox/Config" "$WORLD_FILES/Config"
persist_directory "$APP_FILES/ConanSandbox/Mods" "$WORLD_FILES/Mods"

migrate_windows_settings
migrate_database_case

mkdir -p "$CONAN_CONFIG_DIR"
touch \
    "$CONAN_CONFIG_DIR/Engine.ini" \
    "$CONAN_CONFIG_DIR/Game.ini" \
    "$CONAN_CONFIG_DIR/ServerSettings.ini"

set_ini_value "$CONAN_CONFIG_DIR/Engine.ini" "URL" "Port" "$server_port"
set_ini_value "$CONAN_CONFIG_DIR/Engine.ini" "OnlineSubsystemNull" "GameServerQueryPort" "$server_query_port"
set_ini_value "$CONAN_CONFIG_DIR/Engine.ini" "OnlineSubsystem" "ServerName" "$server_name"
set_ini_value "$CONAN_CONFIG_DIR/Engine.ini" "OnlineSubsystem" "ServerPassword" "$server_player_pass"

set_ini_value "$CONAN_CONFIG_DIR/Game.ini" "/Script/Engine.GameSession" "MaxPlayers" "$server_max_players"

set_ini_value "$CONAN_CONFIG_DIR/ServerSettings.ini" "ServerSettings" "ServerPassword" "$server_player_pass"
set_ini_value "$CONAN_CONFIG_DIR/ServerSettings.ini" "ServerSettings" "AdminPassword" "$server_admin_pass"
set_ini_value "$CONAN_CONFIG_DIR/ServerSettings.ini" "ServerSettings" "serverRegion" "$server_region"
set_ini_value "$CONAN_CONFIG_DIR/ServerSettings.ini" "ServerSettings" "MaxNudity" "$server_nudity"

reconcile_allow_list
reconcile_mods

[ -f "$CONAN_NATIVE_EXECUTABLE" ] || {
    fail "native Conan executable not found after SteamCMD update: $CONAN_NATIVE_EXECUTABLE"
    return 1
}
chmod +x "$CONAN_NATIVE_EXECUTABLE"

log "Conan native Linux persistence and configuration are ready" "$HOOK_NAME"
