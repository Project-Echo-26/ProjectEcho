#!/usr/bin/env bash

set -u

if [[ "$#" -ne 8 ]]; then
    printf 'Usage: %s LAUNCHER_PID PID_FILE PYTHON MAVPROXY_SCRIPT TCP_PORT ROUTER_PORT GCS_MODE GCS_HOST\n' \
        "$0" >&2
    exit 2
fi

LAUNCHER_PID=$1
LAUNCHER_PID_FILE=$2
PYTHON_BIN=$3
MAVPROXY_SCRIPT=$4
TCP_PORT=$5
ROUTER_PORT=$6
GCS_MODE=$7
GCS_HOST=$8

launcher_is_running() {
    [[ -r "$LAUNCHER_PID_FILE" ]] \
        && [[ "$(<"$LAUNCHER_PID_FILE")" == "$LAUNCHER_PID" ]] \
        && kill -0 "$LAUNCHER_PID" 2>/dev/null
}

if ! launcher_is_running; then
    printf 'The three-drone launcher is no longer running.\n' >&2
    exit 1
fi

MAVPROXY_ARGS=(
    "--master=tcp:127.0.0.1:$TCP_PORT"
    "--out=127.0.0.1:$ROUTER_PORT"
)

if [[ "$GCS_MODE" == "direct" && -n "$GCS_HOST" ]]; then
    MAVPROXY_ARGS+=("--out=$GCS_HOST:14550")
elif [[ "$GCS_MODE" != "direct" && "$GCS_MODE" != "mesh-fed" ]]; then
    printf 'Unsupported Mission Planner mode: %s\n' "$GCS_MODE" >&2
    exit 2
fi

"$PYTHON_BIN" "$MAVPROXY_SCRIPT" "${MAVPROXY_ARGS[@]}" </dev/tty &
MAVPROXY_PID=$!

cleanup() {
    local attempt
    trap - EXIT INT TERM HUP

    if kill -0 "$MAVPROXY_PID" 2>/dev/null; then
        kill -TERM "$MAVPROXY_PID" 2>/dev/null
        for ((attempt = 0; attempt < 3; attempt++)); do
            kill -0 "$MAVPROXY_PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$MAVPROXY_PID" 2>/dev/null; then
            kill -KILL "$MAVPROXY_PID" 2>/dev/null
        fi
    fi

    wait "$MAVPROXY_PID" 2>/dev/null || true
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

while launcher_is_running; do
    if ! kill -0 "$MAVPROXY_PID" 2>/dev/null; then
        wait "$MAVPROXY_PID"
        exit $?
    fi
    sleep 1
done
