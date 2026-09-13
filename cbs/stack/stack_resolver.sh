#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/stack/contract.sh"

cbs_stack_manifest_validate() {
    local manifest="${1:-}"

    [[ -n "$manifest" ]] ||
        return "$CBS_RC_STACK_USAGE"

    [[ -f "$manifest" ]] ||
        return "$CBS_RC_STACK_INVALID"

    local stack_id
    local stack_version

    stack_id="$(
        (
            set -a
            source "$manifest"
            printf '%s\n' "${CBS_STACK_ID:-}"
        )
    )"

    stack_version="$(
        (
            set -a
            source "$manifest"
            printf '%s\n' "${CBS_STACK_VERSION:-}"
        )
    )"

    [[ -n "$stack_id" ]] ||
        return "$CBS_RC_STACK_INVALID"

    [[ -n "$stack_version" ]] ||
        return "$CBS_RC_STACK_INVALID"

    return 0
}

cbs_stack_resolve() {
    local manifest="${1:-}"

    if [[ -z "$manifest" ]]; then
        echo "CBS_STACK_ERROR=MANIFEST_REQUIRED" >&2
        return "$CBS_RC_STACK_USAGE"
    fi

    if ! cbs_stack_manifest_validate "$manifest"; then
        echo "CBS_STACK_MANIFEST=$manifest"
        echo "CBS_STACK_STATE=$CBS_STACK_STATE_INVALID"
        return "$CBS_RC_STACK_INVALID"
    fi

    set -a
    source "$manifest"
    set +a

    echo "CBS_STACK_MANIFEST=$manifest"
    echo "CBS_STACK_ID=$CBS_STACK_ID"
    echo "CBS_STACK_VERSION=$CBS_STACK_VERSION"
    echo "CBS_STACK_STATE=$CBS_STACK_STATE_READY"

    printf '%s\n' \
        CBS_STACK_PREREQUISITE_GIT \
        CBS_STACK_PREREQUISITE_UV \
        CBS_STACK_PREREQUISITE_DOCKER \
        CBS_STACK_PREREQUISITE_DOCKER_COMPOSE \
        CBS_STACK_PREREQUISITE_PYTHON_312 |
    while IFS= read -r name
    do
        value="${!name:-}"

        echo "CBS_STACK_PREREQUISITE_NAME=${name#CBS_STACK_PREREQUISITE_}"
        echo "CBS_STACK_PREREQUISITE_REQUIREMENT=$value"
    done

    printf '%s\n' \
        CBS_STACK_COMPONENT_FASTAPI \
        CBS_STACK_COMPONENT_SQLALCHEMY \
        CBS_STACK_COMPONENT_ALEMBIC \
        CBS_STACK_COMPONENT_POSTGRESQL \
        CBS_STACK_COMPONENT_POSTGIS \
        CBS_STACK_COMPONENT_PGVECTOR \
        CBS_STACK_COMPONENT_REDIS \
        CBS_STACK_COMPONENT_OPENSEARCH \
        CBS_STACK_COMPONENT_KONG \
        CBS_STACK_COMPONENT_KEYCLOAK |
    while IFS= read -r name
    do
        value="${!name:-}"

        echo "CBS_STACK_COMPONENT_NAME=${name#CBS_STACK_COMPONENT_}"
        echo "CBS_STACK_COMPONENT_REQUIREMENT=$value"
    done

    printf '%s\n' \
        "${CBS_STACK_MANIFEST_CAPABILITY_START:-}" \
        "${CBS_STACK_MANIFEST_CAPABILITY_CHECK:-}" \
        "${CBS_STACK_MANIFEST_CAPABILITY_STATUS:-}" \
        "${CBS_STACK_MANIFEST_CAPABILITY_QUALIFY:-}" |
    while IFS= read -r capability
    do
        [[ -n "$capability" ]] || continue
        echo "CBS_STACK_CAPABILITY=$capability"
    done

    echo "CBS_STACK_RESOLUTION_RESULT=PASS"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_stack_resolve "${1:-}"
fi
