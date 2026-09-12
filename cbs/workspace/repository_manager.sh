#!/usr/bin/env bash

set -Eeuo pipefail

CBS_REPOSITORY_MANAGER_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

source "$CBS_REPOSITORY_MANAGER_DIR/repository_contract.sh"

cbs_repository_ensure() {
    local repository_path="${1:-}"
    local expected_origin="${2:-}"

    if [[ -z "$repository_path" ]]; then
        echo "CBS_REPOSITORY_ERROR=REPOSITORY_PATH_REQUIRED" >&2
        return "$CBS_REPOSITORY_RC_USAGE"
    fi

    if [[ -z "$expected_origin" ]]; then
        echo "CBS_REPOSITORY_ERROR=EXPECTED_ORIGIN_REQUIRED" >&2
        return "$CBS_REPOSITORY_RC_USAGE"
    fi

    local state

    state="$(
        cbs_repository_state \
            "$repository_path" \
            "$expected_origin"
    )"

    printf 'CBS_REPOSITORY_PATH=%s\n' "$repository_path"
    printf 'CBS_REPOSITORY_EXPECTED_ORIGIN=%s\n' "$expected_origin"
    printf 'CBS_REPOSITORY_STATE_BEFORE=%s\n' "$state"

    case "$state" in
        "$CBS_REPOSITORY_READY")
            echo "CBS_REPOSITORY_ACTION=REUSE"
            echo "CBS_REPOSITORY_STATE=READY"
            return "$CBS_REPOSITORY_RC_OK"
            ;;

        "$CBS_REPOSITORY_MISSING")
            local parent

            parent="$(dirname "$repository_path")"

            if [[ ! -d "$parent" ]]; then
                echo "CBS_REPOSITORY_ERROR=PARENT_DIRECTORY_MISSING" >&2
                echo "CBS_REPOSITORY_PARENT=$parent" >&2
                return "$CBS_REPOSITORY_RC_MISSING"
            fi

            echo "CBS_REPOSITORY_ACTION=CLONE"

            if ! git clone \
                -- \
                "$expected_origin" \
                "$repository_path"
            then
                echo "CBS_REPOSITORY_ERROR=CLONE_FAILED" >&2
                return "$CBS_REPOSITORY_RC_UNKNOWN"
            fi

            local state_after

            state_after="$(
                cbs_repository_state \
                    "$repository_path" \
                    "$expected_origin"
            )"

            printf 'CBS_REPOSITORY_STATE_AFTER=%s\n' "$state_after"

            if [[ "$state_after" != "$CBS_REPOSITORY_READY" ]]; then
                echo "CBS_REPOSITORY_ERROR=POST_CLONE_VALIDATION_FAILED" >&2
                return "$CBS_REPOSITORY_RC_UNKNOWN"
            fi

            echo "CBS_REPOSITORY_STATE=READY"
            return "$CBS_REPOSITORY_RC_OK"
            ;;

        "$CBS_REPOSITORY_NOT_GIT")
            echo "CBS_REPOSITORY_ACTION=BLOCK"
            echo "CBS_REPOSITORY_ERROR=TARGET_NOT_GIT" >&2
            return "$CBS_REPOSITORY_RC_NOT_GIT"
            ;;

        "$CBS_REPOSITORY_REMOTE_MISMATCH")
            echo "CBS_REPOSITORY_ACTION=BLOCK"
            echo "CBS_REPOSITORY_ERROR=REMOTE_MISMATCH" >&2
            return "$CBS_REPOSITORY_RC_REMOTE_MISMATCH"
            ;;

        *)
            echo "CBS_REPOSITORY_ACTION=BLOCK"
            echo "CBS_REPOSITORY_ERROR=UNKNOWN_STATE" >&2
            return "$CBS_REPOSITORY_RC_UNKNOWN"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_repository_ensure \
        "${1:-}" \
        "${2:-}"
fi
