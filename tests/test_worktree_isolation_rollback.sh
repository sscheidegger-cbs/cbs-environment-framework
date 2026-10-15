#!/usr/bin/env bash

# D04b-C.1 safety regression: the rollback of a failed creation.
#
# Faults are injected with a test-only Git shim (see fixtures). The rollback
# may only remove a resource whose identity and CBS ownership are proven, and
# never with a forced removal.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_ROLLBACK"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

iso_fixture_init
iso_shim_init

echo "${TEST_PREFIX}_FIXTURE=PASS"

PROOF_DIR="$ISO_ROOT/.cbs-isolation"
LOCK_DIR="$ISO_ROOT/.cbs-isolation.lock"
FOREIGN_TOKEN="ffffffffffffffffffffffffffffffff"

# A genuine CBS resource and a foreign worktree that no rollback may touch.
iso_run create canary "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_pass "SETUP_CANARY"
git -C "$SOURCE" worktree add --detach "$ISO_ROOT/foreign-wt" "$C2" >/dev/null 2>&1

CANARY_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/canary")"
FOREIGN_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/foreign-wt")"
iso_snapshot_source

assert_bystanders_intact() {
    local label="$1"

    [[ "$(iso_tree_fingerprint "$ISO_ROOT/canary")" == "$CANARY_BEFORE" ]] ||
        iso_fail "${label}_CANARY_CHANGED"
    [[ "$(iso_tree_fingerprint "$ISO_ROOT/foreign-wt")" == "$FOREIGN_BEFORE" ]] ||
        iso_fail "${label}_FOREIGN_CHANGED"
    iso_is_registered "$ISO_ROOT/canary" || iso_fail "${label}_CANARY_UNREGISTERED"
    iso_is_registered "$ISO_ROOT/foreign-wt" || iso_fail "${label}_FOREIGN_UNREGISTERED"
}

# fault_create <add-mode> <id> <commit>
fault_create() {
    local mode="$1"
    local id="$2"
    local commit="$3"

    iso_shim_reset
    export CBS_SHIM_ADD_MODE="$mode"
    export CBS_SHIM_PROOF="$PROOF_DIR/$id.proof"
    export CBS_SHIM_LOCK="$LOCK_DIR"
    export CBS_SHIM_COMMIT2="$C2"

    iso_run_shim create "$id" "$SOURCE" "$ISO_ORIGIN" "$commit" "$ISO_ROOT"

    # No forced operation, whatever happened.
    if iso_shim_saw_force; then
        iso_fail "FORCE_OPTION_USED_$id"
    fi

    unset CBS_SHIM_ADD_MODE CBS_SHIM_PROOF CBS_SHIM_LOCK CBS_SHIM_COMMIT2
}

assert_rollback_refused() {
    local label="$1"
    local reason="$2"

    [[ "$(iso_value ROLLBACK)" == "INCOMPLETE" ]] ||
        iso_fail "${label}_ROLLBACK_FIELD_$(iso_value ROLLBACK)"
    [[ "$(iso_value ROLLBACK_REASON)" == "$reason" ]] ||
        iso_fail "${label}_ROLLBACK_REASON_$(iso_value ROLLBACK_REASON)"
    [[ "$(iso_shim_count remove)" == "0" ]] ||
        iso_fail "${label}_REMOVE_CALLED"
}

# ---------------------------------------------------------------- 1. legitimate rollback, never forced

# The worktree is created, then the source changes: the creation fails after
# the worktree exists. The resource is CBS-owned, clean and unchanged: it is
# rolled back with a NON forced removal.
fault_create source-change legit "$C1"
iso_expect_failed "LEGIT" "SOURCE_CHANGED" 68
[[ "$(iso_value ROLLBACK)" == "DONE" ]] || iso_fail "LEGIT_ROLLBACK_$(iso_value ROLLBACK)"
[[ "$(iso_value ROLLBACK_REASON)" == "NONE" ]] || iso_fail "LEGIT_ROLLBACK_REASON"
[[ ! -e "$ISO_ROOT/legit" && ! -L "$ISO_ROOT/legit" ]] || iso_fail "LEGIT_PATH_REMAINS"
iso_is_registered "$ISO_ROOT/legit" && iso_fail "LEGIT_STILL_REGISTERED"
[[ "$(iso_shim_count remove)" == "1" ]] || iso_fail "LEGIT_REMOVE_COUNT_$(iso_shim_count remove)"
grep -Fxq "CBS_ISOLATION_STATE=ABORTED" "$PROOF_DIR/legit.proof" || iso_fail "LEGIT_PROOF_STATE"
[[ ! -e "$LOCK_DIR" ]] || iso_fail "LEGIT_LOCK_REMAINS"
assert_bystanders_intact "LEGIT"

# Branch added by the shim to simulate the concurrent change of the source.
git -C "$SOURCE" branch -D shim-extra >/dev/null 2>&1
iso_snapshot_source

iso_pass "ROLLBACK_NEVER_FORCED"

# ---------------------------------------------------------------- 2/3. modified resource: rollback refused

# Untracked content appeared in the new worktree: a forced removal would have
# deleted it.
fault_create dirty r-dirty "$C1"
iso_expect_failed "DIRTY" "WORKTREE_DIRTY" 68
assert_rollback_refused "DIRTY" "WORKTREE_DIRTY"
[[ -f "$ISO_ROOT/r-dirty/shim-untracked.txt" ]] || iso_fail "DIRTY_CONTENT_REMOVED"
iso_is_registered "$ISO_ROOT/r-dirty" || iso_fail "DIRTY_UNREGISTERED"
grep -Fxq "CBS_ISOLATION_STATE=ABORTED" "$PROOF_DIR/r-dirty.proof" || iso_fail "DIRTY_PROOF_STATE"
assert_bystanders_intact "DIRTY"

# HEAD moved to another commit by someone else, tree still clean: Git alone
# would accept to remove it.
fault_create head-move r-head "$C1"
iso_expect_failed "HEAD_MOVED" "HEAD_MISMATCH" 68
assert_rollback_refused "HEAD_MOVED" "HEAD_MISMATCH"
[[ "$(git -C "$ISO_ROOT/r-head" rev-parse HEAD)" == "$C2" ]] || iso_fail "HEAD_MOVED_CHANGED"
iso_is_registered "$ISO_ROOT/r-head" || iso_fail "HEAD_MOVED_UNREGISTERED"
assert_bystanders_intact "HEAD_MOVED"

iso_assert_source_untouched "MODIFIED_SOURCE"

iso_pass "ROLLBACK_REFUSED_MODIFIED"

# ---------------------------------------------------------------- 3. replaced path: rollback refused

# Path replaced by another non-empty directory.
fault_create fail-replace-moved r-moved "$C1"
iso_expect_failed "REPLACED_DIR" "GIT_WORKTREE_ADD_FAILED" 69
assert_rollback_refused "REPLACED_DIR" "PATH_REPLACED"
[[ "$(cat "$ISO_ROOT/r-moved/data.txt")" == "precious" ]] || iso_fail "REPLACED_DIR_CONTENT"
[[ -d "$ISO_ROOT/r-moved.moved" ]] || iso_fail "REPLACED_DIR_ORIGINAL_GONE"

# Path replaced by another EMPTY directory: an rmdir would have succeeded.
fault_create fail-replace-empty r-empty "$C1"
iso_expect_failed "REPLACED_EMPTY" "GIT_WORKTREE_ADD_FAILED" 69
assert_rollback_refused "REPLACED_EMPTY" "PATH_REPLACED"
[[ -d "$ISO_ROOT/r-empty" && ! -L "$ISO_ROOT/r-empty" ]] || iso_fail "REPLACED_EMPTY_REMOVED"

# Path replaced by a symlink.
fault_create fail-replace-symlink r-link "$C1"
iso_expect_failed "REPLACED_SYMLINK" "GIT_WORKTREE_ADD_FAILED" 69
assert_rollback_refused "REPLACED_SYMLINK" "PATH_SYMLINK"
[[ -L "$ISO_ROOT/r-link" ]] || iso_fail "REPLACED_SYMLINK_REMOVED"
[[ -d "$ISO_ROOT/r-link.moved" ]] || iso_fail "REPLACED_SYMLINK_TARGET_GONE"

# Path replaced by ANOTHER registered, clean worktree at the expected commit.
fault_create fail-replace-worktree r-wt "$C1"
iso_expect_failed "REPLACED_WORKTREE" "GIT_WORKTREE_ADD_FAILED" 69
assert_rollback_refused "REPLACED_WORKTREE" "PATH_REPLACED"
iso_is_registered "$ISO_ROOT/r-wt" || iso_fail "REPLACED_WORKTREE_UNREGISTERED"
[[ "$(git -C "$ISO_ROOT/r-wt" rev-parse HEAD)" == "$C1" ]] || iso_fail "REPLACED_WORKTREE_HEAD"
[[ -z "$(git -C "$ISO_ROOT/r-wt" status --porcelain)" ]] || iso_fail "REPLACED_WORKTREE_DIRTY"

assert_bystanders_intact "REPLACED"
iso_assert_source_untouched "REPLACED_SOURCE"

iso_pass "ROLLBACK_REFUSED_REPLACED_PATH"

# ---------------------------------------------------------------- 3. claimed by another operation

# Proof replaced by a symlink: ownership can no longer be demonstrated.
fault_create proof-symlink r-psym "$C1"
iso_expect_failed "PROOF_SYMLINK" "PROOF_SUBSTITUTED" 67
assert_rollback_refused "PROOF_SYMLINK" "PROOF_SUBSTITUTED"
[[ -L "$PROOF_DIR/r-psym.proof" ]] || iso_fail "PROOF_SYMLINK_REPLACED"
grep -Fxq "CBS_ISOLATION_STATE=CREATING" "$PROOF_DIR/r-psym.proof.orig" || iso_fail "PROOF_SYMLINK_TARGET_REWRITTEN"
iso_is_registered "$ISO_ROOT/r-psym" || iso_fail "PROOF_SYMLINK_UNREGISTERED"

# Proof replaced by a proof carrying another token.
fault_create proof-foreign r-pfor "$C1"
iso_expect_failed "PROOF_FOREIGN" "PROOF_SUBSTITUTED" 67
assert_rollback_refused "PROOF_FOREIGN" "PROOF_SUBSTITUTED"
grep -Fxq "CBS_ISOLATION_TOKEN=$FOREIGN_TOKEN" "$PROOF_DIR/r-pfor.proof" || iso_fail "PROOF_FOREIGN_OVERWRITTEN"
if grep -Fxq "CBS_ISOLATION_STATE=ABORTED" "$PROOF_DIR/r-pfor.proof"; then
    iso_fail "PROOF_FOREIGN_REWRITTEN"
fi
iso_is_registered "$ISO_ROOT/r-pfor" || iso_fail "PROOF_FOREIGN_UNREGISTERED"

# Lock claimed by another operation.
fault_create lock-steal r-lock "$C1"
iso_expect_failed "LOCK_STOLEN" "LOCK_LOST" 68
assert_rollback_refused "LOCK_STOLEN" "LOCK_LOST"
[[ -d "$LOCK_DIR" ]] || iso_fail "LOCK_STOLEN_REMOVED"
[[ "$(cat "$LOCK_DIR/owner")" == "foreign-owner" ]] || iso_fail "LOCK_STOLEN_OWNER_CHANGED"
iso_is_registered "$ISO_ROOT/r-lock" || iso_fail "LOCK_STOLEN_UNREGISTERED"
grep -Fxq "CBS_ISOLATION_STATE=CREATING" "$PROOF_DIR/r-lock.proof" || iso_fail "LOCK_STOLEN_PROOF_REWRITTEN"

# The foreign lock is never released by the manager: it blocks, it is not stolen.
iso_run create after-steal "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "LOCK_FOREIGN_BLOCKS" "LOCK_BUSY" 68
[[ ! -e "$ISO_ROOT/after-steal" ]] || iso_fail "LOCK_FOREIGN_CREATED"
[[ "$(cat "$LOCK_DIR/owner")" == "foreign-owner" ]] || iso_fail "LOCK_FOREIGN_TOUCHED"

# Operator removes the foreign lock (test fixture only).
rm -f "$LOCK_DIR/owner"
rmdir "$LOCK_DIR"

assert_bystanders_intact "CLAIMED"
iso_assert_source_untouched "CLAIMED_SOURCE"

iso_pass "ROLLBACK_REFUSED_CLAIMED"

# ---------------------------------------------------------------- 8. interrupted rollback

# Interruption (SIGTERM) while the rollback removes the worktree: nothing is
# deleted by the interrupted run, the proof stays unusable for a cleanup, the
# lock is released and the identifier stays burnt.
iso_shim_reset
export CBS_SHIM_ADD_MODE="source-change"
export CBS_SHIM_REMOVE_MODE="kill-term"
iso_run_shim create r-int "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
unset CBS_SHIM_ADD_MODE CBS_SHIM_REMOVE_MODE

[[ "$ISO_RC" -eq 143 ]] || iso_fail "INTERRUPT_TERM_RC_$ISO_RC"
[[ "$(iso_value RESULT)" == "FAIL" ]] || iso_fail "INTERRUPT_TERM_RESULT_$(iso_value RESULT)"
[[ "$(iso_value REASON)" == "INTERRUPTED" ]] || iso_fail "INTERRUPT_TERM_REASON_$(iso_value REASON)"
[[ "$(iso_shim_count remove)" == "1" ]] || iso_fail "INTERRUPT_TERM_REMOVE_COUNT"
iso_shim_saw_force && iso_fail "INTERRUPT_TERM_FORCE"
iso_is_registered "$ISO_ROOT/r-int" || iso_fail "INTERRUPT_TERM_UNREGISTERED"
[[ -d "$ISO_ROOT/r-int" ]] || iso_fail "INTERRUPT_TERM_PATH_REMOVED"
grep -Fxq "CBS_ISOLATION_STATE=CREATING" "$PROOF_DIR/r-int.proof" || iso_fail "INTERRUPT_TERM_PROOF_STATE"
[[ ! -e "$LOCK_DIR" ]] || iso_fail "INTERRUPT_TERM_LOCK_REMAINS"

iso_shim_reset
iso_run_shim cleanup r-int "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "INTERRUPT_TERM_CLEANUP" "PROOF_STATE_CREATING" 67
[[ "$(iso_shim_count remove)" == "0" ]] || iso_fail "INTERRUPT_TERM_CLEANUP_REMOVE_CALLED"

iso_run create r-int "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "INTERRUPT_TERM_REUSE" "ID_ALREADY_USED" 61

git -C "$SOURCE" branch -D shim-extra >/dev/null 2>&1
iso_snapshot_source
assert_bystanders_intact "INTERRUPT_TERM"

# Hard kill (SIGKILL) while the rollback removes the worktree: no handler can
# run. The lock stays in place and blocks every later operation: it is never
# stolen automatically, and nothing is deleted.
iso_shim_reset
export CBS_SHIM_ADD_MODE="source-change"
export CBS_SHIM_REMOVE_MODE="kill-9"
iso_run_shim create r-kill "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
unset CBS_SHIM_ADD_MODE CBS_SHIM_REMOVE_MODE

[[ "$ISO_RC" -eq 137 ]] || iso_fail "INTERRUPT_KILL_RC_$ISO_RC"
iso_is_registered "$ISO_ROOT/r-kill" || iso_fail "INTERRUPT_KILL_UNREGISTERED"
[[ -d "$ISO_ROOT/r-kill" ]] || iso_fail "INTERRUPT_KILL_PATH_REMOVED"
[[ -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]] || iso_fail "INTERRUPT_KILL_LOCK_MISSING"
grep -Fxq "CBS_ISOLATION_STATE=CREATING" "$PROOF_DIR/r-kill.proof" || iso_fail "INTERRUPT_KILL_PROOF_STATE"

git -C "$SOURCE" branch -D shim-extra >/dev/null 2>&1
iso_snapshot_source
STALE_COUNT="$(iso_shim_count remove)"

iso_shim_reset
iso_run_shim cleanup canary "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "INTERRUPT_KILL_CLEANUP_BLOCKED" "LOCK_BUSY" 68
iso_run_shim create r-after "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "INTERRUPT_KILL_CREATE_BLOCKED" "LOCK_BUSY" 68
[[ "$(iso_shim_count remove)" == "0" ]] || iso_fail "INTERRUPT_KILL_REMOVE_CALLED"
[[ ! -e "$ISO_ROOT/r-after" ]] || iso_fail "INTERRUPT_KILL_CREATED"
assert_bystanders_intact "INTERRUPT_KILL"
[[ -d "$ISO_ROOT/r-kill" ]] || iso_fail "INTERRUPT_KILL_RESOURCE_LOST"

# Operator removes the stale lock (test fixture only): the interrupted
# resource stays quarantined, the genuine one can be cleaned.
rm -f "$LOCK_DIR/owner"
rmdir "$LOCK_DIR"

iso_run_shim cleanup r-kill "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "INTERRUPT_KILL_QUARANTINE" "PROOF_STATE_CREATING" 67
[[ -d "$ISO_ROOT/r-kill" ]] || iso_fail "INTERRUPT_KILL_QUARANTINE_REMOVED"

iso_assert_source_untouched "INTERRUPT_SOURCE"

iso_pass "ROLLBACK_INTERRUPTED"

echo "${TEST_PREFIX}_RESULT=PASS"
