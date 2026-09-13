#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/instance/contract.sh"

cbs_instance_container_state() {
    local name="${1:-}"

    [[ -n "$name" ]] ||
        return "$CBS_RC_INSTANCE_USAGE"

    if docker container inspect "$name" >/dev/null 2>&1; then
        printf '%s\n' "$CBS_INSTANCE_RESOURCE_EXPECTED"
    else
        printf '%s\n' "$CBS_INSTANCE_RESOURCE_AVAILABLE"
    fi
}

cbs_instance_network_state() {
    local name="${1:-}"

    [[ -n "$name" ]] ||
        return "$CBS_RC_INSTANCE_USAGE"

    if docker network inspect "$name" >/dev/null 2>&1; then
        printf '%s\n' "$CBS_INSTANCE_RESOURCE_EXPECTED"
    else
        printf '%s\n' "$CBS_INSTANCE_RESOURCE_AVAILABLE"
    fi
}

cbs_instance_volume_state() {
    local name="${1:-}"

    [[ -n "$name" ]] ||
        return "$CBS_RC_INSTANCE_USAGE"

    if docker volume inspect "$name" >/dev/null 2>&1; then
        printf '%s\n' "$CBS_INSTANCE_RESOURCE_EXPECTED"
    else
        printf '%s\n' "$CBS_INSTANCE_RESOURCE_AVAILABLE"
    fi
}

cbs_instance_count_state() {
    local state="${1:-}"

    case "$state" in
        EXPECTED)
            CBS_INSTANCE_EXPECTED_RESOURCE_COUNT=$((CBS_INSTANCE_EXPECTED_RESOURCE_COUNT + 1))
            ;;
        AVAILABLE)
            CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT=$((CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT + 1))
            ;;
        CONFLICT)
            CBS_INSTANCE_CONFLICT_RESOURCE_COUNT=$((CBS_INSTANCE_CONFLICT_RESOURCE_COUNT + 1))
            ;;
        *)
            return "$CBS_RC_INSTANCE_UNKNOWN"
            ;;
    esac
}

cbs_instance_emit_resource() {
    local type="${1:-}"
    local name="${2:-}"
    local state="${3:-}"

    echo "CBS_INSTANCE_RESOURCE_TYPE=$type"
    echo "CBS_INSTANCE_RESOURCE_NAME=$name"
    echo "CBS_INSTANCE_RESOURCE_STATE=$state"

    cbs_instance_count_state "$state"
}

cbs_instance_observe() {
    local manifest="${1:-}"

    if [[ -z "$manifest" ]]; then
        echo "CBS_INSTANCE_ERROR=MANIFEST_REQUIRED" >&2
        return "$CBS_RC_INSTANCE_USAGE"
    fi

    if [[ ! -f "$manifest" ]]; then
        echo "CBS_INSTANCE_ERROR=MANIFEST_INVALID" >&2
        return "$CBS_RC_INSTANCE_INVALID"
    fi

    set -a
    source "$manifest"
    set +a

    [[ -n "${CBS_INSTANCE_ID:-}" ]] ||
        return "$CBS_RC_INSTANCE_INVALID"

    [[ -n "${CBS_INSTANCE_VERSION:-}" ]] ||
        return "$CBS_RC_INSTANCE_INVALID"

    echo "CBS_INSTANCE_ID=$CBS_INSTANCE_ID"
    echo "CBS_INSTANCE_VERSION=$CBS_INSTANCE_VERSION"
    echo "CBS_INSTANCE_STACK_ID=${CBS_INSTANCE_STACK_ID:-UNKNOWN}"

    CBS_INSTANCE_EXPECTED_RESOURCE_COUNT=0
    CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT=0
    CBS_INSTANCE_CONFLICT_RESOURCE_COUNT=0

    local variable
    local name
    local state

    for variable in \
        CBS_INSTANCE_CONTAINER_REDIS \
        CBS_INSTANCE_CONTAINER_OPENSEARCH \
        CBS_INSTANCE_CONTAINER_POSTGRES \
        CBS_INSTANCE_CONTAINER_API \
        CBS_INSTANCE_CONTAINER_KONG \
        CBS_INSTANCE_CONTAINER_KEYCLOAK
    do
        name="${!variable:-}"
        [[ -n "$name" ]] || continue

        state="$(cbs_instance_container_state "$name")"
        cbs_instance_emit_resource \
            "$CBS_INSTANCE_RESOURCE_CONTAINER" \
            "$name" \
            "$state"
    done

    if [[ -n "${CBS_INSTANCE_NETWORK:-}" ]]; then
        state="$(cbs_instance_network_state "$CBS_INSTANCE_NETWORK")"

        cbs_instance_emit_resource \
            "$CBS_INSTANCE_RESOURCE_NETWORK" \
            "$CBS_INSTANCE_NETWORK" \
            "$state"
    fi

    if [[ -n "${CBS_INSTANCE_EXTERNAL_VOLUME:-}" ]]; then
        state="$(cbs_instance_volume_state "$CBS_INSTANCE_EXTERNAL_VOLUME")"

        cbs_instance_emit_resource \
            "$CBS_INSTANCE_RESOURCE_VOLUME" \
            "$CBS_INSTANCE_EXTERNAL_VOLUME" \
            "$state"
    fi

    echo "CBS_INSTANCE_EXPECTED_RESOURCE_COUNT=$CBS_INSTANCE_EXPECTED_RESOURCE_COUNT"
    echo "CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT=$CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT"
    echo "CBS_INSTANCE_CONFLICT_RESOURCE_COUNT=$CBS_INSTANCE_CONFLICT_RESOURCE_COUNT"

    local instance_state

    if [[ "$CBS_INSTANCE_CONFLICT_RESOURCE_COUNT" -gt 0 ]]; then
        instance_state="$CBS_INSTANCE_STATE_CONFLICT"
    elif [[ \
        "$CBS_INSTANCE_EXPECTED_RESOURCE_COUNT" -gt 0 &&
        "$CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT" -gt 0
    ]]; then
        instance_state="$CBS_INSTANCE_STATE_PARTIAL"
    elif [[ "$CBS_INSTANCE_EXPECTED_RESOURCE_COUNT" -gt 0 ]]; then
        instance_state="$CBS_INSTANCE_STATE_READY"
    elif [[ "$CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT" -gt 0 ]]; then
        instance_state="$CBS_INSTANCE_STATE_STOPPED"
    else
        instance_state="$CBS_INSTANCE_STATE_UNKNOWN"
    fi

    echo "CBS_INSTANCE_STATE=$instance_state"
    echo "CBS_INSTANCE_ACTION=$(cbs_instance_action_from_state "$instance_state")"
    echo "CBS_INSTANCE_OBSERVATION_RESULT=PASS"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_instance_observe "${1:-}"
fi

cbs_instance_mutation_decision() {
    local state="${1:-}"

    case "$state" in
        "$CBS_INSTANCE_STATE_READY")
            printf '%s\n' "$CBS_INSTANCE_ACTION_REUSE"
            ;;
        "$CBS_INSTANCE_STATE_STOPPED")
            printf '%s\n' "$CBS_INSTANCE_ACTION_REUSE"
            ;;
        "$CBS_INSTANCE_STATE_PARTIAL")
            printf '%s\n' "$CBS_INSTANCE_ACTION_OBSERVE"
            ;;
        "$CBS_INSTANCE_STATE_CONFLICT")
            printf '%s\n' "$CBS_INSTANCE_ACTION_BLOCK"
            ;;
        "$CBS_INSTANCE_STATE_INVALID")
            printf '%s\n' "$CBS_INSTANCE_ACTION_BLOCK"
            ;;
        "$CBS_INSTANCE_STATE_UNKNOWN")
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
