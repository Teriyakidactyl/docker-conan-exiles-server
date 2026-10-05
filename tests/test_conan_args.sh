#!/bin/bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGS_FILE="$REPO_ROOT/scripts/container/conan.args"

export SERVER_PORT=7777
export SERVER_QUERY_PORT=27015
export SERVER_MAX_PLAYERS=40

mapfile -t args < <(envsubst < "$ARGS_FILE")

expected=(
    ConanSandbox
    -log
    -console
    -Port=7777
    -QueryPort=27015
    -MaxPlayers=40
)

if [ "${#args[@]}" -ne "${#expected[@]}" ]; then
    printf 'expected %d arguments, got %d\n' "${#expected[@]}" "${#args[@]}" >&2
    exit 1
fi

for i in "${!expected[@]}"; do
    if [ "${args[$i]}" != "${expected[$i]}" ]; then
        printf 'argument %d mismatch: expected <%s>, got <%s>\n' "$i" "${expected[$i]}" "${args[$i]}" >&2
        exit 1
    fi
done

echo "Conan argument contract test passed"
