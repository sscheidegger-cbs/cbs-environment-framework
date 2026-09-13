#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/platform/contract.sh"

cbs_platform_repository_from_manifest() {
    local manifest="${1:-}"

    [[ -n "$manifest" ]] ||
        return "$CBS_RC_PLATFORM_USAGE"

    [[ -f "$manifest" ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    local manifest_dir
    local relative_path

    manifest_dir="$(cd "$(dirname "$manifest")" && pwd)"

    relative_path="$(
        awk -F= '
            $1 == "CBS_PLATFORM_REPOSITORY_RELATIVE_PATH" {
                print $2
            }
        ' "$manifest"
    )"

    [[ -n "$relative_path" ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    (
        cd "$manifest_dir/$relative_path" 2>/dev/null &&
        pwd
    ) || return "$CBS_RC_PLATFORM_INVALID"
}

cbs_platform_hook_state() {
    local repository="${1:-}"
    local hook="${2:-}"

    [[ -n "$repository" ]] ||
        return "$CBS_RC_PLATFORM_USAGE"

    [[ -n "$hook" ]] ||
        return "$CBS_RC_PLATFORM_USAGE"

    if [[ ! -e "$repository/$hook" ]]; then
        printf '%s\n' "$CBS_PLATFORM_HOOK_MISSING"
        return 0
    fi

    if [[ ! -x "$repository/$hook" ]]; then
        printf '%s\n' "$CBS_PLATFORM_HOOK_NOT_EXECUTABLE"
        return 0
    fi

    printf '%s\n' "$CBS_PLATFORM_HOOK_PRESENT"
}

cbs_platform_resolve() {
    local manifest="${1:-}"

    if [[ -z "$manifest" ]]; then
        echo "CBS_PLATFORM_ERROR=MANIFEST_REQUIRED" >&2
        return "$CBS_RC_PLATFORM_USAGE"
    fi

    if [[ ! -f "$manifest" ]]; then
        echo "CBS_PLATFORM_ERROR=MANIFEST_INVALID" >&2
        return "$CBS_RC_PLATFORM_INVALID"
    fi

    set -a
    source "$manifest"
    set +a

    [[ -n "${CBS_PLATFORM_ID:-}" ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    [[ -n "${CBS_PLATFORM_VERSION:-}" ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    local repository

    repository="$(
        cbs_platform_repository_from_manifest "$manifest"
    )"

    [[ -d "$repository/.git" ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    echo "CBS_PLATFORM_ID=$CBS_PLATFORM_ID"
    echo "CBS_PLATFORM_VERSION=$CBS_PLATFORM_VERSION"
    echo "CBS_PLATFORM_STACK_ID=${CBS_PLATFORM_STACK_ID:-UNKNOWN}"
    echo "CBS_PLATFORM_INSTANCE_ID=${CBS_PLATFORM_INSTANCE_ID:-UNKNOWN}"
    echo "CBS_PLATFORM_REPOSITORY=$repository"

    local missing=0
    local not_executable=0

    local variable
    local action
    local hook
    local state

    for variable in \
        CBS_PLATFORM_HOOK_START \
        CBS_PLATFORM_HOOK_CHECK \
        CBS_PLATFORM_HOOK_STATUS \
        CBS_PLATFORM_HOOK_STOP \
        CBS_PLATFORM_HOOK_QUALIFY
    do
        action="${variable#CBS_PLATFORM_HOOK_}"
        action="${action,,}"

        hook="${!variable:-}"

        if [[ -z "$hook" ]]; then
            state="$CBS_PLATFORM_HOOK_MISSING"
        else
            state="$(
                cbs_platform_hook_state \
                    "$repository" \
                    "$hook"
            )"
        fi

        case "$state" in
            "$CBS_PLATFORM_HOOK_MISSING")
                missing=$((missing + 1))
                ;;
            "$CBS_PLATFORM_HOOK_NOT_EXECUTABLE")
                not_executable=$((not_executable + 1))
                ;;
        esac

        echo "CBS_PLATFORM_HOOK_ACTION=$action"
        echo "CBS_PLATFORM_HOOK_PATH=$hook"
        echo "CBS_PLATFORM_HOOK_STATE=$state"
    done

    local platform_state

    platform_state="$(
        cbs_platform_state_from_hook_failures \
            "$missing" \
            "$not_executable"
    )"

    echo "CBS_PLATFORM_HOOK_MISSING_COUNT=$missing"
    echo "CBS_PLATFORM_HOOK_NOT_EXECUTABLE_COUNT=$not_executable"
    echo "CBS_PLATFORM_STATE=$platform_state"

    if [[ "$platform_state" == "$CBS_PLATFORM_STATE_READY" ]]; then
        echo "CBS_PLATFORM_RESOLUTION_RESULT=PASS"
        return 0
    fi

    echo "CBS_PLATFORM_RESOLUTION_RESULT=FAIL"

    if [[ "$missing" -gt 0 ]]; then
        return "$CBS_RC_PLATFORM_HOOK_MISSING"
    fi

    if [[ "$not_executable" -gt 0 ]]; then
        return "$CBS_RC_PLATFORM_HOOK_NOT_EXECUTABLE"
    fi

    return "$CBS_RC_PLATFORM_UNKNOWN"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_platform_resolve "${1:-}"
fi
