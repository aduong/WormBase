#!/bin/bash

DIR="$(dirname "$0")"
LOGDIR="$DIR/logs"
PIDFILE="$DIR/wormbase.pid"

if [ -z "$PORT" ]; then
    PORT=8091
fi

if [ -z "$WORKERS" ]; then
    WORKERS=5
fi

if [ \( "$1" == "stop" \) -a ! -e "$PIDFILE" ]; then
    echo "Server does not appear to be running. Cannot stop server."
    exit 1
fi

if [ -e "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE")"
    if [ "$1" == "stop" ]; then
        echo "Stopping server with PID $PID"
        kill "$PID"
    else
        echo "Restarting server with PID $PID"
        kill -HUP "$PID"
    fi
else
    echo "Starting up server..."
    [ -e "$LOGDIR" ] || mkdir "$LOGDIR"
    starman --port "$PORT" --workers "$WORKERS" --daemonize --pid "$PIDFILE" \
        --access-log "$LOGDIR/access.log" --repload-app "$DIR/wormbase.psgi"
    echo "Started ($(cat "$PIDFILE"))."
fi
