#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/stack/contract.sh"
source "$ROOT/cbs/stack/resource_contract.sh"

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

cbs_stack_manifest_variable_names() {
    local manifest="${1:-}"
    local prefix="${2:-}"

    awk -F= -v prefix="$prefix" '
        /^[[:space:]]*#/ {
            next
        }

        /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ {
            name = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)

            if (index(name, prefix) == 1) {
                print name
            }
        }
    ' "$manifest" |
        LC_ALL=C sort -u
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

    local name
    local value

    while IFS= read -r name
    do
        [[ -n "$name" ]] || continue

        value="${!name:-}"

        echo "CBS_STACK_RESOURCE_TYPE=$CBS_STACK_RESOURCE_TYPE_SYSTEM_PREREQUISITE"
        echo "CBS_STACK_PREREQUISITE_NAME=${name#CBS_STACK_PREREQUISITE_}"
        echo "CBS_STACK_PREREQUISITE_REQUIREMENT=$value"
    done < <(
        cbs_stack_manifest_variable_names \
            "$manifest" \
            "CBS_STACK_PREREQUISITE_"
    )

    while IFS= read -r name
    do
        [[ -n "$name" ]] || continue

        value="${!name:-}"

        echo "CBS_STACK_RESOURCE_TYPE=$CBS_STACK_RESOURCE_TYPE_RUNTIME_COMPONENT"
        echo "CBS_STACK_COMPONENT_NAME=${name#CBS_STACK_COMPONENT_}"
        echo "CBS_STACK_COMPONENT_REQUIREMENT=$value"
    done < <(
        cbs_stack_manifest_variable_names \
            "$manifest" \
            "CBS_STACK_COMPONENT_"
    )

    while IFS= read -r name
    do
        [[ -n "$name" ]] || continue

        value="${!name:-}"
        [[ -n "$value" ]] || continue

        echo "CBS_STACK_RESOURCE_TYPE=$CBS_STACK_RESOURCE_TYPE_PLATFORM_CAPABILITY"
        echo "CBS_STACK_CAPABILITY=$value"
    done < <(
        cbs_stack_manifest_variable_names \
            "$manifest" \
            "CBS_STACK_MANIFEST_CAPABILITY_"
    )

    local resource_id
    local field
    local variable

    for resource_id in ${CBS_STACK_MANAGED_TOOLCHAIN_IDS:-}
    do
        echo "CBS_STACK_RESOURCE_TYPE=$CBS_STACK_RESOURCE_TYPE_MANAGED_TOOLCHAIN"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_ID=$resource_id"

        for field in REQUIREMENT VERSION PROVIDER
        do
            variable="CBS_STACK_MANAGED_TOOLCHAIN_${resource_id}_${field}"
            value="${!variable:-}"

            [[ -n "$value" ]] || continue

            echo "CBS_STACK_MANAGED_TOOLCHAIN_${field}=$value"
        done
    done

    for resource_id in ${CBS_STACK_PROJECT_DEPENDENCY_IDS:-}
    do
        echo "CBS_STACK_RESOURCE_TYPE=$CBS_STACK_RESOURCE_TYPE_PROJECT_DEPENDENCY"
        echo "CBS_STACK_PROJECT_DEPENDENCY_ID=$resource_id"

        for field in REQUIREMENT VERSION
        do
            variable="CBS_STACK_PROJECT_DEPENDENCY_${resource_id}_${field}"
            value="${!variable:-}"

            [[ -n "$value" ]] || continue

            echo "CBS_STACK_PROJECT_DEPENDENCY_${field}=$value"
        done
    done

    echo "CBS_STACK_RESOLUTION_RESULT=PASS"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_stack_resolve "${1:-}"
fi
