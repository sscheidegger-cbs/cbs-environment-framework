#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/worktree/contract.sh"

cbs_worktree_repository_valid() {
    local repository="${1:-}"

    [[ -n "$repository" ]] || return 1
    [[ -d "$repository" ]] || return 1

    git -C "$repository" rev-parse --is-inside-work-tree \
        >/dev/null 2>&1
}

cbs_worktree_list_paths() {
    local repository="${1:-}"

    cbs_worktree_repository_valid "$repository" ||
        return "$CBS_RC_WORKTREE_INVALID_REPOSITORY"

    git -C "$repository" worktree list --porcelain |
        sed -n 's/^worktree //p'
}

cbs_worktree_branch_state() {
    local path="${1:-}"

    if [[ -z "$path" || ! -e "$path" ]]; then
        printf '%s\n' "$CBS_WORKTREE_BRANCH_ABSENT"
        return 0
    fi

    local branch
    branch="$(
        git -C "$path" branch --show-current 2>/dev/null || true
    )"

    if [[ -n "$branch" ]]; then
        printf '%s\n' "$CBS_WORKTREE_BRANCH_ATTACHED"
    elif git -C "$path" rev-parse HEAD >/dev/null 2>&1; then
        printf '%s\n' "$CBS_WORKTREE_BRANCH_DETACHED"
    else
        printf '%s\n' "$CBS_WORKTREE_BRANCH_UNKNOWN"
    fi
}

cbs_worktree_worktree_state() {
    local path="${1:-}"

    if [[ -z "$path" || ! -e "$path" ]]; then
        printf '%s\n' "ABSENT"
        return 0
    fi

    if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
        printf '%s\n' "DIRTY"
    else
        printf '%s\n' "CLEAN"
    fi
}

cbs_worktree_observe() {
    local repository="${1:-}"

    if [[ -z "$repository" ]]; then
        echo "CBS_WORKTREE_ERROR=REPOSITORY_REQUIRED" >&2
        return "$CBS_RC_WORKTREE_USAGE"
    fi

    if ! cbs_worktree_repository_valid "$repository"; then
        echo "CBS_WORKTREE_REPOSITORY=$repository"
        echo "CBS_WORKTREE_STATE=$CBS_WORKTREE_STATE_INVALID_REPOSITORY"
        return "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
    fi

    local count=0
    local path
    local branch
    local head
    local branch_state
    local state

    echo "CBS_WORKTREE_REPOSITORY=$repository"

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue

        count=$((count + 1))

        branch="$(
            git -C "$path" branch --show-current 2>/dev/null || true
        )"

        head="$(
            git -C "$path" rev-parse HEAD 2>/dev/null || true
        )"

        branch_state="$(cbs_worktree_branch_state "$path")"
        state="$(cbs_worktree_worktree_state "$path")"

        echo "CBS_WORKTREE_INDEX=$count"
        echo "CBS_WORKTREE_PATH=$path"
        echo "CBS_WORKTREE_BRANCH_STATE=$branch_state"

        if [[ -n "$branch" ]]; then
            echo "CBS_WORKTREE_BRANCH=$branch"
        else
            echo "CBS_WORKTREE_BRANCH=DETACHED"
        fi

        echo "CBS_WORKTREE_HEAD=$head"
        echo "CBS_WORKTREE_WORKTREE_STATE=$state"

    done < <(cbs_worktree_list_paths "$repository")

    echo "CBS_WORKTREE_COUNT=$count"
    echo "CBS_WORKTREE_OBSERVATION_RESULT=PASS"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_worktree_observe "${1:-}"
fi

cbs_worktree_decide() {
    local path_state="${1:-}"
    local branch_state="${2:-}"

    case "$path_state:$branch_state" in
        READY:ATTACHED)
            printf '%s\n' "$CBS_WORKTREE_ACTION_REUSE"
            ;;
        MISSING:ABSENT)
            printf '%s\n' "$CBS_WORKTREE_ACTION_CREATE"
            ;;
        READY:DETACHED|READY:UNKNOWN)
            printf '%s\n' "$CBS_WORKTREE_ACTION_BLOCK"
            ;;
        PATH_CONFLICT:*)
            printf '%s\n' "$CBS_WORKTREE_ACTION_BLOCK"
            ;;
        BRANCH_CONFLICT:*)
            printf '%s\n' "$CBS_WORKTREE_ACTION_BLOCK"
            ;;
        INVALID_REPOSITORY:*)
            printf '%s\n' "$CBS_WORKTREE_ACTION_BLOCK"
            ;;
        *)
            printf '%s\n' "$CBS_WORKTREE_ACTION_BLOCK"
            ;;
    esac
}
