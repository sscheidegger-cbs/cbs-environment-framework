#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/contract.sh"

DEFAULT_PREREQUISITE_CHECKER="$SCRIPT_DIR/prerequisite_checker.sh"
DEFAULT_ISOLATION_CHECKER="$SCRIPT_DIR/isolation_checker.sh"

cbs_workstation_check() {
    local context_file="${1:-}"

    local prerequisite_checker="${CBS_PREREQUISITE_CHECKER:-$DEFAULT_PREREQUISITE_CHECKER}"
    local isolation_checker="${CBS_ISOLATION_CHECKER:-$DEFAULT_ISOLATION_CHECKER}"

    local prerequisite_output=""
    local prerequisite_rc=0

    local isolation_output=""
    local isolation_rc=0

    if [[ -z "$context_file" ]]; then
        echo "CBS_WORKSTATION_ERROR=CONTEXT_FILE_REQUIRED" >&2
        return "$CBS_RC_INVALID_CONTEXT"
    fi

    if [[ ! -x "$prerequisite_checker" ]]; then
        echo "CBS_WORKSTATION_ERROR=PREREQUISITE_CHECKER_NOT_EXECUTABLE" >&2
        printf 'CBS_WORKSTATION_STATE=%s\n' "$CBS_WORKSTATION_UNKNOWN"
        return "$CBS_RC_INVALID_INPUT"
    fi

    if [[ ! -x "$isolation_checker" ]]; then
        echo "CBS_WORKSTATION_ERROR=ISOLATION_CHECKER_NOT_EXECUTABLE" >&2
        printf 'CBS_WORKSTATION_STATE=%s\n' "$CBS_WORKSTATION_UNKNOWN"
        return "$CBS_RC_INVALID_INPUT"
    fi

    set +e
    prerequisite_output="$("$prerequisite_checker" 2>&1)"
    prerequisite_rc=$?
    set -e

    printf '%s\n' "$prerequisite_output"
    printf 'CBS_WORKSTATION_PREREQUISITE_RC=%d\n' "$prerequisite_rc"

    case "$prerequisite_rc" in
        "$CBS_RC_OK")
            ;;
        "$CBS_RC_PREREQUISITE_FAILURE")
            printf 'CBS_WORKSTATION_STATE=%s\n' \
                "$CBS_WORKSTATION_INCOMPLETE"
            printf 'CBS_WORKSTATION_RESULT=%s\n' \
                "$CBS_RESULT_FAIL"
            return "$CBS_RC_PREREQUISITE_FAILURE"
            ;;
        *)
            printf 'CBS_WORKSTATION_STATE=%s\n' \
                "$CBS_WORKSTATION_UNKNOWN"
            printf 'CBS_WORKSTATION_RESULT=%s\n' \
                "$CBS_RESULT_UNKNOWN"
            return "$CBS_RC_INVALID_INPUT"
            ;;
    esac

    set +e
    isolation_output="$("$isolation_checker" "$context_file" 2>&1)"
    isolation_rc=$?
    set -e

    printf '%s\n' "$isolation_output"
    printf 'CBS_WORKSTATION_ISOLATION_RC=%d\n' "$isolation_rc"

    case "$isolation_rc" in
        "$CBS_RC_OK")
            printf 'CBS_WORKSTATION_STATE=%s\n' \
                "$CBS_WORKSTATION_READY"
            printf 'CBS_WORKSTATION_RESULT=%s\n' \
                "$CBS_RESULT_PASS"
            return "$CBS_RC_OK"
            ;;
        "$CBS_RC_ISOLATION_CONFLICT")
            printf 'CBS_WORKSTATION_STATE=%s\n' \
                "$CBS_WORKSTATION_CONFLICT"
            printf 'CBS_WORKSTATION_RESULT=%s\n' \
                "$CBS_RESULT_FAIL"
            return "$CBS_RC_ISOLATION_CONFLICT"
            ;;
        "$CBS_RC_PREREQUISITE_FAILURE")
            printf 'CBS_WORKSTATION_STATE=%s\n' \
                "$CBS_WORKSTATION_INCOMPLETE"
            printf 'CBS_WORKSTATION_RESULT=%s\n' \
                "$CBS_RESULT_FAIL"
            return "$CBS_RC_PREREQUISITE_FAILURE"
            ;;
        *)
            printf 'CBS_WORKSTATION_STATE=%s\n' \
                "$CBS_WORKSTATION_UNKNOWN"
            printf 'CBS_WORKSTATION_RESULT=%s\n' \
                "$CBS_RESULT_UNKNOWN"
            return "$CBS_RC_INVALID_INPUT"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_workstation_check "${1:-}"
fi
