#!/usr/bin/env bash

if [[ "${CBS_PLATFORM_CONTRACT_LOADED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

CBS_PLATFORM_CONTRACT_LOADED=1
readonly CBS_PLATFORM_CONTRACT_LOADED

CBS_PLATFORM_CONTRACT_VERSION=1
readonly CBS_PLATFORM_CONTRACT_VERSION

readonly CBS_PLATFORM_STATE_READY="READY"
readonly CBS_PLATFORM_STATE_INCOMPLETE="INCOMPLETE"
readonly CBS_PLATFORM_STATE_INVALID="INVALID"
readonly CBS_PLATFORM_STATE_UNKNOWN="UNKNOWN"

readonly CBS_PLATFORM_HOOK_PRESENT="PRESENT"
readonly CBS_PLATFORM_HOOK_MISSING="MISSING"
readonly CBS_PLATFORM_HOOK_NOT_EXECUTABLE="NOT_EXECUTABLE"
readonly CBS_PLATFORM_HOOK_UNKNOWN="UNKNOWN"

readonly CBS_PLATFORM_ACTION_START="start"
readonly CBS_PLATFORM_ACTION_CHECK="check"
readonly CBS_PLATFORM_ACTION_STATUS="status"
readonly CBS_PLATFORM_ACTION_STOP="stop"
readonly CBS_PLATFORM_ACTION_QUALIFY="qualify"

readonly CBS_RC_PLATFORM_HOOK_MISSING=90
readonly CBS_RC_PLATFORM_HOOK_NOT_EXECUTABLE=91
readonly CBS_RC_PLATFORM_INVALID=92
readonly CBS_RC_PLATFORM_UNKNOWN=93
readonly CBS_RC_PLATFORM_EXECUTION_FAILED=94
readonly CBS_RC_PLATFORM_USAGE=64

cbs_platform_state_is_valid() {
    case "${1:-}" in
        "$CBS_PLATFORM_STATE_READY"|\
        "$CBS_PLATFORM_STATE_INCOMPLETE"|\
        "$CBS_PLATFORM_STATE_INVALID"|\
        "$CBS_PLATFORM_STATE_UNKNOWN")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_platform_hook_state_is_valid() {
    case "${1:-}" in
        "$CBS_PLATFORM_HOOK_PRESENT"|\
        "$CBS_PLATFORM_HOOK_MISSING"|\
        "$CBS_PLATFORM_HOOK_NOT_EXECUTABLE"|\
        "$CBS_PLATFORM_HOOK_UNKNOWN")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_platform_action_is_valid() {
    case "${1:-}" in
        "$CBS_PLATFORM_ACTION_START"|\
        "$CBS_PLATFORM_ACTION_CHECK"|\
        "$CBS_PLATFORM_ACTION_STATUS"|\
        "$CBS_PLATFORM_ACTION_STOP"|\
        "$CBS_PLATFORM_ACTION_QUALIFY")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_platform_state_from_hook_failures() {
    local missing="${1:-}"
    local not_executable="${2:-}"

    [[ "$missing" =~ ^[0-9]+$ ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    [[ "$not_executable" =~ ^[0-9]+$ ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    if [[ "$missing" -gt 0 || "$not_executable" -gt 0 ]]; then
        printf '%s\n' "$CBS_PLATFORM_STATE_INCOMPLETE"
    else
        printf '%s\n' "$CBS_PLATFORM_STATE_READY"
    fi
}
