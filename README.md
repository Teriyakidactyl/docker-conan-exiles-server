# Docker Conan Exiles Enhanced Server Images

Multi-architecture Conan Exiles Enhanced dedicated-server image built on
[`docker-steamcmd-server`](https://github.com/Teriyakidactyl/docker-steamcmd-server).
The image uses the current native Linux dedicated-server payload on both
architectures. On `arm64`, the shared base supplies Box64 for the x86_64 game
binary; Conan-specific code does not own architecture emulation.

![Teriyakidactyl Delivers!](./images/teriyakidactyl_conan.png)

## Features

- Native Linux Conan Exiles Enhanced server
- `amd64` and `arm64` images from the same application contract
- Non-root game execution
- SteamCMD update-on-start
- Graceful interrupt-based shutdown
- One persistent `/world` volume for Conan mutable state
- Runtime-repaired persistence symlinks after SteamCMD updates
- Environment-driven server settings, allow list, and Workshop mods
- Safe, section-specific INI reconciliation that preserves unknown settings

## Persistence

The image intentionally collects Conan's mutable game state under one `/world`
volume while leaving `/app` as the Steam-installed application volume. After
SteamCMD updates, the pre-start hook reconciles these links:

| Application path | Persistent target |
| --- | --- |
| `/app/Engine/Config` | `/world/Engine/Config` |
| `/app/ConanSandbox/Saved` | `/world/Saved` |
| `/app/ConanSandbox/Config` | `/world/Config` |
| `/app/ConanSandbox/Mods` | `/world/Mods` |

The persistent target wins during reconciliation. If SteamCMD recreates a real
directory at one of the application paths, files missing from `/world` are
copied in and the application path is restored as a symlink.

Keep both `/app` and `/world` persistent across container recreation.

## Native migration

Existing installations are migrated conservatively on the first native start:

- `.ini` files found under `/world/Saved/Config/WindowsServer` are copied into
  `/world/Saved/Config/LinuxServer` only when the corresponding LinuxServer file
  does not already exist.
- `Game.db`, `Game.db-wal`, and `Game.db-shm` are renamed to lowercase
  `game.db...` names required by the case-sensitive Linux filesystem.
- If both an uppercase and lowercase database copy exist, startup fails instead
  of choosing one and risking the wrong world.

Legacy files are not deleted merely because a native equivalent exists. The first native boot can take longer because SteamCMD must materialize the Linux payload before the migration hook runs.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `SERVER_NAME` | `Teriyakolypse` | Advertised server name |
| `SERVER_PLAYER_PASS` | `MySecretPassword` | Join password |
| `SERVER_ADMIN_PASS` | `MySecretPasswordAdmin` | Admin password |
| `SERVER_REGION_ID` | `1` | Visible region (`0`–`5`) |
| `SERVER_NUDITY_POLICY` | `0` | Nudity policy (`0`, `1`, or `2`) |
| `SERVER_PORT` | `7777` | Game port; the pinger uses the next UDP port |
| `SERVER_QUERY_PORT` | `27015` | Steam query port |
| `SERVER_MAX_PLAYERS` | `40` | Maximum players |
| `STEAM_ID_ALLOW_LIST` | empty | Comma- or newline-separated allowed Steam IDs |
| `SERVER_ALLOW_LIST` | empty | Compatibility alias for `STEAM_ID_ALLOW_LIST` |
| `STEAM_WORKSHOP_MOD_IDS` | empty | Ordered comma/space-separated Workshop IDs |
| `SERVER_MOD_IDS` | empty | Compatibility alias for `STEAM_WORKSHOP_MOD_IDS` |
| `UPDATE_ON_START` | `true` | Update Conan with SteamCMD before launch |
| `STEAM_VALIDATE` | `false` | Validate the Steam installation during update |
| `SHUTDOWN_TIMEOUT` | `120` | Internal graceful-stop timeout in seconds |

Passwords are written to Conan's configuration but are not printed by the
pre-start hook.

### Allow list

A non-empty allow list writes `/world/Saved/whitelist.txt` and sets
`EnableWhitelist=True`. Clearing the environment value sets
`EnableWhitelist=False` but leaves the existing file in place so operator data
is not destructively removed.

### Workshop mods

Workshop downloads use Conan Exiles client App ID `440900` through the
shared-base `STEAMCMD_EXEC` wrapper. The hook links the downloaded `.pak` files
and any matching `.utoc`/`.ucas` companions into `/world/Mods`, writes
`modlist.txt` in the requested order, and sets `ServerModList=modlist.txt`.

Only files recorded as container-managed symlinks are removed on the next
reconciliation. Unknown/operator-owned files in `/world/Mods` are preserved.

## Usage

```bash
UR_PATH="/root/conan"
mkdir -p "$UR_PATH/world" "$UR_PATH/app"

docker run -d \
  --name Conan-Exiles-Server \
  --restart unless-stopped \
  --stop-timeout 135 \
  -e SERVER_NAME="Teriyakolypse" \
  -e SERVER_PLAYER_PASS="MySecretPassword" \
  -e SERVER_ADMIN_PASS="MySecretPasswordAdmin" \
  -v "$UR_PATH/world:/world" \
  -v "$UR_PATH/app:/app" \
  -p 7777-7778:7777-7778/udp \
  -p 27015:27015/udp \
  -p 7777:7777/tcp \
  -p 25575:25575/tcp \
  ghcr.io/teriyakidactyl/docker-conan-exiles-server:latest
```

The Compose example supports the same two-volume persistence model. Compose
cannot calculate `SERVER_PORT+1`, so if the game port changes, set
`SERVER_PINGER_PORT` to the following port in the host mapping as well.

## Building

```bash
docker build -f dockerfile \
  -t ghcr.io/teriyakidactyl/docker-conan-exiles-server:latest .
```

`BASE_TAG` defaults to `trixie`; `bookworm` is also built.

## Image tags

The main workflow publishes `trixie` and `bookworm` multi-architecture
manifests, architecture-specific tags such as `trixie_arm64`, and `latest`
tracking the main-branch `trixie` image. Development builds use `_dev`.

## Health check

The inherited shared-base health check verifies the launched Conan process is
still alive.

## Support

For issues, feature requests, or contributions, use this repository's GitHub
issue tracker.
