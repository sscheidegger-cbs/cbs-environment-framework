#!/usr/bin/env bash

if [[ "${CBS_INSTANCE_CONTRACT_LOADED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

CBS_INSTANCE_CONTRACT_LOADED=1
readonly CBS_INSTANCE_CONTRACT_LOADED

CBS_INSTANCE_CONTRACT_VERSION=1
readonly CBS_INSTANCE_CONTRACT_VERSION

readonly CBS_INSTANCE_STATE_READY="READY"
readonly CBS_INSTANCE_STATE_STOPPED="STOPPED"
readonly CBS_INSTANCE_STATE_PARTIAL="PARTIAL"
readonly CBS_INSTANCE_STATE_CONFLICT="CONFLICT"
readonly CBS_INSTANCE_STATE_INVALID="INVALID"
readonly CBS_INSTANCE_STATE_UNKNOWN="UNKNOWN"

readonly CBS_INSTANCE_RESOURCE_CONTAINER="CONTAINER"
readonly CBS_INSTANCE_RESOURCE_NETWORK="NETWORK"
readonly CBS_INSTANCE_RESOURCE_VOLUME="VOLUME"
readonly CBS_INSTANCE_RESOURCE_PORT="PORT"

readonly CBS_INSTANCE_RESOURCE_AVAILABLE="AVAILABLE"
readonly CBS_INSTANCE_RESOURCE_EXPECTED="EXPECTED"
readonly CBS_INSTANCE_RESOURCE_CONFLICT="CONFLICT"
readonly CBS_INSTANCE_RESOURCE_UNKNOWN="UNKNOWN"

readonly CBS_INSTANCE_ACTION_REUSE="REUSE"
readonly CBS_INSTANCE_ACTION_CREATE="CREATE"
readonly CBS_INSTANCE_ACTION_BLOCK="BLOCK"
readonly CBS_INSTANCE_ACTION_OBSERVE="OBSERVE"

readonly CBS_RC_INSTANCE_CONFLICT=80
readonly CBS_RC_INSTANCE_INVALID=81
readonly CBS_RC_INSTANCE_UNKNOWN=82
readonly CBS_RC_INSTANCE_USAGE=64

cbs_instance_state_is_valid() {
    case "${1:-}" in
        "$CBS_INSTANCE_STATE_READY"|\
        "$CBS_INSTANCE_STATE_STOPPED"|\
        "$CBS_INSTANCE_STATE_PARTIAL"|\
        "$CBS_INSTANCE_STATE_CONFLICT"|\
        "$CBS_INSTANCE_STATE_INVALID"|\
        "$CBS_INSTANCE_STATE_UNKNOWN")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_instance_resource_type_is_valid() {
    case "${1:-}" in
        "$CBS_INSTANCE_RESOURCE_CONTAINER"|\
        "$CBS_INSTANCE_RESOURCE_NETWORK"|\
        "$CBS_INSTANCE_RESOURCE_VOLUME"|\
        "$CBS_INSTANCE_RESOURCE_PORT")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_instance_resource_state_is_valid() {
    case "${1:-}" in
        "$CBS_INSTANCE_RESOURCE_AVAILABLE"|\
        "$CBS_INSTANCE_RESOURCE_EXPECTED"|\
        "$CBS_INSTANCE_RESOURCE_CONFLICT"|\
        "$CBS_INSTANCE_RESOURCE_UNKNOWN")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_instance_action_is_valid() {
    case "${1:-}" in
        "$CBS_INSTANCE_ACTION_REUSE"|\
        "$CBS_INSTANCE_ACTION_CREATE"|\
        "$CBS_INSTANCE_ACTION_BLOCK"|\
        "$CBS_INSTANCE_ACTION_OBSERVE")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_instance_action_from_state() {
    case "${1:-}" in
        "$CBS_INSTANCE_STATE_READY"|"$CBS_INSTANCE_STATE_STOPPED")
            printf '%s\n' "$CBS_INSTANCE_ACTION_REUSE"
            ;;
        "$CBS_INSTANCE_STATE_CONFLICT"|"$CBS_INSTANCE_STATE_INVALID")
            printf '%s\n' "$CBS_INSTANCE_ACTION_BLOCK"
            ;;
        "$CBS_INSTANCE_STATE_PARTIAL"|"$CBS_INSTANCE_STATE_UNKNOWN")
            printf '%s\n' "$CBS_INSTANCE_ACTION_OBSERVE"
            ;;
        "")
            return "$CBS_RC_INSTANCE_USAGE"
            ;;
        *)
            return "$CBS_RC_INSTANCE_INVALID"
            ;;
    esac
}
