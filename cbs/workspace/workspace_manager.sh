#!/usr/bin/env bash

set -Eeuo pipefail

CBS_WORKSPACE_MANAGER_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

source "$CBS_WORKSPACE_MANAGER_DIR/contract.sh"

cbs_workspace_ensure() {
    local workspace_path="${1:-}"

    if [[ -z "$workspace_path" ]]; then
        echo "CBS_WORKSPACE_ERROR=WORKSPACE_PATH_REQUIRED" >&2
        return "$CBS_WORKSPACE_RC_USAGE"
    fi

    local path_class
    local state

    path_class="$(
        cbs_workspace_classify_path "$workspace_path"
    )"

    state="$(
        cbs_workspace_state_from_path_class "$path_class"
    )"

    printf 'CBS_WORKSPACE_PATH=%s\n' "$workspace_path"
    printf 'CBS_WORKSPACE_PATH_CLASS_BEFORE=%s\n' "$path_class"
    printf 'CBS_WORKSPACE_STATE_BEFORE=%s\n' "$state"

    case "$state" in
        "$CBS_WORKSPACE_READY")
            echo "CBS_WORKSPACE_ACTION=REUSE"
            echo "CBS_WORKSPACE_STATE=READY"
            return "$CBS_WORKSPACE_RC_OK"
            ;;

        "$CBS_WORKSPACE_MISSING")
            local parent

            parent="$(dirname "$workspace_path")"

            if [[ ! -d "$parent" ]]; then
                echo "CBS_WORKSPACE_ACTION=BLOCK"
                echo "CBS_WORKSPACE_ERROR=PARENT_DIRECTORY_MISSING" >&2
                echo "CBS_WORKSPACE_PARENT=$parent" >&2
                return "$CBS_WORKSPACE_RC_MISSING"
            fi

            echo "CBS_WORKSPACE_ACTION=CREATE"

            if ! mkdir -- "$workspace_path"; then
                echo "CBS_WORKSPACE_ERROR=CREATE_FAILED" >&2
                return "$CBS_WORKSPACE_RC_UNKNOWN"
            fi

            local class_after
            local state_after

            class_after="$(
                cbs_workspace_classify_path "$workspace_path"
            )"

            state_after="$(
                cbs_workspace_state_from_path_class "$class_after"
            )"

            printf 'CBS_WORKSPACE_PATH_CLASS_AFTER=%s\n' "$class_after"
            printf 'CBS_WORKSPACE_STATE_AFTER=%s\n' "$state_after"

            if [[ "$state_after" != "$CBS_WORKSPACE_READY" ]]; then
                echo "CBS_WORKSPACE_ERROR=POST_CREATE_VALIDATION_FAILED" >&2
                return "$CBS_WORKSPACE_RC_UNKNOWN"
            fi

            echo "CBS_WORKSPACE_STATE=READY"
            return "$CBS_WORKSPACE_RC_OK"
            ;;

        "$CBS_WORKSPACE_INVALID")
            echo "CBS_WORKSPACE_ACTION=BLOCK"
            echo "CBS_WORKSPACE_ERROR=TARGET_INVALID" >&2
            return "$CBS_WORKSPACE_RC_INVALID"
            ;;

        *)
            echo "CBS_WORKSPACE_ACTION=BLOCK"
            echo "CBS_WORKSPACE_ERROR=UNKNOWN_STATE" >&2
            return "$CBS_WORKSPACE_RC_UNKNOWN"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_workspace_ensure "${1:-}"
fi
