#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/stack/contract.sh"

RESOLVER="$ROOT/cbs/stack/stack_resolver.sh"
PREREQUISITE_CHECKER="$ROOT/cbs/workstation/prerequisite_checker.sh"

cbs_stack_prerequisite_observed_state() {
    local checker_output="${1:-}"
    local prerequisite="${2:-}"

    awk -v target="$prerequisite" '
        $0 == "CBS_PREREQUISITE_NAME=" target {
            found = 1
            next
        }

        found && /^CBS_PREREQUISITE_STATE=/ {
            sub(/^CBS_PREREQUISITE_STATE=/, "")
            print
            exit
        }
    ' <<<"$checker_output"
}

cbs_stack_prerequisite_evaluate() {
    local manifest="${1:-}"

    if [[ -z "$manifest" ]]; then
        echo "CBS_STACK_PREREQUISITE_ERROR=MANIFEST_REQUIRED" >&2
        return "$CBS_RC_STACK_USAGE"
    fi

    if [[ ! -f "$manifest" ]]; then
        echo "CBS_STACK_PREREQUISITE_ERROR=MANIFEST_INVALID" >&2
        return "$CBS_RC_STACK_INVALID"
    fi

    local resolution
    local prerequisite_output

    resolution="$("$RESOLVER" "$manifest")"

    set +e
    prerequisite_output="$("$PREREQUISITE_CHECKER" 2>&1)"
    local prerequisite_rc=$?
    set -e

    local required_count=0
    local missing_count=0
    local prerequisite=""
    local requirement=""
    local observed_state=""

    while IFS= read -r line
    do
        case "$line" in
            CBS_STACK_PREREQUISITE_NAME=*)
                prerequisite="${line#CBS_STACK_PREREQUISITE_NAME=}"
                ;;

            CBS_STACK_PREREQUISITE_REQUIREMENT=*)
                requirement="${line#CBS_STACK_PREREQUISITE_REQUIREMENT=}"

                if [[ "$requirement" != "$CBS_STACK_COMPONENT_REQUIRED" ]]; then
                    continue
                fi

                required_count=$((required_count + 1))

                observed_state="$(
                    cbs_stack_prerequisite_observed_state \
                        "$prerequisite_output" \
                        "$prerequisite"
                )"

                if [[ -z "$observed_state" ]]; then
                    observed_state="$CBS_STACK_PREREQUISITE_UNKNOWN"
                fi

                echo "CBS_STACK_PREREQUISITE_NAME=$prerequisite"
                echo "CBS_STACK_PREREQUISITE_REQUIREMENT=$requirement"
                echo "CBS_STACK_PREREQUISITE_OBSERVED_STATE=$observed_state"

                if [[ "$observed_state" == "PRESENT" ]]; then
                    echo "CBS_STACK_PREREQUISITE_RESULT=PASS"
                else
                    missing_count=$((missing_count + 1))
                    echo "CBS_STACK_PREREQUISITE_RESULT=FAIL"
                fi
                ;;
        esac
    done <<<"$resolution"

    local stack_state
    stack_state="$(
        cbs_stack_state_from_missing_required_count "$missing_count"
    )"

    echo "CBS_STACK_PREREQUISITE_REQUIRED_COUNT=$required_count"
    echo "CBS_STACK_PREREQUISITE_FAILURE_COUNT=$missing_count"
    echo "CBS_STACK_STATE=$stack_state"

    if [[ "$missing_count" -gt 0 ]]; then
        echo "CBS_STACK_PREREQUISITE_EVALUATION_RESULT=FAIL"
        return "$CBS_RC_STACK_PREREQUISITE_MISSING"
    fi

    # The Workstation checker may inspect prerequisites that are not part of
    # this stack manifest. Its aggregate return code is therefore informative
    # only; stack readiness is derived exclusively from required manifest items.
    : "$prerequisite_rc"

    echo "CBS_STACK_PREREQUISITE_EVALUATION_RESULT=PASS"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_stack_prerequisite_evaluate "${1:-}"
fi
