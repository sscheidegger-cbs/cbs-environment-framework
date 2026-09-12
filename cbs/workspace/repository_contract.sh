#!/usr/bin/env bash

CBS_REPOSITORY_CONTRACT_VERSION=1

CBS_REPOSITORY_READY="READY"
CBS_REPOSITORY_MISSING="MISSING"
CBS_REPOSITORY_NOT_GIT="NOT_GIT"
CBS_REPOSITORY_REMOTE_MISMATCH="REMOTE_MISMATCH"
CBS_REPOSITORY_UNKNOWN="UNKNOWN"

CBS_REPOSITORY_WORKTREE_CLEAN="CLEAN"
CBS_REPOSITORY_WORKTREE_DIRTY="DIRTY"
CBS_REPOSITORY_WORKTREE_UNKNOWN="UNKNOWN"

CBS_REPOSITORY_RC_OK=0
CBS_REPOSITORY_RC_MISSING=50
CBS_REPOSITORY_RC_NOT_GIT=51
CBS_REPOSITORY_RC_REMOTE_MISMATCH=52
CBS_REPOSITORY_RC_UNKNOWN=53
CBS_REPOSITORY_RC_USAGE=64

cbs_repository_state() {
    local repository_path="${1:-}"
    local expected_origin="${2:-}"

    if [[ -z "$repository_path" || -z "$expected_origin" ]]; then
        printf '%s\n' "$CBS_REPOSITORY_UNKNOWN"
        return "$CBS_REPOSITORY_RC_OK"
    fi

    if [[ ! -e "$repository_path" ]]; then
        printf '%s\n' "$CBS_REPOSITORY_MISSING"
        return "$CBS_REPOSITORY_RC_OK"
    fi

    if [[ ! -d "$repository_path" ]]; then
        printf '%s\n' "$CBS_REPOSITORY_NOT_GIT"
        return "$CBS_REPOSITORY_RC_OK"
    fi

    if ! git -C "$repository_path" \
        rev-parse --is-inside-work-tree \
        >/dev/null 2>&1
    then
        printf '%s\n' "$CBS_REPOSITORY_NOT_GIT"
        return "$CBS_REPOSITORY_RC_OK"
    fi

    local observed_origin

    observed_origin="$(
        git -C "$repository_path" \
            remote get-url origin \
            2>/dev/null ||
        true
    )"

    if [[ "$observed_origin" != "$expected_origin" ]]; then
        printf '%s\n' "$CBS_REPOSITORY_REMOTE_MISMATCH"
        return "$CBS_REPOSITORY_RC_OK"
    fi

    printf '%s\n' "$CBS_REPOSITORY_READY"
}

cbs_repository_worktree_state() {
    local repository_path="${1:-}"

    if [[ -z "$repository_path" ]]; then
        printf '%s\n' "$CBS_REPOSITORY_WORKTREE_UNKNOWN"
        return "$CBS_REPOSITORY_RC_OK"
    fi

    if ! git -C "$repository_path" \
        rev-parse --is-inside-work-tree \
        >/dev/null 2>&1
    then
        printf '%s\n' "$CBS_REPOSITORY_WORKTREE_UNKNOWN"
        return "$CBS_REPOSITORY_RC_OK"
    fi

    if [[ -z "$(
        git -C "$repository_path" status --porcelain
    )" ]]; then
        printf '%s\n' "$CBS_REPOSITORY_WORKTREE_CLEAN"
    else
        printf '%s\n' "$CBS_REPOSITORY_WORKTREE_DIRTY"
    fi
}

cbs_repository_rc_from_state() {
    local state="${1:-}"

    case "$state" in
        "$CBS_REPOSITORY_READY")
            return "$CBS_REPOSITORY_RC_OK"
            ;;
        "$CBS_REPOSITORY_MISSING")
            return "$CBS_REPOSITORY_RC_MISSING"
            ;;
        "$CBS_REPOSITORY_NOT_GIT")
            return "$CBS_REPOSITORY_RC_NOT_GIT"
            ;;
        "$CBS_REPOSITORY_REMOTE_MISMATCH")
            return "$CBS_REPOSITORY_RC_REMOTE_MISMATCH"
            ;;
        *)
            return "$CBS_REPOSITORY_RC_UNKNOWN"
            ;;
    esac
}
