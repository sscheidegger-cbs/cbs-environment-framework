#!/usr/bin/env bash

# CBS iOS simulator runtime manager (D05).
#
# Thin wrapper around "xcrun simctl" and "open -a DeviceHub" (Xcode 27+).
# It never creates and never deletes a simulator, never uses SSH, and never
# runs any iOS command on a host that is not macOS.
#
# Compatible with Bash 3.2 (macOS system Bash): no associative array, no
# mapfile, no case-conversion expansion.

set -Eeuo pipefail

action="${1:-}"
udid_arg="${2:-}"

USAGE="Usage: ios_simulator_manager.sh {list|ensure|start|status|stop} [UDID]"
UDID_PATTERN='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'

fail() {
    echo "CBS_IOS_RUNTIME_ERROR=$1" >&2
    exit 82
}

fail_usage() {
    echo "CBS_IOS_RUNTIME_ERROR=${1:-USAGE}" >&2
    echo "$USAGE" >&2
    exit 64
}

# --- argument validation (no iOS command is run here)

case "$action" in
    list)
        [[ $# -le 1 ]] ||
            fail_usage "USAGE"
        ;;
    ensure|start|status|stop)
        [[ $# -ge 2 ]] ||
            fail_usage "UDID_REQUIRED"
        [[ $# -eq 2 ]] ||
            fail_usage "USAGE"
        [[ "$udid_arg" =~ $UDID_PATTERN ]] ||
            fail_usage "UDID_INVALID"
        ;;
    *)
        fail_usage "USAGE"
        ;;
esac

UDID="$(printf '%s' "$udid_arg" | tr '[:lower:]' '[:upper:]')"

# Bounded wait for asynchronous simulator transitions (boot, shutdown): at
# most POLL_MAX_ATTEMPTS extra observations, POLL_INTERVAL_SECONDS apart.
# There is deliberately no unbounded loop.
POLL_MAX_ATTEMPTS=30
POLL_INTERVAL_SECONDS=1

# --- host and tool gates (before any xcrun / open call)

[[ "$(uname -s)" == "Darwin" ]] ||
    fail "HOST_NOT_MACOS"

command -v xcrun >/dev/null 2>&1 ||
    fail "XCRUN_MISSING"

# --- simctl observation (read-only)

OBSERVED_FOUND=0
OBSERVED_STATE=""

# Reads "xcrun simctl list devices" once and looks for $UDID. Sets
# OBSERVED_FOUND (0|1) and OBSERVED_STATE (SHUTDOWN, BOOTED, BOOTING,
# SHUTTING_DOWN, ... or UNAVAILABLE for a device simctl reports as
# unavailable). Never mutates anything.
observe_device() {
    local output line state
    local in_unavailable=0
    local state_pattern="\\(${UDID}\\) \\(([^)]+)\\)"

    OBSERVED_FOUND=0
    OBSERVED_STATE=""

    if ! output="$(xcrun simctl list devices 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail "SIMCTL_LIST_FAILED"
    fi

    output="$(printf '%s\n' "$output" | tr '[:lower:]' '[:upper:]')"

    while IFS= read -r line; do
        case "$line" in
            "-- UNAVAILABLE:"*)
                in_unavailable=1
                continue
                ;;
            "-- "*|"== "*)
                in_unavailable=0
                continue
                ;;
        esac

        if [[ "$line" =~ $state_pattern ]]; then
            state="${BASH_REMATCH[1]}"
            state="$(printf '%s' "$state" | tr ' ' '_')"

            if [[ "$in_unavailable" -eq 1 || "$line" == *"(UNAVAILABLE"* ]]; then
                state="UNAVAILABLE"
            fi

            OBSERVED_FOUND=1
            OBSERVED_STATE="$state"
            return 0
        fi
    done <<EOF
$output
EOF

    return 0
}

require_device() {
    observe_device

    [[ "$OBSERVED_FOUND" -eq 1 ]] ||
        fail "DEVICE_MISSING"

    [[ "$OBSERVED_STATE" != "UNAVAILABLE" ]] ||
        fail "DEVICE_UNAVAILABLE"
}

# wait_for_state <STATE>: observes the device, then re-observes up to
# POLL_MAX_ATTEMPTS times (sleeping POLL_INTERVAL_SECONDS before each
# re-observation) until OBSERVED_STATE equals <STATE>. Returns 0 when the state
# is reached, 1 when the bound is exhausted. Never mutates anything. A
# "simctl list" failure is still reported by observe_device as
# SIMCTL_LIST_FAILED.
wait_for_state() {
    local target="$1"
    local attempt=0

    observe_device

    while [[ "$OBSERVED_STATE" != "$target" ]]; do
        [[ "$attempt" -lt "$POLL_MAX_ATTEMPTS" ]] ||
            return 1

        attempt=$((attempt + 1))
        sleep "$POLL_INTERVAL_SECONDS"
        observe_device
    done

    return 0
}

print_device() {
    echo "CBS_IOS_RUNTIME_DEVICE=$UDID"
}

case "$action" in
    list)
        if ! devices="$(xcrun simctl list devices)"; then
            fail "SIMCTL_LIST_FAILED"
        fi

        printf '%s\n' "$devices"
        echo "CBS_IOS_RUNTIME_LIST_RESULT=PASS"
        ;;

    ensure)
        require_device

        print_device
        echo "CBS_IOS_RUNTIME_STATE=$OBSERVED_STATE"
        echo "CBS_IOS_RUNTIME_ACTION=REUSE"
        echo "CBS_IOS_RUNTIME_ENSURE_RESULT=PASS"
        ;;

    status)
        observe_device

        [[ "$OBSERVED_FOUND" -eq 1 ]] ||
            fail "DEVICE_MISSING"

        print_device
        echo "CBS_IOS_RUNTIME_STATE=$OBSERVED_STATE"
        echo "CBS_IOS_RUNTIME_STATUS_RESULT=PASS"
        ;;

    start)
        require_device

        command -v open >/dev/null 2>&1 ||
            fail "OPEN_MISSING"

        case "$OBSERVED_STATE" in
            BOOTED)
                boot_action="NOOP"
                ;;
            SHUTDOWN)
                if ! xcrun simctl boot "$UDID"; then
                    fail "SIMCTL_BOOT_FAILED"
                fi

                # Blocks until the boot is complete; the real state is then
                # confirmed (bounded wait absorbs a lagging "simctl list").
                if ! xcrun simctl bootstatus "$UDID" -b; then
                    fail "SIMCTL_BOOTSTATUS_FAILED"
                fi

                wait_for_state "BOOTED" ||
                    fail "BOOT_NOT_CONFIRMED"

                boot_action="BOOT"
                ;;
            BOOTING|SHUTTING_DOWN|CREATING)
                fail "DEVICE_STATE_TRANSITIONING"
                ;;
            *)
                fail "DEVICE_STATE_UNSUPPORTED"
                ;;
        esac

        if ! open -a DeviceHub; then
            fail "DEVICEHUB_UNAVAILABLE"
        fi

        print_device
        echo "CBS_IOS_RUNTIME_STATE=BOOTED"
        echo "CBS_IOS_RUNTIME_ACTION=$boot_action"
        echo "CBS_IOS_RUNTIME_DEVICEHUB=OPENED"
        echo "CBS_IOS_RUNTIME_START_RESULT=PASS"
        ;;

    stop)
        require_device

        case "$OBSERVED_STATE" in
            SHUTDOWN)
                stop_action="NOOP"
                ;;
            BOOTED)
                if ! xcrun simctl shutdown "$UDID"; then
                    fail "SIMCTL_SHUTDOWN_FAILED"
                fi

                # Shutdown is asynchronous: bounded wait for the real state.
                wait_for_state "SHUTDOWN" ||
                    fail "SHUTDOWN_NOT_CONFIRMED"

                stop_action="SHUTDOWN"
                ;;
            BOOTING|SHUTTING_DOWN|CREATING)
                fail "DEVICE_STATE_TRANSITIONING"
                ;;
            *)
                fail "DEVICE_STATE_UNSUPPORTED"
                ;;
        esac

        print_device
        echo "CBS_IOS_RUNTIME_STATE=SHUTDOWN"
        echo "CBS_IOS_RUNTIME_ACTION=$stop_action"
        echo "CBS_IOS_RUNTIME_STOP_RESULT=PASS"
        ;;
esac
