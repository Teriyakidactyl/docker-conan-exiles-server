#!/bin/bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/container/hooks/pre-startup/30_conan_functions.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

log() { :; }
log_stdout() { cat >/dev/null; }

export APP_FILES="$TMP_ROOT/app"
export WORLD_FILES="$TMP_ROOT/world"
export STEAM_LIBRARY="$TMP_ROOT/steam-library"
export STEAM_CLIENT_APPID=440900
export STEAM_ID_ALLOW_LIST_PATH="$WORLD_FILES/Saved/whitelist.txt"
export CONAN_STATE_DIR="$WORLD_FILES/.docker-conan-exiles-server"
export CONAN_NATIVE_EXECUTABLE="$APP_FILES/ConanSandbox/Binaries/Linux/ConanSandboxServer-Linux-Shipping"

mkdir -p \
    "$APP_FILES/Engine/Config" \
    "$APP_FILES/ConanSandbox/Saved/Config/WindowsServer" \
    "$APP_FILES/ConanSandbox/Config" \
    "$APP_FILES/ConanSandbox/Mods" \
    "$(dirname "$CONAN_NATIVE_EXECUTABLE")" \
    "$STEAM_LIBRARY/steamapps/workshop/content/$STEAM_CLIENT_APPID/111" \
    "$STEAM_LIBRARY/steamapps/workshop/content/$STEAM_CLIENT_APPID/222"

printf '#!/bin/true\n' > "$CONAN_NATIVE_EXECUTABLE"
cat > "$APP_FILES/ConanSandbox/Saved/Config/WindowsServer/Engine.ini" <<'EOF'
[URL]
Port=7000
UnknownEngineSetting=preserve-me

[OnlineSubsystem]
ServerName=Legacy Name
ServerPassword=legacy-password
EOF
cat > "$APP_FILES/ConanSandbox/Saved/Config/WindowsServer/ServerSettings.ini" <<'EOF'
[ServerSettings]
AdminPassword=legacy-admin
EnableWhitelist=False
UnknownServerSetting=preserve-me
EOF
printf 'database\n' > "$APP_FILES/ConanSandbox/Saved/Game.db"

printf 'mod-one\n' > "$STEAM_LIBRARY/steamapps/workshop/content/$STEAM_CLIENT_APPID/111/One.pak"
printf 'mod-one-utoc\n' > "$STEAM_LIBRARY/steamapps/workshop/content/$STEAM_CLIENT_APPID/111/One.utoc"
printf 'mod-one-ucas\n' > "$STEAM_LIBRARY/steamapps/workshop/content/$STEAM_CLIENT_APPID/111/One.ucas"
printf 'mod-two\n' > "$STEAM_LIBRARY/steamapps/workshop/content/$STEAM_CLIENT_APPID/222/Two.pak"

FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/steamcmd" <<'EOF'
#!/bin/bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$STEAMCMD_TEST_LOG"
EOF
chmod +x "$FAKE_BIN/steamcmd"
export STEAMCMD_EXEC="$FAKE_BIN/steamcmd"
export STEAMCMD_TEST_LOG="$TMP_ROOT/steamcmd.log"

export SERVER_NAME='Native & / Server'
export SERVER_PLAYER_PASS='player&/password'
export SERVER_ADMIN_PASS='admin&/password'
export SERVER_REGION_ID=1
export SERVER_NUDITY_POLICY=2
export SERVER_PORT=7777
export SERVER_QUERY_PORT=27015
export SERVER_MAX_PLAYERS=40
export STEAM_ID_ALLOW_LIST='7656111,7656112'
export STEAM_WORKSHOP_MOD_IDS='111,222'
unset SERVER_ALLOW_LIST SERVER_MOD_IDS

source "$HOOK"

for link in "$APP_FILES/Engine/Config" "$APP_FILES/ConanSandbox/Saved" "$APP_FILES/ConanSandbox/Config" "$APP_FILES/ConanSandbox/Mods"; do
    test -L "$link"
done

test -f "$WORLD_FILES/Saved/Config/LinuxServer/Engine.ini"
test -f "$WORLD_FILES/Saved/game.db"
test ! -e "$WORLD_FILES/Saved/Game.db"
grep -Fqx 'Port=7777' "$WORLD_FILES/Saved/Config/LinuxServer/Engine.ini"
grep -Fqx 'GameServerQueryPort=27015' "$WORLD_FILES/Saved/Config/LinuxServer/Engine.ini"
grep -Fqx 'ServerName=Native & / Server' "$WORLD_FILES/Saved/Config/LinuxServer/Engine.ini"
grep -Fqx 'ServerPassword=player&/password' "$WORLD_FILES/Saved/Config/LinuxServer/Engine.ini"
grep -Fqx 'UnknownEngineSetting=preserve-me' "$WORLD_FILES/Saved/Config/LinuxServer/Engine.ini"
grep -Fqx 'AdminPassword=admin&/password' "$WORLD_FILES/Saved/Config/LinuxServer/ServerSettings.ini"
grep -Fqx 'UnknownServerSetting=preserve-me' "$WORLD_FILES/Saved/Config/LinuxServer/ServerSettings.ini"
grep -Fqx 'EnableWhitelist=True' "$WORLD_FILES/Saved/Config/LinuxServer/ServerSettings.ini"
grep -Fqx 'ServerModList=modlist.txt' "$WORLD_FILES/Saved/Config/LinuxServer/ServerSettings.ini"
grep -Fqx '7656111' "$WORLD_FILES/Saved/whitelist.txt"
grep -Fqx '7656112' "$WORLD_FILES/Saved/whitelist.txt"

for managed in One.pak One.utoc One.ucas Two.pak; do test -L "$WORLD_FILES/Mods/$managed"; done
grep -Fqx '*One.pak' "$WORLD_FILES/Mods/modlist.txt"
grep -Fqx '*Two.pak' "$WORLD_FILES/Mods/modlist.txt"
grep -Fq '+workshop_download_item 440900 111' "$STEAMCMD_TEST_LOG"
grep -Fq '+workshop_download_item 440900 222' "$STEAMCMD_TEST_LOG"
test -x "$CONAN_NATIVE_EXECUTABLE"

one_target_before="$(readlink "$WORLD_FILES/Mods/One.pak")"
cat > "$FAKE_BIN/steamcmd" <<'EOF'
#!/bin/bash
exit 42
EOF
chmod +x "$FAKE_BIN/steamcmd"
set +e
( source "$HOOK" )
failure_status=$?
set -e
test "$failure_status" -ne 0
test -L "$WORLD_FILES/Mods/One.pak"
test "$(readlink "$WORLD_FILES/Mods/One.pak")" = "$one_target_before"

cat > "$FAKE_BIN/steamcmd" <<'EOF'
#!/bin/bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$STEAMCMD_TEST_LOG"
EOF
chmod +x "$FAKE_BIN/steamcmd"

rm -rf "$WORLD_FILES/Engine/Config"
source "$HOOK"
test -d "$WORLD_FILES/Engine/Config"
test -L "$APP_FILES/Engine/Config"

export STEAM_ID_ALLOW_LIST=""
export STEAM_WORKSHOP_MOD_IDS=""
source "$HOOK"
grep -Fqx 'EnableWhitelist=False' "$WORLD_FILES/Saved/Config/LinuxServer/ServerSettings.ini"
grep -Fqx 'ServerModList=' "$WORLD_FILES/Saved/Config/LinuxServer/ServerSettings.ini"
test -f "$WORLD_FILES/Saved/whitelist.txt"
for managed in One.pak One.utoc One.ucas Two.pak; do test ! -L "$WORLD_FILES/Mods/$managed"; done

echo "Conan hook contract test passed"
