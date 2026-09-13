#!/usr/bin/env bash

if [[ "${CBS_STACK_CONTRACT_LOADED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

CBS_STACK_CONTRACT_LOADED=1
readonly CBS_STACK_CONTRACT_LOADED

CBS_STACK_CONTRACT_VERSION=1
readonly CBS_STACK_CONTRACT_VERSION

readonly CBS_STACK_STATE_READY="READY"
readonly CBS_STACK_STATE_INCOMPLETE="INCOMPLETE"
readonly CBS_STACK_STATE_INVALID="INVALID"
readonly CBS_STACK_STATE_UNKNOWN="UNKNOWN"

readonly CBS_STACK_PREREQUISITE_PRESENT="PRESENT"
readonly CBS_STACK_PREREQUISITE_MISSING="MISSING"
readonly CBS_STACK_PREREQUISITE_UNKNOWN="UNKNOWN"

readonly CBS_STACK_COMPONENT_REQUIRED="REQUIRED"
readonly CBS_STACK_COMPONENT_OPTIONAL="OPTIONAL"
readonly CBS_STACK_COMPONENT_DISABLED="DISABLED"

readonly CBS_STACK_CAPABILITY_START="start"
readonly CBS_STACK_CAPABILITY_CHECK="check"
readonly CBS_STACK_CAPABILITY_STATUS="status"
readonly CBS_STACK_CAPABILITY_QUALIFY="qualify"

readonly CBS_RC_STACK_PREREQUISITE_MISSING=70
readonly CBS_RC_STACK_INVALID=71
readonly CBS_RC_STACK_UNKNOWN=72
readonly CBS_RC_STACK_USAGE=64

cbs_stack_state_is_valid() {
    case "${1:-}" in
        "$CBS_STACK_STATE_READY"|"$CBS_STACK_STATE_INCOMPLETE"|"$CBS_STACK_STATE_INVALID"|"$CBS_STACK_STATE_UNKNOWN")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_stack_prerequisite_state_is_valid() {
    case "${1:-}" in
        "$CBS_STACK_PREREQUISITE_PRESENT"|"$CBS_STACK_PREREQUISITE_MISSING"|"$CBS_STACK_PREREQUISITE_UNKNOWN")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_stack_component_requirement_is_valid() {
    case "${1:-}" in
        "$CBS_STACK_COMPONENT_REQUIRED"|"$CBS_STACK_COMPONENT_OPTIONAL"|"$CBS_STACK_COMPONENT_DISABLED")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_stack_capability_is_valid() {
    case "${1:-}" in
        "$CBS_STACK_CAPABILITY_START"|"$CBS_STACK_CAPABILITY_CHECK"|"$CBS_STACK_CAPABILITY_STATUS"|"$CBS_STACK_CAPABILITY_QUALIFY")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_stack_state_from_missing_required_count() {
    local missing="${1:-}"

    [[ "$missing" =~ ^[0-9]+$ ]] ||
        return "$CBS_RC_STACK_INVALID"

    if [[ "$missing" -eq 0 ]]; then
        printf '%s\n' "$CBS_STACK_STATE_READY"
    else
        printf '%s\n' "$CBS_STACK_STATE_INCOMPLETE"
    fi
}
