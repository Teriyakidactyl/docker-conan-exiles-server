#!/bin/bash

log "Creating $APP_NAME xvfb-run APP_COMMAND"

export APP_COMMAND="\
xvfb-run \
--auto-servernum \
--server-args='-screen 0 640x480x24:32 -nolisten tcp' $APP_COMMAND_PREFIX $APP_FILES/$APP_EXE $APP_ARGS \
-nosteamclient \
-game \
-server \
-log"