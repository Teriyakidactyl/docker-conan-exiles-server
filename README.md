# Docker Conan-Exiles Server Images

This Docker image provides a Conan-Exiles dedicated server, supporting **both `amd64` and `arm64` (x86, arm) architectures.**

![Teriyakidactyl Delivers!™](/images/teriyakidactyl_conan.png)

**_Teriyakidactyl Delivers!™_**

## Features

- Supports `amd64` and `arm64` architectures
- Runs under non-root user
- Automatic server updates via [steamcmd](https://developer.valvesoftware.com/wiki/SteamCMD) (on reboot)
- Cross-platform compatibility using [Box86](https://github.com/ptitSeb/box86)/[Box64](https://github.com/ptitSeb/box64) for `arm64` systems (tested on [Oracle Ampere](https://www.oracle.com/cloud/compute/arm/))
- Colored :rainbow: (even in Portainer), organized logs (under development)

![Teriyakidactyl Delivers!™](/images/logs.png)

## Environment Variables

Configure your server using the following environment variables:

- `SERVER_PLAYER_PASS`: Server password (default: "MySecretPassword")
- `SERVER_ADMIN_PASS`: Server password (default: "MySecretPassword")
- `SERVER_NAME`: Server name (default: "MyValheimServer")
- `SERVER_REGION_ID`: Region ID

## Usage

1. Pull the image:
   
```bash
docker pull ghcr.io/teriyakidactyl/docker-conan-exiles-server:latest
```

2. Run the container:
   
```bash
UR_PATH="/root/conan"
mkdir -p $UR_PATH/world  $UR_PATH/app

docker run -d \
-e SERVER_NAME="Teriyakolypse" \
-e SERVER_PLAYER_PASS="MySecretPassword" \
-e SERVER_ADMIN_PASS="MySecretPasswordAdmin" \
-v $UR_PATH/world:/world \
-v $UR_PATH/app:/app \
-p 7777-7778:7777-7778/udp \
--name Conan-Exiles-Server \
ghcr.io/teriyakidactyl/docker-conan-exiles-server:latest

```

Replace `UR_PATH="/root/conan"` with the path where you want to store your app/world data.

## Building the Image

To build the image yourself:

```docker build -t ghcr.io/teriyakidactyl/docker-conan-exiles-server:latest .```

## Healthcheck

The container includes a basic healthcheck that verifies if the Conan server process is running.

## Support

For issues, feature requests, or contributions, please use the GitHub issue tracker.
