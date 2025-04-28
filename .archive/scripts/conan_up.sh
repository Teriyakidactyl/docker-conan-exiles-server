#!/bin/bash
source $SCRIPTS/conan_logging_functions
source $SCRIPTS/conan_server_functions


# Set Variables ---------------------------------------------------------------------------
export ARCH=$(dpkg --print-architecture)
export CONTAINER_START_TIME=$(date -u +%s)

# only configure box64 if $ARCH contains arm
if echo "$ARCH" | grep -q "arm"; then
    log "Running on $ARCH, setting ENV"
    # https://github.com/ptitSeb/box86/blob/master/docs/USAGE.md
    export BOX86_LOG=1
    export BOX86_TRACE_FILE=$LOGS/$APP_NAME'_box86.log'
    export DEBUGGER=box86 

    # Box64 + Wine: https://github.com/ptitSeb/box64/blob/main/docs/X64WINE.md
    ## https://forum.armbian.com/topic/19526-how-to-install-box86-box64-wine32-wine64-winetricks-on-arm64/
    # https://community.fydeos.io/t/topic/26128

    # Box64 Config, Refference: https://github.com/ptitSeb/box64/blob/main/docs/USAGE.md ,errors: https://github.com/ptitSeb/box64/issues/1182
    export BOX64_NOBANNER=1
    export BOX64_DYNAREC_BLEEDING_EDGE=0
    export BOX64_DYNAREC_BIGBLOCK=0
    export BOX64_DYNAREC_STRONGMEM=2
    export BOX64_LOG=1
    export BOX64_TRACE_FILE=$LOGS/$APP_NAME'_box64.log'
    #export BOX64_NOPULSE=1

    export APP_COMMAND="box64 wine64 $APP_FILES/$APP_EXE"
    
else
    export APP_COMMAND="wine64 $APP_FILES/$APP_EXE"
fi

# Main --------------------------------------------------------------------------------------
main() {
    tail_pids=()
    trap 'down SIGTERM' SIGTERM
    trap 'down SIGINT' SIGINT
    trap 'down EXIT' EXIT

    check_env
    wine_setup
    log_clean
    server_update
    check_whitelist
    mod_updates
    server_start
    log_tails

    # Infinite loop while APP_PID is running
    while kill -0 $APP_PID > /dev/null 2>&1; do
        current_minute=$(date '+%M' | sed 's/^0*//')
        
        if (( current_minute % 10 == 0 )); then
            log "$(uptime)"
        fi

        # TODO at current Hour 3AM, check for update

        # Sleep for 1 minute before checking again
        sleep 60
    done

    log "ERROR - $APP_EXE @PID $APP_PID appears to have died! $(uptime)"
    down "(main loop exit)"
}

check_env() {

    if [[ ${#SERVER_PLAYER_PASS} -lt 5 ]]; then
        log "WARNING - Password: '$SERVER_PLAYER_PASS' too short! Password should be at least 5 characters long."
    fi

    if [[ "$SERVER_NAME" == *"$SERVER_PLAYER_PASS"* ]]; then
        log "WARNING - Password '$SERVER_PLAYER_PASS' should not be part of the server name."
    fi
}

uptime() {

    local now=$(date -u +%s)    
    local uptime_seconds=$(( now - CONTAINER_START_TIME ))
    local days=$(( uptime_seconds / 86400 ))
    local hours=$(( (uptime_seconds % 86400) / 3600 ))
    local minutes=$(( (uptime_seconds % 3600) / 60 ))
    
    # Print uptime in a readable format
    echo "Container Uptime: ${days}d ${hours}h ${minutes}m"

}

down() {
    local signal_name=$1
    log "Received $signal_name. Initiating graceful shutdown..."

    # Stop tail processes immediately
    if [ ${#tail_pids[@]} -gt 0 ]; then
        log "Stopping tail processes..."
        kill -TERM "${tail_pids[@]}" 2>/dev/null
    fi

    # Stop main application process
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        log "Stopping application process (PID: $APP_PID)..."
        kill -TERM "$APP_PID" 2>/dev/null
        
        # Wait for the process to terminate, with a 9-second timeout
        # This leaves 1 second for final cleanup before Docker's 10-second limit
        local timeout=9
        for ((i=0; i<timeout; i++)); do
            if ! kill -0 "$APP_PID" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        
        # If process is still running after timeout, log a warning
        # Docker will send SIGKILL after its own timeout
        if kill -0 "$APP_PID" 2>/dev/null; then
            log "WARNING: Application did not stop within the timeout period. Docker may force termination."
        fi
    fi

    # Quick final wait, but don't exceed our adjusted timeout
    wait -n 1 2>/dev/null

    log "Cleanup complete. Exiting."
    exit 0
}

main
