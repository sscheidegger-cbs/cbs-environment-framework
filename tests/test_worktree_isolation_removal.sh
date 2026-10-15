#!/usr/bin/env bash

# D04b-C.1 safety regression: the removal performed by a cleanup.
#
#  - the Git invariants are revalidated immediately before the removal;
#  - the removal is never forced;
#  - a failed cleanup never causes any additional deletion.
#
# The mutations are injected by a test-only Git shim, triggered by the Nth
# "git for-each-ref" call: in a cleanup, the 1st call belongs to the source
# snapshot taken after the first verification and before the removal, the 2nd
# call to the snapshot taken after the removal.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_REMOVAL"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

iso_fixture_init
iso_shim_init

echo "${TEST_PREFIX}_FIXTURE=PASS"

PROOF_DIR="$ISO_ROOT/.cbs-isolation"

create_ok() {
    iso_run create "$1" "$SOURCE" "$ISO_ORIGIN" "$2" "$ISO_ROOT"
    iso_expect_pass "SETUP_CREATE_$1"
}

create_ok bystander "$C2"
git -C "$SOURCE" worktree add --detach "$ISO_ROOT/foreign-wt" "$C1" >/dev/null 2>&1

root_fingerprint() {
    # Whole authorized root: names and checksums.
    (cd "$ISO_ROOT" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} \; | LC_ALL=C sort)
}

# mutated_cleanup <id> <kind> [at]
mutated_cleanup() {
    local id="$1"
    local kind="$2"
    local at="${3:-1}"

    iso_shim_reset
    export CBS_SHIM_MUTATE="$kind"
    export CBS_SHIM_MUTATE_AT="$at"
    export CBS_SHIM_MUTATE_PATH="$ISO_ROOT/$id"
    export CBS_SHIM_COMMIT2="$C2"
    export CBS_SHIM_BRANCH="dev-branch"

    iso_run_shim cleanup "$id" "$SOURCE" "$ISO_ROOT"

    unset CBS_SHIM_MUTATE CBS_SHIM_MUTATE_AT CBS_SHIM_MUTATE_PATH
    unset CBS_SHIM_COMMIT2 CBS_SHIM_BRANCH

    if iso_shim_saw_force; then
        iso_fail "FORCE_OPTION_USED_${id}"
    fi
}

assert_bystanders_intact() {
    local label="$1"

    [[ -d "$ISO_ROOT/bystander" ]] || iso_fail "${label}_BYSTANDER_REMOVED"
    iso_is_registered "$ISO_ROOT/bystander" || iso_fail "${label}_BYSTANDER_UNREGISTERED"
    [[ -d "$ISO_ROOT/foreign-wt" ]] || iso_fail "${label}_FOREIGN_REMOVED"
    iso_is_registered "$ISO_ROOT/foreign-wt" || iso_fail "${label}_FOREIGN_UNREGISTERED"
}

iso_snapshot_source
BYSTANDER_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/bystander")"

# ---------------------------------------------------------------- 5. revalidation right before the removal

# HEAD moves to another commit AFTER the first verification, tree still clean:
# a plain "git worktree remove" would delete it.
create_ok rv-head "$C1"
mutated_cleanup rv-head head-move
iso_expect_blocked "REVALIDATE_HEAD" "HEAD_MISMATCH" 68
[[ "$(iso_shim_count remove)" == "0" ]] || iso_fail "REVALIDATE_HEAD_REMOVE_CALLED"
[[ "$(git -C "$ISO_ROOT/rv-head" rev-parse HEAD)" == "$C2" ]] || iso_fail "REVALIDATE_HEAD_CHANGED"
iso_is_registered "$ISO_ROOT/rv-head" || iso_fail "REVALIDATE_HEAD_UNREGISTERED"
[[ ! -e "$PROOF_DIR/rv-head.cleaned" ]] || iso_fail "REVALIDATE_HEAD_RECORDED"

# HEAD re-attached to a branch at the same commit AFTER the first verification:
# a plain removal would also succeed.
create_ok rv-attach "$C2"
mutated_cleanup rv-attach attach
iso_expect_blocked "REVALIDATE_ATTACH" "NOT_DETACHED" 68
[[ "$(iso_shim_count remove)" == "0" ]] || iso_fail "REVALIDATE_ATTACH_REMOVE_CALLED"
[[ "$(git -C "$ISO_ROOT/rv-attach" branch --show-current)" == "dev-branch" ]] || iso_fail "REVALIDATE_ATTACH_CHANGED"
iso_is_registered "$ISO_ROOT/rv-attach" || iso_fail "REVALIDATE_ATTACH_UNREGISTERED"

# Untracked content appears AFTER the first verification.
create_ok rv-dirty "$C1"
mutated_cleanup rv-dirty dirty
iso_expect_blocked "REVALIDATE_DIRTY" "WORKTREE_DIRTY" 68
[[ "$(iso_shim_count remove)" == "0" ]] || iso_fail "REVALIDATE_DIRTY_REMOVE_CALLED"
[[ -f "$ISO_ROOT/rv-dirty/shim-untracked.txt" ]] || iso_fail "REVALIDATE_DIRTY_CONTENT_REMOVED"

# The path is replaced by an identical copy AFTER the first verification:
# same path, same content, same Git association, different directory.
create_ok rv-swap "$C1"
mutated_cleanup rv-swap swap-copy
iso_expect_blocked "REVALIDATE_SWAP" "PATH_IDENTITY_MISMATCH" 67
[[ "$(iso_shim_count remove)" == "0" ]] || iso_fail "REVALIDATE_SWAP_REMOVE_CALLED"
[[ -d "$ISO_ROOT/rv-swap" && -d "$ISO_ROOT/rv-swap.moved" ]] || iso_fail "REVALIDATE_SWAP_REMOVED"
iso_is_registered "$ISO_ROOT/rv-swap" || iso_fail "REVALIDATE_SWAP_UNREGISTERED"

assert_bystanders_intact "REVALIDATE"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/bystander")" == "$BYSTANDER_BEFORE" ]] || iso_fail "REVALIDATE_BYSTANDER_CHANGED"
iso_assert_source_untouched "REVALIDATE_SOURCE"

iso_pass "REVALIDATE_BEFORE_REMOVAL"

# ---------------------------------------------------------------- the removal is a plain, exact, single removal

create_ok plain "$C1"
PLAIN_PATH="$ISO_ROOT/plain"

iso_shim_reset
iso_run_shim cleanup plain "$SOURCE" "$ISO_ROOT"
iso_expect_pass "PLAIN_CLEANUP"
[[ "$(iso_shim_count remove)" == "1" ]] || iso_fail "PLAIN_REMOVE_COUNT_$(iso_shim_count remove)"
iso_shim_saw_force && iso_fail "PLAIN_FORCE"
grep -Fq "worktree-remove | " "$CBS_SHIM_LOG" || iso_fail "PLAIN_REMOVE_LOGGED"
[[ "$(grep '^worktree-remove ' "$CBS_SHIM_LOG" | grep -c " $PLAIN_PATH\$" || true)" == "1" ]] ||
    iso_fail "PLAIN_REMOVE_PATH"
[[ "$(iso_shim_count prune)" == "0" ]] || iso_fail "PLAIN_PRUNE"
[[ ! -e "$PLAIN_PATH" ]] || iso_fail "PLAIN_PATH_REMAINS"

iso_pass "REMOVAL_PLAIN_AND_EXACT"

# ---------------------------------------------------------------- 7. a failed cleanup deletes nothing more

# Git refuses the removal.
create_ok fail-a "$C2"
BEFORE="$(root_fingerprint)"

iso_shim_reset
export CBS_SHIM_REMOVE_MODE="fail"
iso_run_shim cleanup fail-a "$SOURCE" "$ISO_ROOT"
unset CBS_SHIM_REMOVE_MODE

iso_expect_failed "FAILED_REMOVAL" "WORKTREE_REMOVE_FAILED" 69
[[ "$(iso_shim_count remove)" == "1" ]] || iso_fail "FAILED_REMOVAL_REMOVE_COUNT"
iso_shim_saw_force && iso_fail "FAILED_REMOVAL_FORCE"
[[ "$(root_fingerprint)" == "$BEFORE" ]] || iso_fail "FAILED_REMOVAL_TREE_CHANGED"
[[ ! -e "$PROOF_DIR/fail-a.cleaned" ]] || iso_fail "FAILED_REMOVAL_RECORDED"
[[ ! -e "$ISO_ROOT/.cbs-isolation.lock" ]] || iso_fail "FAILED_REMOVAL_LOCK_REMAINS"
iso_is_registered "$ISO_ROOT/fail-a" || iso_fail "FAILED_REMOVAL_UNREGISTERED"

# The resource is still cleanable once the failure cause is gone.
iso_shim_reset
iso_run_shim cleanup fail-a "$SOURCE" "$ISO_ROOT"
iso_expect_pass "FAILED_REMOVAL_RETRY"

# Git removes part of the worktree then fails: no retry, no rmdir, no sweep.
create_ok fail-b "$C2"
iso_shim_reset
export CBS_SHIM_REMOVE_MODE="partial"
iso_run_shim cleanup fail-b "$SOURCE" "$ISO_ROOT"
unset CBS_SHIM_REMOVE_MODE

iso_expect_failed "PARTIAL_REMOVAL" "WORKTREE_REMOVE_FAILED" 69
[[ "$(iso_shim_count remove)" == "1" ]] || iso_fail "PARTIAL_REMOVAL_REMOVE_COUNT"
[[ ! -e "$ISO_ROOT/fail-b/file.txt" ]] || iso_fail "PARTIAL_REMOVAL_PRECONDITION"
[[ -f "$ISO_ROOT/fail-b/extra.txt" ]] || iso_fail "PARTIAL_REMOVAL_SWEPT_CONTENT"
[[ -e "$ISO_ROOT/fail-b/.git" ]] || iso_fail "PARTIAL_REMOVAL_SWEPT_GIT_FILE"
iso_is_registered "$ISO_ROOT/fail-b" || iso_fail "PARTIAL_REMOVAL_UNREGISTERED"
grep -Fxq "CBS_ISOLATION_STATE=READY" "$PROOF_DIR/fail-b.proof" || iso_fail "PARTIAL_REMOVAL_PROOF_CHANGED"
[[ ! -e "$PROOF_DIR/fail-b.cleaned" ]] || iso_fail "PARTIAL_REMOVAL_RECORDED"

# A second attempt on the damaged resource is refused, with no removal call.
iso_shim_reset
iso_run_shim cleanup fail-b "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "PARTIAL_REMOVAL_RETRY" "WORKTREE_DIRTY" 68
[[ "$(iso_shim_count remove)" == "0" ]] || iso_fail "PARTIAL_REMOVAL_RETRY_REMOVE_CALLED"
[[ -f "$ISO_ROOT/fail-b/extra.txt" ]] || iso_fail "PARTIAL_REMOVAL_RETRY_DELETED"

# Locked worktree (real Git refusal): never escalated to a forced removal.
create_ok fail-c "$C1"
git -C "$SOURCE" worktree lock "$ISO_ROOT/fail-c"
C_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/fail-c")"

iso_shim_reset
iso_run_shim cleanup fail-c "$SOURCE" "$ISO_ROOT"
iso_expect_failed "LOCKED_WORKTREE" "WORKTREE_REMOVE_FAILED" 69
[[ "$(iso_shim_count remove)" == "1" ]] || iso_fail "LOCKED_REMOVE_COUNT"
iso_shim_saw_force && iso_fail "LOCKED_FORCE"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/fail-c")" == "$C_BEFORE" ]] || iso_fail "LOCKED_CHANGED"
iso_is_registered "$ISO_ROOT/fail-c" || iso_fail "LOCKED_UNREGISTERED"
[[ ! -e "$PROOF_DIR/fail-c.cleaned" ]] || iso_fail "LOCKED_RECORDED"

# A failure AFTER the removal (source changed while cleaning: the branch is
# created right after the first snapshot): nothing else is removed, the proof
# is kept, no retry deletes anything.
create_ok fail-d "$C1"
mutated_cleanup fail-d source-branch 1
iso_expect_failed "SOURCE_CHANGED_AFTER_REMOVAL" "SOURCE_CHANGED" 68
[[ "$(iso_shim_count remove)" == "1" ]] || iso_fail "AFTER_REMOVAL_REMOVE_COUNT"
[[ ! -e "$ISO_ROOT/fail-d" ]] || iso_fail "AFTER_REMOVAL_PATH_REMAINS"
[[ -f "$PROOF_DIR/fail-d.proof" ]] || iso_fail "AFTER_REMOVAL_PROOF_REMOVED"
assert_bystanders_intact "AFTER_REMOVAL"
git -C "$SOURCE" branch -D shim-extra >/dev/null 2>&1
iso_snapshot_source

iso_shim_reset
iso_run_shim cleanup fail-d "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "AFTER_REMOVAL_RETRY" "PATH_MISSING" 61
[[ "$(iso_shim_count remove)" == "0" ]] || iso_fail "AFTER_REMOVAL_RETRY_REMOVE_CALLED"

assert_bystanders_intact "FAILED_CLEANUPS"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/bystander")" == "$BYSTANDER_BEFORE" ]] || iso_fail "FAILED_CLEANUPS_BYSTANDER_CHANGED"
iso_assert_source_untouched "FAILED_CLEANUPS_SOURCE"

iso_pass "FAILED_CLEANUP_NO_EXTRA_DELETION"

echo "${TEST_PREFIX}_RESULT=PASS"
