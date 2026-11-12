#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
GAZEBO_ROOT="$PROJECT_ROOT/ardupilot_gazebo"
WORLD="$GAZEBO_ROOT/worlds/iris_three_basic.sdf"
SIM_VEHICLE="$PROJECT_ROOT/Tools/autotest/sim_vehicle.py"
MESH_ROUTER="$SCRIPT_DIR/mesh_router.py"
RECEIVER="$SCRIPT_DIR/receiver.py"
MAVPROXY_PANE="$SCRIPT_DIR/mavproxy_pane.sh"
DASHBOARD_SCRIPT="$SCRIPT_DIR/open_three_drone_dashboard.ps1"

STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/projectecho/three-drone-mesh"
SITL_STATE_DIR="$STATE_ROOT/sitl"
SITL_LOG_DIR="$STATE_ROOT/sitl-logs"
LAUNCHER_PID_FILE="$STATE_ROOT/launcher.pid"
WINDOWS_POWERSHELL="${WINDOWS_POWERSHELL:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}"
WINDOWS_TERMINAL_DISTRO="${WINDOWS_TERMINAL_DISTRO:-${WSL_DISTRO_NAME:-Ubuntu-24.04}}"

ROUTER_PORT_1=14610
ROUTER_PORT_2=14611
ROUTER_PORT_3=14612
RECEIVER_PORT_1=14620
RECEIVER_PORT_2=14621
RECEIVER_PORT_3=14622

MESH_RANGE_M="${MESH_RANGE_M:-100}"
MESH_BANDWIDTH="${MESH_BANDWIDTH:-57600}"
MESH_LATENCY_MS="${MESH_LATENCY_MS:-20}"
MESH_PACKET_LOSS="${MESH_PACKET_LOSS:-0.01}"
MESH_MAX_HOPS="${MESH_MAX_HOPS:-4}"
MESH_GCS_MODE="${MESH_GCS_MODE:-direct}"
GCS_PORT=14550

if [[ "$MESH_GCS_MODE" != "direct" && "$MESH_GCS_MODE" != "mesh-fed" ]]; then
    printf 'MESH_GCS_MODE must be direct or mesh-fed.\n' >&2
    exit 2
fi

if [[ -z "${PYTHON_BIN:-}" ]]; then
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN=python3
    fi
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

for command_name in gz ss setsid ps awk grep tail wslpath; do
    require_command "$command_name"
done
require_command "$PYTHON_BIN"
if [[ ! -x "$WINDOWS_POWERSHELL" ]]; then
    printf 'Windows PowerShell was not found at %s.\n' "$WINDOWS_POWERSHELL" >&2
    printf 'Set WINDOWS_POWERSHELL to its WSL-accessible path.\n' >&2
    exit 1
fi

if [[ -x "$PROJECT_ROOT/.venv/bin/mavproxy.py" ]]; then
    MAVPROXY_SCRIPT="$PROJECT_ROOT/.venv/bin/mavproxy.py"
else
    require_command mavproxy.py
    MAVPROXY_SCRIPT="$(command -v mavproxy.py)"
fi

SITL_BINARY="$PROJECT_ROOT/build/sitl/bin/arducopter"
GAZEBO_PLUGIN="$GAZEBO_ROOT/build/libArduPilotPlugin.so"

if [[ ! -f "$WORLD" \
    || ! -f "$GAZEBO_ROOT/models/iris_with_ardupilot/model.sdf" \
    || ! -f "$GAZEBO_ROOT/models/iris_with_ardupilot_2/model.sdf" \
    || ! -f "$GAZEBO_ROOT/models/iris_with_ardupilot_3/model.sdf" ]]; then
    printf 'Three-drone Gazebo world or model files are missing.\n' >&2
    exit 1
fi
if [[ ! -x "$SITL_BINARY" ]]; then
    printf 'SITL binary is missing. Build it first with:\n' >&2
    printf '  ./waf configure --board sitl && ./waf copter\n' >&2
    exit 1
fi
if [[ ! -f "$GAZEBO_PLUGIN" ]]; then
    printf 'Gazebo plugin is missing: %s\n' "$GAZEBO_PLUGIN" >&2
    printf 'Build ardupilot_gazebo as described in README.md.\n' >&2
    exit 1
fi
if [[ ! -f "$MAVPROXY_PANE" || ! -f "$DASHBOARD_SCRIPT" ]]; then
    printf 'Windows Terminal dashboard scripts are missing.\n' >&2
    exit 1
fi
"$PYTHON_BIN" -c 'import pymavlink' || {
    printf 'pymavlink is not available to %s.\n' "$PYTHON_BIN" >&2
    exit 1
}
"$PYTHON_BIN" "$MAVPROXY_SCRIPT" --version >/dev/null

WINDOWS_HOST_IP="${WINDOWS_HOST_IP:-}"
if [[ -z "$WINDOWS_HOST_IP" ]] && command -v ip >/dev/null 2>&1; then
    WINDOWS_HOST_IP="$(ip route show default 2>/dev/null | awk 'NR == 1 {print $3}')"
fi

WINDOWS_DASHBOARD_SCRIPT="$(wslpath -w "$DASHBOARD_SCRIPT")"
declare -a WINDOWS_DASHBOARD_ARGUMENTS=(
    -Distro "$WINDOWS_TERMINAL_DISTRO"
    -ProjectRoot "$PROJECT_ROOT"
    -StateRoot "$STATE_ROOT"
    -LauncherPid "$$"
    -LauncherPidFile "$LAUNCHER_PID_FILE"
    -PythonBin "$PYTHON_BIN"
    -MavproxyScript "$MAVPROXY_SCRIPT"
    -MavproxyPaneScript "$MAVPROXY_PANE"
    -GcsMode "$MESH_GCS_MODE"
)
if [[ -n "$WINDOWS_HOST_IP" ]]; then
    WINDOWS_DASHBOARD_ARGUMENTS+=(-WindowsHostIP "$WINDOWS_HOST_IP")
fi

if ! "$WINDOWS_POWERSHELL" -NoLogo -NoProfile -ExecutionPolicy Bypass \
    -File "$WINDOWS_DASHBOARD_SCRIPT" "${WINDOWS_DASHBOARD_ARGUMENTS[@]}" -DryRun >/dev/null; then
    printf 'Windows Terminal dashboard preflight failed.\n' >&2
    exit 1
fi

declare -a ROUTER_GCS_OUTPUT=()
if [[ "$MESH_GCS_MODE" == "mesh-fed" ]]; then
    if [[ -z "$WINDOWS_HOST_IP" ]]; then
        printf 'Set WINDOWS_HOST_IP for mesh-fed Mission Planner telemetry.\n' >&2
        exit 1
    fi
    ROUTER_GCS_OUTPUT+=(--gcs-output "$WINDOWS_HOST_IP:$GCS_PORT")
    printf 'Mesh-fed Mission Planner telemetry will use %s:%s (read-only).\n' \
        "$WINDOWS_HOST_IP" "$GCS_PORT"
elif [[ -n "$WINDOWS_HOST_IP" ]]; then
    printf 'Direct Mission Planner telemetry will use %s:%s.\n' "$WINDOWS_HOST_IP" "$GCS_PORT"
else
    printf 'No Windows host IP detected; set WINDOWS_HOST_IP to enable Mission Planner output.\n'
fi

export GZ_SIM_SYSTEM_PLUGIN_PATH="$GAZEBO_ROOT/build${GZ_SIM_SYSTEM_PLUGIN_PATH:+:$GZ_SIM_SYSTEM_PLUGIN_PATH}"
export GZ_SIM_RESOURCE_PATH="$GAZEBO_ROOT/models:$GAZEBO_ROOT/worlds${GZ_SIM_RESOURCE_PATH:+:$GZ_SIM_RESOURCE_PATH}"

udp_port_listening() {
    ss -H -lun | grep -Eq "[.:]$1[[:space:]]"
}

tcp_port_listening() {
    ss -H -ltn | grep -Eq "[.:]$1[[:space:]]"
}

check_port_available() {
    local port=$1
    if udp_port_listening "$port" || tcp_port_listening "$port"; then
        printf 'Port %s is already in use; stop the other simulation first.\n' "$port" >&2
        exit 1
    fi
}

for port in 9002 9012 9022 "$ROUTER_PORT_1" "$ROUTER_PORT_2" "$ROUTER_PORT_3" \
    "$RECEIVER_PORT_1" "$RECEIVER_PORT_2" "$RECEIVER_PORT_3" 5760 5770 5780; do
    check_port_available "$port"
done

mkdir -p "$SITL_STATE_DIR" "$SITL_LOG_DIR"

declare -a PROCESS_PIDS=()
declare -a PROCESS_NAMES=()

start_process() {
    local name=$1
    shift

    setsid "$@" >"$STATE_ROOT/$name.log" 2>&1 </dev/null &
    local pid=$!
    PROCESS_PIDS+=("$pid")
    PROCESS_NAMES+=("$name")
    sleep 0.2
    if ! kill -0 "$pid" 2>/dev/null; then
        printf 'Failed to start %s; see %s\n' "$name" "$STATE_ROOT/$name.log" >&2
        tail -n 40 "$STATE_ROOT/$name.log" >&2 || true
        return 1
    fi
    printf 'Started %-18s PID %s (log: %s)\n' "$name" "$pid" "$STATE_ROOT/$name.log"
}

process_group_alive() {
    kill -0 -- "-$1" 2>/dev/null
}

stop_processes() {
    local index pid attempt alive
    set +e

    printf '\nStopping simulation processes...\n'
    for ((index = ${#PROCESS_PIDS[@]} - 1; index >= 0; index--)); do
        pid=${PROCESS_PIDS[index]}
        if process_group_alive "$pid"; then
            kill -INT -- "-$pid" 2>/dev/null
        fi
    done

    for ((attempt = 0; attempt < 10; attempt++)); do
        alive=0
        for pid in "${PROCESS_PIDS[@]}"; do
            if process_group_alive "$pid"; then
                alive=1
                break
            fi
        done
        if [[ "$alive" -eq 0 ]]; then
            break
        fi
        sleep 1
    done

    for ((index = ${#PROCESS_PIDS[@]} - 1; index >= 0; index--)); do
        pid=${PROCESS_PIDS[index]}
        if process_group_alive "$pid"; then
            printf 'Sending TERM to %s process group %s\n' "${PROCESS_NAMES[index]}" "$pid"
            kill -TERM -- "-$pid" 2>/dev/null
        fi
    done
    sleep 2

    for ((index = ${#PROCESS_PIDS[@]} - 1; index >= 0; index--)); do
        pid=${PROCESS_PIDS[index]}
        if process_group_alive "$pid"; then
            printf 'Force-stopping %s process group %s\n' "${PROCESS_NAMES[index]}" "$pid"
            kill -KILL -- "-$pid" 2>/dev/null
        fi
    done
}

wait_for_ports() {
    local kind=$1
    local timeout=$2
    shift 2
    local port elapsed

    for ((elapsed = 0; elapsed < timeout; elapsed++)); do
        local all_ready=1
        for port in "$@"; do
            if [[ "$kind" == "udp" ]]; then
                udp_port_listening "$port" || all_ready=0
            else
                tcp_port_listening "$port" || all_ready=0
            fi
        done
        if [[ "$all_ready" -eq 1 ]]; then
            return 0
        fi
        sleep 1
    done

    printf 'Timed out waiting for %s ports: %s\n' "$kind" "$*" >&2
    return 1
}

on_exit() {
    local status=$?
    trap - EXIT INT TERM HUP
    stop_processes
    if [[ -f "$LAUNCHER_PID_FILE" ]] \
        && [[ "$(<"$LAUNCHER_PID_FILE")" == "$$" ]]; then
        rm -f -- "$LAUNCHER_PID_FILE"
    fi
    return "$status"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

printf '%s\n' "$$" >"$LAUNCHER_PID_FILE"

cd "$PROJECT_ROOT"
start_process gazebo gz sim -v4 -r "$WORLD"
wait_for_ports udp 45 9002 9012 9022 || {
    printf 'Gazebo did not bind both ArduPilot ports; see %s/gazebo.log\n' "$STATE_ROOT" >&2
    exit 1
}

start_process mesh-router "$PYTHON_BIN" "$MESH_ROUTER" \
    --node "1:$ROUTER_PORT_1:$RECEIVER_PORT_1" \
    --node "2:$ROUTER_PORT_2:$RECEIVER_PORT_2" \
    --node "3:$ROUTER_PORT_3:$RECEIVER_PORT_3" \
    "${ROUTER_GCS_OUTPUT[@]}" \
    --range-m "$MESH_RANGE_M" \
    --bandwidth "$MESH_BANDWIDTH" \
    --latency-ms "$MESH_LATENCY_MS" \
    --packet-loss "$MESH_PACKET_LOSS" \
    --max-hops "$MESH_MAX_HOPS"
start_process receiver-drone-1 "$PYTHON_BIN" "$RECEIVER" --port "$RECEIVER_PORT_1"
start_process receiver-drone-2 "$PYTHON_BIN" "$RECEIVER" --port "$RECEIVER_PORT_2"
start_process receiver-drone-3 "$PYTHON_BIN" "$RECEIVER" --port "$RECEIVER_PORT_3"

start_process sitl-manager env DISPLAY= TMPDIR="$SITL_LOG_DIR" \
    "$PYTHON_BIN" "$SIM_VEHICLE" \
    -v ArduCopter -f gazebo-iris --model JSON \
    -I0 -n3 --auto-sysid \
    --use-dir "$SITL_STATE_DIR" \
    --no-rebuild --no-mavproxy
wait_for_ports tcp 60 5760 5770 5780 || {
    printf 'SITL instances did not open their MAVLink ports; see %s/sitl-manager.log\n' "$STATE_ROOT" >&2
    exit 1
}

"$WINDOWS_POWERSHELL" -NoLogo -NoProfile -ExecutionPolicy Bypass \
    -File "$WINDOWS_DASHBOARD_SCRIPT" "${WINDOWS_DASHBOARD_ARGUMENTS[@]}"

printf '\nThree-drone mesh simulation is running in the six-pane Windows Terminal dashboard.\n'
printf 'Peer telemetry logs: %s/receiver-drone-*.log\n' "$STATE_ROOT"
printf 'All logs: %s\n' "$STATE_ROOT"
printf 'Connect Mission Planner using UDP port %s. Keep this launcher terminal open; press Ctrl+C here to stop the stack.\n' \
    "$GCS_PORT"

while true; do
    for index in "${!PROCESS_PIDS[@]}"; do
        if ! kill -0 "${PROCESS_PIDS[index]}" 2>/dev/null; then
            printf '%s exited unexpectedly; check %s/%s.log\n' \
                "${PROCESS_NAMES[index]}" "$STATE_ROOT" "${PROCESS_NAMES[index]}" >&2
            exit 1
        fi
    done
    sleep 2
done
