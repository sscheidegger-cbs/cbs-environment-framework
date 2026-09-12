#!/usr/bin/env bash

set -Eeuo pipefail

CBS_WORKSPACE_OBSERVER_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

source "$CBS_WORKSPACE_OBSERVER_DIR/contract.sh"
source "$CBS_WORKSPACE_OBSERVER_DIR/repository_contract.sh"

cbs_workspace_observe() {
    local workspace_path="${1:-}"
    local repository_path="${2:-}"
    local expected_origin="${3:-}"

    if [[ -z "$workspace_path" ]]; then
        echo "CBS_WORKSPACE_ERROR=WORKSPACE_PATH_REQUIRED" >&2
        return "$CBS_WORKSPACE_RC_USAGE"
    fi

    if [[ -z "$repository_path" ]]; then
        echo "CBS_WORKSPACE_ERROR=REPOSITORY_PATH_REQUIRED" >&2
        return "$CBS_WORKSPACE_RC_USAGE"
    fi

    if [[ -z "$expected_origin" ]]; then
        echo "CBS_WORKSPACE_ERROR=EXPECTED_ORIGIN_REQUIRED" >&2
        return "$CBS_WORKSPACE_RC_USAGE"
    fi

    local workspace_class
    local workspace_state
    local repository_state
    local repository_worktree_state

    workspace_class="$(
        cbs_workspace_classify_path "$workspace_path"
    )"

    workspace_state="$(
        cbs_workspace_state_from_path_class "$workspace_class"
    )"

    repository_state="$(
        cbs_repository_state \
            "$repository_path" \
            "$expected_origin"
    )"

    repository_worktree_state="$(
        cbs_repository_worktree_state \
            "$repository_path"
    )"

    printf 'CBS_WORKSPACE_PATH=%s\n' "$workspace_path"
    printf 'CBS_WORKSPACE_PATH_CLASS=%s\n' "$workspace_class"
    printf 'CBS_WORKSPACE_STATE=%s\n' "$workspace_state"

    printf 'CBS_REPOSITORY_PATH=%s\n' "$repository_path"
    printf 'CBS_REPOSITORY_EXPECTED_ORIGIN=%s\n' "$expected_origin"

    if git -C "$repository_path" \
        rev-parse --is-inside-work-tree \
        >/dev/null 2>&1
    then
        local observed_toplevel
        local observed_origin
        local observed_branch
        local observed_head

        observed_toplevel="$(
            git -C "$repository_path" rev-parse --show-toplevel
        )"

        observed_origin="$(
            git -C "$repository_path" \
                remote get-url origin \
                2>/dev/null ||
            true
        )"

        observed_branch="$(
            git -C "$repository_path" branch --show-current
        )"

        observed_head="$(
            git -C "$repository_path" rev-parse HEAD
        )"

        printf 'CBS_REPOSITORY_TOPLEVEL=%s\n' "$observed_toplevel"
        printf 'CBS_REPOSITORY_OBSERVED_ORIGIN=%s\n' "$observed_origin"
        printf 'CBS_REPOSITORY_BRANCH=%s\n' "$observed_branch"
        printf 'CBS_REPOSITORY_HEAD=%s\n' "$observed_head"
    fi

    printf 'CBS_REPOSITORY_WORKTREE_STATE=%s\n' \
        "$repository_worktree_state"

    printf 'CBS_REPOSITORY_STATE=%s\n' \
        "$repository_state"

    if [[ "$workspace_state" != "$CBS_WORKSPACE_READY" ]]; then
        cbs_workspace_rc_from_state "$workspace_state"
        return $?
    fi

    cbs_repository_rc_from_state "$repository_state"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_workspace_observe \
        "${1:-}" \
        "${2:-}" \
        "${3:-}"
fi
