#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/platform/contract.sh"
source "$ROOT/cbs/platform/platform_resolver.sh"

cbs_platform_hook_from_action() {
    local manifest="${1:-}"
    local action="${2:-}"

    [[ -n "$manifest" ]] ||
        return "$CBS_RC_PLATFORM_USAGE"

    [[ -n "$action" ]] ||
        return "$CBS_RC_PLATFORM_USAGE"

    cbs_platform_action_is_valid "$action" ||
        return "$CBS_RC_PLATFORM_INVALID"

    [[ -f "$manifest" ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    set -a
    source "$manifest"
    set +a

    case "$action" in
        start)
            printf '%s\n' "${CBS_PLATFORM_HOOK_START:-}"
            ;;
        check)
            printf '%s\n' "${CBS_PLATFORM_HOOK_CHECK:-}"
            ;;
        status)
            printf '%s\n' "${CBS_PLATFORM_HOOK_STATUS:-}"
            ;;
        stop)
            printf '%s\n' "${CBS_PLATFORM_HOOK_STOP:-}"
            ;;
        qualify)
            printf '%s\n' "${CBS_PLATFORM_HOOK_QUALIFY:-}"
            ;;
        *)
            return "$CBS_RC_PLATFORM_INVALID"
            ;;
    esac
}

cbs_platform_run_hook() {
    local manifest="${1:-}"
    local action="${2:-}"

    if [[ -z "$manifest" || -z "$action" ]]; then
        echo "CBS_PLATFORM_RUNNER_ERROR=USAGE" >&2
        return "$CBS_RC_PLATFORM_USAGE"
    fi

    if ! cbs_platform_action_is_valid "$action"; then
        echo "CBS_PLATFORM_RUNNER_ERROR=INVALID_ACTION" >&2
        return "$CBS_RC_PLATFORM_INVALID"
    fi

    local repository
    local hook
    local hook_state

    repository="$(
        cbs_platform_repository_from_manifest "$manifest"
    )"

    hook="$(
        cbs_platform_hook_from_action \
            "$manifest" \
            "$action"
    )"

    [[ -n "$repository" ]] ||
        return "$CBS_RC_PLATFORM_INVALID"

    [[ -n "$hook" ]] ||
        return "$CBS_RC_PLATFORM_HOOK_MISSING"

    hook_state="$(
        cbs_platform_hook_state \
            "$repository" \
            "$hook"
    )"

    case "$hook_state" in
        "$CBS_PLATFORM_HOOK_MISSING")
            echo "CBS_PLATFORM_RUNNER_ERROR=HOOK_MISSING" >&2
            return "$CBS_RC_PLATFORM_HOOK_MISSING"
            ;;
        "$CBS_PLATFORM_HOOK_NOT_EXECUTABLE")
            echo "CBS_PLATFORM_RUNNER_ERROR=HOOK_NOT_EXECUTABLE" >&2
            return "$CBS_RC_PLATFORM_HOOK_NOT_EXECUTABLE"
            ;;
        "$CBS_PLATFORM_HOOK_PRESENT")
            ;;
        *)
            echo "CBS_PLATFORM_RUNNER_ERROR=HOOK_UNKNOWN" >&2
            return "$CBS_RC_PLATFORM_UNKNOWN"
            ;;
    esac

    echo "CBS_PLATFORM_RUNNER_ACTION=$action"
    echo "CBS_PLATFORM_RUNNER_REPOSITORY=$repository"
    echo "CBS_PLATFORM_RUNNER_HOOK=$hook"

    set +e
    (
        cd "$repository"
        "./$hook"
    )
    local rc=$?
    set -e

    echo "CBS_PLATFORM_RUNNER_HOOK_RC=$rc"

    if [[ "$rc" -eq 0 ]]; then
        echo "CBS_PLATFORM_RUNNER_RESULT=PASS"
        return 0
    fi

    echo "CBS_PLATFORM_RUNNER_RESULT=FAIL"
    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_platform_run_hook "${1:-}" "${2:-}"
fi
