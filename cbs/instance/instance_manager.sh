#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/instance/contract.sh"
source "$ROOT/cbs/instance/instance_observer.sh"

cbs_instance_ensure() {
    local manifest="${1:-}"

    if [[ -z "$manifest" ]]; then
        echo "CBS_INSTANCE_MANAGER_ERROR=MANIFEST_REQUIRED" >&2
        return "$CBS_RC_INSTANCE_USAGE"
    fi

    if [[ ! -f "$manifest" ]]; then
        echo "CBS_INSTANCE_MANAGER_ERROR=MANIFEST_INVALID" >&2
        return "$CBS_RC_INSTANCE_INVALID"
    fi

    local observation
    local state
    local action

    observation="$(
        cbs_instance_observe "$manifest"
    )"

    state="$(
        awk -F= '
            $1 == "CBS_INSTANCE_STATE" {
                print $2
            }
        ' <<<"$observation"
    )"

    action="$(
        cbs_instance_mutation_decision "$state"
    )"

    echo "CBS_INSTANCE_MANAGER_STATE_BEFORE=$state"
    echo "CBS_INSTANCE_MANAGER_ACTION=$action"

    case "$action" in
        "$CBS_INSTANCE_ACTION_REUSE")
            echo "CBS_INSTANCE_MANAGER_MUTATION=NONE"
            echo "CBS_INSTANCE_MANAGER_RESULT=PASS"
            return 0
            ;;

        "$CBS_INSTANCE_ACTION_OBSERVE")
            echo "CBS_INSTANCE_MANAGER_MUTATION=NONE"
            echo "CBS_INSTANCE_MANAGER_RESULT=BLOCKED"
            return "$CBS_RC_INSTANCE_UNKNOWN"
            ;;

        "$CBS_INSTANCE_ACTION_BLOCK")
            echo "CBS_INSTANCE_MANAGER_MUTATION=NONE"
            echo "CBS_INSTANCE_MANAGER_RESULT=BLOCKED"
            return "$CBS_RC_INSTANCE_CONFLICT"
            ;;

        "$CBS_INSTANCE_ACTION_CREATE")
            echo "CBS_INSTANCE_MANAGER_MUTATION=NONE"
            echo "CBS_INSTANCE_MANAGER_RESULT=NOT_IMPLEMENTED"
            return "$CBS_RC_INSTANCE_INVALID"
            ;;

        *)
            echo "CBS_INSTANCE_MANAGER_MUTATION=NONE"
            echo "CBS_INSTANCE_MANAGER_RESULT=UNKNOWN"
            return "$CBS_RC_INSTANCE_UNKNOWN"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_instance_ensure "${1:-}"
fi
