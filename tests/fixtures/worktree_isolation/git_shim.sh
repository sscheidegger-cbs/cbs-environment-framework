#!/usr/bin/env bash

# TEST ONLY - Git wrapper used by the hermetic D04b-C.1 isolation tests.
#
# Installed first in PATH by tests (never by production code), it forwards to
# the real Git and, depending on CBS_SHIM_* variables, injects a controlled
# fault at an exact point of the isolation manager: a path replaced, a proof
# substituted, a lock claimed, a worktree modified, a removal that fails or is
# interrupted. Without CBS_SHIM_* variables it is a transparent pass-through.
#
# Bash 3.2 compatible: no arrays, no associative arrays.
#
#   CBS_SHIM_REAL_GIT   absolute path of the real git (required)
#   CBS_SHIM_LOG        file receiving one line per "git worktree ..." call
#   CBS_SHIM_SYNC       directory used for "hold" synchronization
#   CBS_SHIM_ADD_MODE   hold | fail-replace-moved | fail-replace-empty |
#                       fail-replace-symlink |
#                       fail-replace-worktree | dirty | head-move |
#                       source-change | proof-symlink | proof-foreign |
#                       lock-steal
#   CBS_SHIM_REMOVE_MODE fail | partial | kill-term | kill-9
#   CBS_SHIM_MUTATE     dirty | head-move | swap-copy | attach | source-branch
#   CBS_SHIM_MUTATE_AT  Nth "git for-each-ref" call that triggers the mutation
#   CBS_SHIM_MUTATE_PATH worktree path mutated by CBS_SHIM_MUTATE
#   CBS_SHIM_COMMIT2    commit used by head-move
#   CBS_SHIM_BRANCH     branch used by attach
#   CBS_SHIM_PROOF      proof file altered by proof-* modes
#   CBS_SHIM_LOCK       lock directory altered by lock-steal

set -u

REAL="${CBS_SHIM_REAL_GIT:-}"

if [[ -z "$REAL" || ! -x "$REAL" ]]; then
    echo "git shim: CBS_SHIM_REAL_GIT is not usable" >&2
    exit 98
fi

SUB=""
SUBSUB=""
GIT_C=""
LAST=""
PENULT=""

parse_arguments() {
    local arg

    for arg in "$@"; do
        PENULT="$LAST"
        LAST="$arg"
    done

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c)
                shift 2
                ;;
            -C)
                GIT_C="${2:-}"
                shift 2
                ;;
            -*)
                shift
                ;;
            *)
                SUB="$1"
                SUBSUB="${2:-}"
                return 0
                ;;
        esac
    done

    return 0
}

parse_arguments "$@"

log_worktree_call() {
    if [[ -n "${CBS_SHIM_LOG:-}" ]]; then
        printf 'worktree-%s | %s\n' "$SUBSUB" "$*" >> "$CBS_SHIM_LOG"
    fi
}

run_real() {
    "$REAL" "$@"
}

mutate_worktree() {
    local kind="$1"
    local path="$2"

    case "$kind" in
        dirty)
            printf '%s\n' "shim-untracked" > "$path/shim-untracked.txt"
            ;;
        head-move)
            "$REAL" -C "$path" checkout -q --detach "${CBS_SHIM_COMMIT2:-}"
            ;;
        attach)
            "$REAL" -C "$path" checkout -q "${CBS_SHIM_BRANCH:-}"
            ;;
        source-branch)
            "$REAL" -C "$GIT_C" branch shim-extra HEAD
            ;;
        swap-copy)
            # Same path, same content, same Git association: only the
            # directory identity changes.
            mv "$path" "$path.moved"
            cp -R "$path.moved" "$path"
            ;;
    esac
}

handle_add() {
    local path="$PENULT"
    local rc=0
    local forged

    log_worktree_call "$@"

    case "${CBS_SHIM_ADD_MODE:-}" in
        hold)
            : > "${CBS_SHIM_SYNC}/reached"
            local waited=0
            while [[ ! -e "${CBS_SHIM_SYNC}/release" ]]; do
                sleep 0.1
                waited=$((waited + 1))
                if [[ "$waited" -gt 600 ]]; then
                    exit 97
                fi
            done
            run_real "$@"
            exit $?
            ;;
        fail-replace-moved)
            mv "$path" "$path.moved"
            mkdir "$path"
            printf '%s\n' "precious" > "$path/data.txt"
            exit 1
            ;;
        fail-replace-empty)
            mv "$path" "$path.moved"
            mkdir "$path"
            exit 1
            ;;
        fail-replace-symlink)
            mv "$path" "$path.moved"
            ln -s "$path.moved" "$path"
            exit 1
            ;;
        fail-replace-worktree)
            mv "$path" "$path.moved"
            run_real "$@"
            exit 1
            ;;
    esac

    run_real "$@"
    rc=$?

    case "${CBS_SHIM_ADD_MODE:-}" in
        dirty)
            mutate_worktree dirty "$path"
            ;;
        head-move)
            mutate_worktree head-move "$path"
            ;;
        source-change)
            "$REAL" -C "$GIT_C" branch shim-extra "$LAST"
            ;;
        proof-symlink)
            mv "${CBS_SHIM_PROOF}" "${CBS_SHIM_PROOF}.orig"
            ln -s "${CBS_SHIM_PROOF}.orig" "${CBS_SHIM_PROOF}"
            ;;
        proof-foreign)
            forged="${CBS_SHIM_PROOF}.forged"
            sed -e 's#^CBS_ISOLATION_TOKEN=.*#CBS_ISOLATION_TOKEN=ffffffffffffffffffffffffffffffff#' \
                "${CBS_SHIM_PROOF}" > "$forged"
            mv "$forged" "${CBS_SHIM_PROOF}"
            ;;
        lock-steal)
            printf '%s\n' "foreign-owner" > "${CBS_SHIM_LOCK}/owner.new"
            mv "${CBS_SHIM_LOCK}/owner.new" "${CBS_SHIM_LOCK}/owner"
            ;;
    esac

    exit "$rc"
}

handle_remove() {
    local path="$LAST"

    log_worktree_call "$@"

    case "${CBS_SHIM_REMOVE_MODE:-}" in
        fail)
            exit 1
            ;;
        partial)
            rm -f "$path/file.txt"
            exit 1
            ;;
        kill-term)
            kill -TERM "$PPID"
            exit 1
            ;;
        kill-9)
            kill -KILL "$PPID"
            exit 1
            ;;
    esac

    run_real "$@"
    exit $?
}

handle_foreach() {
    local rc=0
    local counter="${CBS_SHIM_SYNC:-/nonexistent}/foreach.count"
    local count=0

    run_real "$@"
    rc=$?

    if [[ -n "${CBS_SHIM_MUTATE:-}" && -d "${CBS_SHIM_SYNC:-}" ]]; then
        if [[ -f "$counter" ]]; then
            IFS= read -r count < "$counter" || count=0
        fi

        count=$((count + 1))
        printf '%s\n' "$count" > "$counter"

        if [[ "$count" -eq "${CBS_SHIM_MUTATE_AT:-1}" ]]; then
            mutate_worktree "$CBS_SHIM_MUTATE" "${CBS_SHIM_MUTATE_PATH}"
        fi
    fi

    exit "$rc"
}

case "$SUB:$SUBSUB" in
    worktree:add)
        handle_add "$@"
        ;;
    worktree:remove)
        handle_remove "$@"
        ;;
    worktree:*)
        log_worktree_call "$@"
        run_real "$@"
        exit $?
        ;;
    for-each-ref:*)
        handle_foreach "$@"
        ;;
esac

exec "$REAL" "$@"
