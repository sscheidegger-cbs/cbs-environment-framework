#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/contract.sh"
source "$CBS_ROOT/cbs/context/context.sh"

cbs_isolation_normalize_name() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr '_' '-'
}

cbs_isolation_resource_belongs_to_context() {
    local resource_name="$1"
    local entity_name="$2"

    local normalized_resource
    local normalized_entity

    normalized_resource="$(
        cbs_isolation_normalize_name "$resource_name"
    )"

    normalized_entity="$(
        cbs_isolation_normalize_name "$entity_name"
    )"

    case "$normalized_resource" in
        "$normalized_entity"|"$normalized_entity"-*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_isolation_classify_named_resource() {
    local resource_name="$1"
    local entity_name="$2"

    if cbs_isolation_resource_belongs_to_context \
        "$resource_name" \
        "$entity_name"
    then
        printf '%s\n' "$CBS_RESOURCE_EXPECTED"
        return "$CBS_RC_OK"
    fi

    printf '%s\n' "$CBS_RESOURCE_EXTERNAL"
    return "$CBS_RC_OK"
}

cbs_isolation_emit_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local classification="$3"
    local owner="${4:-}"

    printf 'CBS_ISOLATION_RESOURCE_TYPE=%s\n' "$resource_type"
    printf 'CBS_ISOLATION_RESOURCE_NAME=%s\n' "$resource_name"
    printf 'CBS_ISOLATION_RESOURCE_CLASS=%s\n' "$classification"

    if [[ -n "$owner" ]]; then
        printf 'CBS_ISOLATION_RESOURCE_OWNER=%s\n' "$owner"
    fi
}

cbs_isolation_check_containers() {
    local expected=0
    local external=0
    local name
    local classification

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue

        classification="$(
            cbs_isolation_classify_named_resource \
                "$name" \
                "$CBS_CONTEXT_ENTITY_NAME"
        )"

        cbs_isolation_emit_resource \
            "CONTAINER" \
            "$name" \
            "$classification" \
            "$name"

        case "$classification" in
            "$CBS_RESOURCE_EXPECTED")
                expected=$((expected + 1))
                ;;
            "$CBS_RESOURCE_EXTERNAL")
                external=$((external + 1))
                ;;
        esac
    done < <(
        docker ps -a \
            --format '{{.Names}}' \
            2>/dev/null
    )

    CBS_ISOLATION_CONTAINER_EXPECTED="$expected"
    CBS_ISOLATION_CONTAINER_EXTERNAL="$external"
}

cbs_isolation_check_networks() {
    local expected=0
    local external=0
    local name
    local classification

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue

        case "$name" in
            bridge|host|none)
                classification="$CBS_RESOURCE_EXTERNAL"
                ;;
            *)
                classification="$(
                    cbs_isolation_classify_named_resource \
                        "$name" \
                        "$CBS_CONTEXT_ENTITY_NAME"
                )"
                ;;
        esac

        cbs_isolation_emit_resource \
            "NETWORK" \
            "$name" \
            "$classification"

        case "$classification" in
            "$CBS_RESOURCE_EXPECTED")
                expected=$((expected + 1))
                ;;
            "$CBS_RESOURCE_EXTERNAL")
                external=$((external + 1))
                ;;
        esac
    done < <(
        docker network ls \
            --format '{{.Name}}' \
            2>/dev/null
    )

    CBS_ISOLATION_NETWORK_EXPECTED="$expected"
    CBS_ISOLATION_NETWORK_EXTERNAL="$external"
}

cbs_isolation_check_volumes() {
    local expected=0
    local external=0
    local name
    local classification

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue

        classification="$(
            cbs_isolation_classify_named_resource \
                "$name" \
                "$CBS_CONTEXT_ENTITY_NAME"
        )"

        cbs_isolation_emit_resource \
            "VOLUME" \
            "$name" \
            "$classification"

        case "$classification" in
            "$CBS_RESOURCE_EXPECTED")
                expected=$((expected + 1))
                ;;
            "$CBS_RESOURCE_EXTERNAL")
                external=$((external + 1))
                ;;
        esac
    done < <(
        docker volume ls \
            --format '{{.Name}}' \
            2>/dev/null
    )

    CBS_ISOLATION_VOLUME_EXPECTED="$expected"
    CBS_ISOLATION_VOLUME_EXTERNAL="$external"
}

cbs_isolation_check_published_ports() {
    local expected=0
    local external=0

    local container_name
    local ports
    local classification
    local port

    while IFS='|' read -r container_name ports; do
        [[ -n "$container_name" ]] || continue
        [[ -n "$ports" ]] || continue

        classification="$(
            cbs_isolation_classify_named_resource \
                "$container_name" \
                "$CBS_CONTEXT_ENTITY_NAME"
        )"

        while IFS= read -r port; do
            [[ -n "$port" ]] || continue

            cbs_isolation_emit_resource \
                "PORT" \
                "$port" \
                "$classification" \
                "$container_name"

            case "$classification" in
                "$CBS_RESOURCE_EXPECTED")
                    expected=$((expected + 1))
                    ;;
                "$CBS_RESOURCE_EXTERNAL")
                    external=$((external + 1))
                    ;;
            esac
        done < <(
            printf '%s\n' "$ports" |
                grep -oE '([0-9]+\.){3}[0-9]+:[0-9]+|:::[0-9]+|0\.0\.0\.0:[0-9]+' |
                sed -E 's/^.*:([0-9]+)$/\1/' |
                sort -u ||
                true
        )
    done < <(
        docker ps \
            --format '{{.Names}}|{{.Ports}}' \
            2>/dev/null
    )

    CBS_ISOLATION_PORT_EXPECTED="$expected"
    CBS_ISOLATION_PORT_EXTERNAL="$external"
}

cbs_isolation_check() {
    local context_file="${1:-}"

    if [[ -z "$context_file" ]]; then
        echo "CBS_ISOLATION_ERROR=CONTEXT_FILE_REQUIRED" >&2
        return "$CBS_RC_INVALID_CONTEXT"
    fi

    cbs_context_load "$context_file" || return $?

    if ! command -v docker >/dev/null 2>&1; then
        echo "CBS_ISOLATION_ERROR=DOCKER_NOT_FOUND" >&2
        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "CBS_ISOLATION_ERROR=DOCKER_UNAVAILABLE" >&2
        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    CBS_ISOLATION_CONFLICTS=0

    cbs_isolation_check_containers
    cbs_isolation_check_networks
    cbs_isolation_check_volumes
    cbs_isolation_check_published_ports

    printf 'CBS_ISOLATION_CONTAINER_EXPECTED=%d\n' \
        "$CBS_ISOLATION_CONTAINER_EXPECTED"

    printf 'CBS_ISOLATION_CONTAINER_EXTERNAL=%d\n' \
        "$CBS_ISOLATION_CONTAINER_EXTERNAL"

    printf 'CBS_ISOLATION_NETWORK_EXPECTED=%d\n' \
        "$CBS_ISOLATION_NETWORK_EXPECTED"

    printf 'CBS_ISOLATION_NETWORK_EXTERNAL=%d\n' \
        "$CBS_ISOLATION_NETWORK_EXTERNAL"

    printf 'CBS_ISOLATION_VOLUME_EXPECTED=%d\n' \
        "$CBS_ISOLATION_VOLUME_EXPECTED"

    printf 'CBS_ISOLATION_VOLUME_EXTERNAL=%d\n' \
        "$CBS_ISOLATION_VOLUME_EXTERNAL"

    printf 'CBS_ISOLATION_PORT_EXPECTED=%d\n' \
        "$CBS_ISOLATION_PORT_EXPECTED"

    printf 'CBS_ISOLATION_PORT_EXTERNAL=%d\n' \
        "$CBS_ISOLATION_PORT_EXTERNAL"

    printf 'CBS_ISOLATION_CONFLICTS=%d\n' \
        "$CBS_ISOLATION_CONFLICTS"

    if ((CBS_ISOLATION_CONFLICTS > 0)); then
        printf 'CBS_ISOLATION_RESULT=%s\n' "$CBS_RESULT_FAIL"
        return "$CBS_RC_ISOLATION_CONFLICT"
    fi

    printf 'CBS_ISOLATION_RESULT=%s\n' "$CBS_RESULT_PASS"

    return "$CBS_RC_OK"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_isolation_check "${1:-}"
fi

cbs_isolation_classify_claim() {
    local expected_owner="${1:-}"
    local observed_owner="${2:-}"

    if [[ -z "$expected_owner" || -z "$observed_owner" ]]; then
        printf '%s\n' "$CBS_RESOURCE_UNKNOWN"
        return "$CBS_RC_OK"
    fi

    if [[ "$expected_owner" == "$observed_owner" ]]; then
        printf '%s\n' "$CBS_RESOURCE_EXPECTED"
        return "$CBS_RC_OK"
    fi

    printf '%s\n' "$CBS_RESOURCE_CONFLICT"
    return "$CBS_RC_OK"
}
