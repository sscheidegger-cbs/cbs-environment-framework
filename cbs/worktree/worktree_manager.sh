#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/cbs/worktree/worktree_observer.sh"

cbs_worktree_find_branch_path() {
    local repository="${1:-}"
    local branch="${2:-}"

    [[ -n "$repository" ]] || return "$CBS_RC_WORKTREE_USAGE"
    [[ -n "$branch" ]] || return "$CBS_RC_WORKTREE_USAGE"

    git -C "$repository" worktree list --porcelain |
        awk -v branch="refs/heads/$branch" '
            /^worktree / {
                path = substr($0, 10)
            }
            /^branch / {
                ref = substr($0, 8)
                if (ref == branch) {
                    print path
                    exit
                }
            }
        '
}

cbs_worktree_classify_request() {
    local repository="${1:-}"
    local path="${2:-}"
    local branch="${3:-}"

    if ! cbs_worktree_repository_valid "$repository"; then
        printf '%s\n' "$CBS_WORKTREE_STATE_INVALID_REPOSITORY"
        return 0
    fi

    if [[ -e "$path" ]]; then
        if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local observed_top
            local observed_branch

            observed_top="$(git -C "$path" rev-parse --show-toplevel)"
            observed_branch="$(git -C "$path" branch --show-current || true)"

            if [[ "$observed_top" == "$path" && "$observed_branch" == "$branch" ]]; then
                printf '%s\n' "$CBS_WORKTREE_STATE_READY"
            else
                printf '%s\n' "$CBS_WORKTREE_STATE_PATH_CONFLICT"
            fi
        else
            printf '%s\n' "$CBS_WORKTREE_STATE_PATH_CONFLICT"
        fi

        return 0
    fi

    local existing_branch_path
    existing_branch_path="$(
        cbs_worktree_find_branch_path "$repository" "$branch"
    )"

    if [[ -n "$existing_branch_path" ]]; then
        printf '%s\n' "$CBS_WORKTREE_STATE_BRANCH_CONFLICT"
        return 0
    fi

    printf '%s\n' "$CBS_WORKTREE_STATE_MISSING"
}

cbs_worktree_ensure() {
    local repository="${1:-}"
    local path="${2:-}"
    local branch="${3:-}"

    if [[ -z "$repository" || -z "$path" || -z "$branch" ]]; then
        echo "CBS_WORKTREE_ERROR=USAGE" >&2
        return "$CBS_RC_WORKTREE_USAGE"
    fi

    local state
    state="$(
        cbs_worktree_classify_request \
            "$repository" \
            "$path" \
            "$branch"
    )"

    echo "CBS_WORKTREE_REPOSITORY=$repository"
    echo "CBS_WORKTREE_PATH=$path"
    echo "CBS_WORKTREE_BRANCH=$branch"
    echo "CBS_WORKTREE_STATE_BEFORE=$state"

    case "$state" in
        "$CBS_WORKTREE_STATE_READY")
            echo "CBS_WORKTREE_ACTION=$CBS_WORKTREE_ACTION_REUSE"
            echo "CBS_WORKTREE_STATE=$CBS_WORKTREE_STATE_READY"
            return 0
            ;;

        "$CBS_WORKTREE_STATE_MISSING")
            local parent
            parent="$(dirname "$path")"

            if [[ ! -d "$parent" ]]; then
                echo "CBS_WORKTREE_ERROR=PARENT_DIRECTORY_MISSING" >&2
                return "$CBS_RC_WORKTREE_PATH_CONFLICT"
            fi

            if ! git -C "$repository" show-ref --verify --quiet "refs/heads/$branch"; then
                echo "CBS_WORKTREE_ERROR=BRANCH_NOT_FOUND" >&2
                return "$CBS_RC_WORKTREE_BRANCH_CONFLICT"
            fi

            git -C "$repository" worktree add "$path" "$branch" >/dev/null

            echo "CBS_WORKTREE_ACTION=$CBS_WORKTREE_ACTION_CREATE"
            echo "CBS_WORKTREE_STATE=$CBS_WORKTREE_STATE_READY"
            return 0
            ;;

        "$CBS_WORKTREE_STATE_BRANCH_CONFLICT")
            echo "CBS_WORKTREE_ACTION=$CBS_WORKTREE_ACTION_BLOCK"
            echo "CBS_WORKTREE_STATE=$CBS_WORKTREE_STATE_BRANCH_CONFLICT"
            return "$CBS_RC_WORKTREE_BRANCH_CONFLICT"
            ;;

        "$CBS_WORKTREE_STATE_PATH_CONFLICT")
            echo "CBS_WORKTREE_ACTION=$CBS_WORKTREE_ACTION_BLOCK"
            echo "CBS_WORKTREE_STATE=$CBS_WORKTREE_STATE_PATH_CONFLICT"
            return "$CBS_RC_WORKTREE_PATH_CONFLICT"
            ;;

        "$CBS_WORKTREE_STATE_INVALID_REPOSITORY")
            echo "CBS_WORKTREE_ACTION=$CBS_WORKTREE_ACTION_BLOCK"
            echo "CBS_WORKTREE_STATE=$CBS_WORKTREE_STATE_INVALID_REPOSITORY"
            return "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
            ;;

        *)
            echo "CBS_WORKTREE_ACTION=$CBS_WORKTREE_ACTION_BLOCK"
            echo "CBS_WORKTREE_STATE=$CBS_WORKTREE_STATE_UNKNOWN"
            return "$CBS_RC_WORKTREE_UNKNOWN"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_worktree_ensure \
        "${1:-}" \
        "${2:-}" \
        "${3:-}"
fi
