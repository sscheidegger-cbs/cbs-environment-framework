#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/stack/contract.sh"
source "$ROOT/cbs/stack/stack_resolver.sh"

TOOLCHAIN_MANAGER="$ROOT/cbs/toolchain/toolchain_manager.sh"

cbs_stack_toolchain_manifest_value() {
    local resource_id="${1:-}"
    local field="${2:-}"
    local variable="CBS_STACK_MANAGED_TOOLCHAIN_${resource_id}_${field}"

    printf '%s\n' "${!variable:-}"
}

cbs_stack_toolchain_ensure() {
    local manifest="${1:-}"

    if [[ -z "$manifest" ]]; then
        echo "CBS_STACK_TOOLCHAIN_ERROR=MANIFEST_REQUIRED" >&2
        return "$CBS_RC_STACK_USAGE"
    fi

    if ! cbs_stack_manifest_validate "$manifest"; then
        echo "CBS_STACK_TOOLCHAIN_ERROR=MANIFEST_INVALID" >&2
        return "$CBS_RC_STACK_INVALID"
    fi

    if [[ ! -x "$TOOLCHAIN_MANAGER" ]]; then
        echo "CBS_STACK_TOOLCHAIN_ERROR=TOOLCHAIN_MANAGER_NOT_EXECUTABLE" >&2
        return "$CBS_RC_STACK_INVALID"
    fi

    set -a
    source "$manifest"
    set +a

    local declared_ids="${CBS_STACK_MANAGED_TOOLCHAIN_IDS:-}"

    local required_count=0
    local ensured_count=0
    local failure_count=0

    local resource_id
    local requirement
    local version
    local provider
    local toolchain_id

    for resource_id in $declared_ids
    do
        requirement="$(
            cbs_stack_toolchain_manifest_value \
                "$resource_id" \
                "REQUIREMENT"
        )"

        version="$(
            cbs_stack_toolchain_manifest_value \
                "$resource_id" \
                "VERSION"
        )"

        provider="$(
            cbs_stack_toolchain_manifest_value \
                "$resource_id" \
                "PROVIDER"
        )"

        if [[ -z "$requirement" || -z "$version" || -z "$provider" ]]; then
            echo "CBS_STACK_RESOURCE_TYPE=MANAGED_TOOLCHAIN"
            echo "CBS_STACK_MANAGED_TOOLCHAIN_ID=$resource_id"
            echo "CBS_STACK_MANAGED_TOOLCHAIN_ERROR=DECLARATION_INVALID"
            failure_count=$((failure_count + 1))
            continue
        fi

        case "$requirement" in
            REQUIRED)
                required_count=$((required_count + 1))
                ;;
            OPTIONAL)
                ;;
            DISABLED)
                continue
                ;;
            *)
                echo "CBS_STACK_RESOURCE_TYPE=MANAGED_TOOLCHAIN"
                echo "CBS_STACK_MANAGED_TOOLCHAIN_ID=$resource_id"
                echo "CBS_STACK_MANAGED_TOOLCHAIN_ERROR=REQUIREMENT_INVALID"
                failure_count=$((failure_count + 1))
                continue
                ;;
        esac

        toolchain_id="$(
            cbs_stack_toolchain_manifest_value \
                "$resource_id" \
                "ID"
        )"

        if [[ -z "$toolchain_id" ]]; then
            toolchain_id="$(
                printf '%s' "$resource_id" |
                    tr '[:upper:]' '[:lower:]'
            )"
        fi

        local toolchain_manifest
        toolchain_manifest="$(mktemp)"

        cat > "$toolchain_manifest" <<MANIFEST
CBS_TOOLCHAIN_ID=$toolchain_id
CBS_TOOLCHAIN_VERSION=$version
CBS_TOOLCHAIN_PROVIDER=$provider
MANIFEST

        local ensure_output
        local ensure_rc

        set +e
        ensure_output="$("$TOOLCHAIN_MANAGER" ensure "$toolchain_manifest" 2>&1)"
        ensure_rc=$?
        set -e

        rm -f "$toolchain_manifest"

        echo "CBS_STACK_RESOURCE_TYPE=MANAGED_TOOLCHAIN"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_ID=$resource_id"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_REQUIREMENT=$requirement"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_VERSION=$version"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_PROVIDER=$provider"

        if [[ "$ensure_rc" -ne 0 ]]; then
            echo "$ensure_output"
            echo "CBS_STACK_MANAGED_TOOLCHAIN_RESULT=FAIL"
            failure_count=$((failure_count + 1))
            continue
        fi

        local action=""
        local mutation=""
        local verification=""
        local resolved_path=""
        local version_observed=""

        while IFS= read -r line
        do
            case "$line" in
                CBS_TOOLCHAIN_ACTION=*)
                    action="${line#CBS_TOOLCHAIN_ACTION=}"
                    ;;
                CBS_TOOLCHAIN_MUTATION=*)
                    mutation="${line#CBS_TOOLCHAIN_MUTATION=}"
                    ;;
                CBS_TOOLCHAIN_VERIFICATION_RESULT=*)
                    verification="${line#CBS_TOOLCHAIN_VERIFICATION_RESULT=}"
                    ;;
                CBS_TOOLCHAIN_RESOLVED_PATH=*)
                    resolved_path="${line#CBS_TOOLCHAIN_RESOLVED_PATH=}"
                    ;;
                CBS_TOOLCHAIN_VERSION_OBSERVED=*)
                    version_observed="${line#CBS_TOOLCHAIN_VERSION_OBSERVED=}"
                    ;;
            esac
        done <<<"$ensure_output"

        echo "CBS_STACK_MANAGED_TOOLCHAIN_RESOLVED_PATH=$resolved_path"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_ACTION=$action"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_MUTATION=$mutation"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_VERSION_OBSERVED=$version_observed"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_VERIFICATION_RESULT=$verification"
        echo "CBS_STACK_MANAGED_TOOLCHAIN_RESULT=PASS"

        ensured_count=$((ensured_count + 1))
    done

    echo "CBS_STACK_TOOLCHAIN_REQUIRED_COUNT=$required_count"
    echo "CBS_STACK_TOOLCHAIN_ENSURED_COUNT=$ensured_count"
    echo "CBS_STACK_TOOLCHAIN_FAILURE_COUNT=$failure_count"

    if [[ "$failure_count" -gt 0 ]]; then
        echo "CBS_STACK_TOOLCHAIN_ENSURE_RESULT=FAIL"
        return "$CBS_RC_STACK_INVALID"
    fi

    echo "CBS_STACK_TOOLCHAIN_ENSURE_RESULT=PASS"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_stack_toolchain_ensure "${1:-}"
fi
