#!/usr/bin/env bash

set -Eeuo pipefail

cbs_git_error() {
    printf "CBS_GIT_ERROR=%s\n" "$1" >&2
}

cbs_git_observe() {
    local repository_path="$1"

    [[ -d "$repository_path" ]] || {
        cbs_git_error "REPOSITORY_PATH_NOT_FOUND"
        return 20
    }

    git -C "$repository_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        cbs_git_error "NOT_A_GIT_REPOSITORY"
        return 21
    }

    CBS_OBSERVED_REPOSITORY_PATH="$(git -C "$repository_path" rev-parse --show-toplevel)"
    CBS_OBSERVED_BRANCH="$(git -C "$repository_path" branch --show-current)"
    CBS_OBSERVED_HEAD="$(git -C "$repository_path" rev-parse HEAD)"

    [[ -n "$CBS_OBSERVED_BRANCH" ]] || {
        cbs_git_error "DETACHED_HEAD"
        return 22
    }

    return 0
}

cbs_git_compare_context() {
    CBS_CONTEXT_DRIFT=NO

    CBS_CONTEXT_DRIFT_REPOSITORY_PATH=NO
    CBS_CONTEXT_DRIFT_BRANCH=NO

    if [[ "$CBS_CONTEXT_REPOSITORY_PATH" != "$CBS_OBSERVED_REPOSITORY_PATH" ]]; then
        CBS_CONTEXT_DRIFT=YES
        CBS_CONTEXT_DRIFT_REPOSITORY_PATH=YES
    fi

    if [[ "$CBS_CONTEXT_BRANCH" != "$CBS_OBSERVED_BRANCH" ]]; then
        CBS_CONTEXT_DRIFT=YES
        CBS_CONTEXT_DRIFT_BRANCH=YES
    fi

    return 0
}

cbs_git_observe_and_compare() {
    cbs_git_observe "$CBS_CONTEXT_REPOSITORY_PATH" || return $?
    cbs_git_compare_context
}
