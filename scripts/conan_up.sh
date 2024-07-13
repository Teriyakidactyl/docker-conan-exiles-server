#!/bin/bash
source $SCRIPTS/conan_logging_functions
source $SCRIPTS/conan_server_functions

export APP_LOGS="$LOGS/$APP_NAME"
export ARCH=$(dpkg --print-architecture)
export CONTAINER_START_TIME=$(date -u +%s)

# TODO log rotate

main() {
    tail_pids=()
    trap 'down SIGTERM' SIGTERM
    trap 'down SIGINT' SIGINT
    trap 'down EXIT' EXIT

    check_env
    log_clean
    links
    server_update
    server_start
    log_tails

    # Infinite loop while APP_PID is running
    # FIXME this loop is likely breaking due to xfvb > wine > conan redirects
    # while kill -0 $APP_PID > /dev/null 2>&1; do
    while true; do
        current_minute=$(date '+%M' | sed 's/^0*//')
        
        if (( current_minute % 10 == 0 )); then
            log "$(uptime)"
        fi

        # Sleep for 1 minute before checking again
        sleep 60
    done

    log "ERROR - $APP_EXE @PID $APP_PID appears to have died! $(uptime)"
    down "(main loop exit)"
}

links (){

    # Create symbolic links based on the SERVER_NAME environment variable

    WORLD_DIRECTORIES=" \
        $WORLD_FILES/$SERVER_NAME/Saved/Logs \
        $WORLD_FILES/$SERVER_NAME/Config \
        $WORLD_FILES/$SERVER_NAME/Mods \
        $WORLD_FILES/$SERVER_NAME/Engine/Config \
        $APP_FILES/Engine \
        $APP_FILES/ConanSandbox" \

    mkdir -p $WORLD_DIRECTORIES

    # Link 'WORLD_FILES' folders from 'APP_FILES'
    # ln [LINK] [DATA]

    ln -sf "$WORLD_FILES/$SERVER_NAME/Engine/Config" "$APP_FILES/Engine"
    ln -sf "$WORLD_FILES/$SERVER_NAME/Saved" "$APP_FILES/ConanSandbox"
    ln -sf "$WORLD_FILES/$SERVER_NAME/Config" "$APP_FILES/ConanSandbox"
    ln -sf "$WORLD_FILES/$SERVER_NAME/Mods" "$APP_FILES/ConanSandbox"

    # TODO throw error if /ConanSandbox/Saved exists


    # Link LOGS TO WORLD_FILES
    touch $WORLD_FILES/$SERVER_NAME/Saved/Logs/ConanSandbox.log
    ln -sf "$APP_FILES/ConanSandbox/Saved/Logs/ConanSandbox.log" "$APP_LOGS/ConanSandbox.log"


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
