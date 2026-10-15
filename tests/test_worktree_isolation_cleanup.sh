#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_CLEANUP"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

iso_fixture_init

echo "${TEST_PREFIX}_FIXTURE=PASS"

PROOF_DIR="$ISO_ROOT/.cbs-isolation"

proof_value() {
    sed -n "s/^CBS_ISOLATION_$2=//p" "$PROOF_DIR/$1.proof" | head -n 1
}

create_ok() {
    iso_run create "$1" "$SOURCE" "$ISO_ORIGIN" "$2" "$ISO_ROOT"
    iso_expect_pass "SETUP_CREATE_$1"
}

assert_preserved() {
    local label="$1"
    local path="$2"
    local expected_head="$3"

    [[ -d "$path" ]] || iso_fail "${label}_PATH_REMOVED"
    [[ "$(git -C "$path" rev-parse HEAD)" == "$expected_head" ]] || iso_fail "${label}_HEAD_CHANGED"
    git -C "$SOURCE" worktree list --porcelain | grep -Fxq "worktree $path" ||
        iso_fail "${label}_UNREGISTERED"
}

# ---------------------------------------------------------------- setup

create_ok del1 "$C1"
create_ok keep "$C2"

# Pre-existing resources, not created by CBS, under the authorized root.
git -C "$SOURCE" worktree add --detach "$ISO_ROOT/pre-existing" "$C1" >/dev/null 2>&1
mkdir -p "$ISO_ROOT/plain-dir"
printf '%s\n' "precious" > "$ISO_ROOT/plain-dir/data.txt"
iso_snapshot_source

# ---------------------------------------------------------------- refusal: not identified as created by CBS

iso_run cleanup pre-existing "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "PREEXISTING_WORKTREE" "PROOF_MISSING" 67
assert_preserved "PREEXISTING_WORKTREE" "$ISO_ROOT/pre-existing" "$C1"
[[ "$(iso_value GIT_STATUS)" == "NOT_RUN" ]] || iso_fail "PREEXISTING_NOT_RUN"

iso_run cleanup plain-dir "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "PREEXISTING_DIR" "PROOF_MISSING" 67
[[ "$(cat "$ISO_ROOT/plain-dir/data.txt")" == "precious" ]] || iso_fail "PREEXISTING_DIR_CHANGED"

iso_run cleanup never-created "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "UNKNOWN_ID" "PROOF_MISSING" 67

iso_run cleanup "../pre-existing" "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "TRAVERSAL_ID" "ID_INVALID" 64
assert_preserved "TRAVERSAL_ID" "$ISO_ROOT/pre-existing" "$C1"

iso_run cleanup "" "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "EMPTY_ID" "USAGE" 64

iso_run cleanup del1 "$SOURCE"
iso_expect_blocked "MISSING_ARGUMENT" "USAGE" 64

iso_run verify pre-existing "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "VERIFY_PREEXISTING" "PROOF_MISSING" 67

# Forged proof: copy of a genuine proof renamed for a pre-existing worktree.
sed -e 's#^CBS_ISOLATION_ID=.*#CBS_ISOLATION_ID=pre-existing#' \
    -e "s#^CBS_ISOLATION_PATH=.*#CBS_ISOLATION_PATH=$ISO_ROOT/pre-existing#" \
    -e "s#^CBS_ISOLATION_RESOURCE_PROOF_FILE=.*#CBS_ISOLATION_RESOURCE_PROOF_FILE=$PROOF_DIR/pre-existing.proof#" \
    "$PROOF_DIR/del1.proof" > "$PROOF_DIR/pre-existing.proof"

iso_run cleanup pre-existing "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "FORGED_PROOF" "GIT_DIR_MISMATCH" 67
assert_preserved "FORGED_PROOF" "$ISO_ROOT/pre-existing" "$C1"
assert_preserved "FORGED_PROOF_GENUINE" "$ISO_ROOT/del1" "$C1"

# Forged proof pointing to a plain directory.
sed -e 's#^CBS_ISOLATION_ID=.*#CBS_ISOLATION_ID=plain-dir#' \
    -e "s#^CBS_ISOLATION_PATH=.*#CBS_ISOLATION_PATH=$ISO_ROOT/plain-dir#" \
    -e "s#^CBS_ISOLATION_RESOURCE_PROOF_FILE=.*#CBS_ISOLATION_RESOURCE_PROOF_FILE=$PROOF_DIR/plain-dir.proof#" \
    "$PROOF_DIR/del1.proof" > "$PROOF_DIR/plain-dir.proof"

iso_run cleanup plain-dir "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "FORGED_PROOF_PLAIN_DIR" "NOT_A_WORKTREE" 67
[[ "$(cat "$ISO_ROOT/plain-dir/data.txt")" == "precious" ]] || iso_fail "FORGED_PLAIN_DIR_CHANGED"

# Fully consistent forged proof for a worktree OUTSIDE the authorized root.
git -C "$SOURCE" worktree add --detach "$TMP/outside-wt" "$C1" >/dev/null 2>&1
OUTSIDE_GIT_DIR="$(cd -P "$TMP/outside-wt" && cd -P "$(git rev-parse --git-dir)" && pwd -P)"

{
    printf 'CBS_ISOLATION_PROOF_VERSION=1\n'
    printf 'CBS_ISOLATION_ID=outsider\n'
    printf 'CBS_ISOLATION_TOKEN=%s\n' "$(proof_value del1 TOKEN)"
    printf 'CBS_ISOLATION_STATE=READY\n'
    printf 'CBS_ISOLATION_CREATED_BY=CBS\n'
    printf 'CBS_ISOLATION_CREATED_AT=2026-01-01T00:00:00Z\n'
    printf 'CBS_ISOLATION_SOURCE_REPOSITORY=%s\n' "$SOURCE"
    printf 'CBS_ISOLATION_SOURCE_COMMON_DIR=%s\n' "$(proof_value del1 SOURCE_COMMON_DIR)"
    printf 'CBS_ISOLATION_ORIGIN=%s\n' "$ISO_ORIGIN"
    printf 'CBS_ISOLATION_COMMIT=%s\n' "$C1"
    printf 'CBS_ISOLATION_ROOT=%s\n' "$ISO_ROOT"
    printf 'CBS_ISOLATION_PATH=%s\n' "$TMP/outside-wt"
    printf 'CBS_ISOLATION_WORKTREE_GIT_DIR=%s\n' "$OUTSIDE_GIT_DIR"
    printf 'CBS_ISOLATION_PATH_IDENTITY=%s\n' "$(proof_value del1 PATH_IDENTITY)"
    printf 'CBS_ISOLATION_GIT_DIR_IDENTITY=%s\n' "$(proof_value del1 GIT_DIR_IDENTITY)"
    printf 'CBS_ISOLATION_RESOURCE_PROOF_FILE=%s\n' "$PROOF_DIR/outsider.proof"
    printf 'CBS_ISOLATION_ABORT_REASON=NONE\n'
} > "$PROOF_DIR/outsider.proof"

iso_run cleanup outsider "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "OUTSIDE_ROOT" "PROOF_MISMATCH_PATH" 67
assert_preserved "OUTSIDE_ROOT" "$TMP/outside-wt" "$C1"

iso_assert_source_untouched "REFUSALS_NOT_CBS_SOURCE"

iso_pass "REFUSE_PREEXISTING_RESOURCES"

# ---------------------------------------------------------------- refusal: tampered proofs

tamper_case() {
    local label="$1"
    local expression="$2"
    local reason="$3"
    local rc="$4"
    local file="$PROOF_DIR/del1.proof"

    cp "$file" "$file.orig"
    sed -e "$expression" "$file.orig" > "$file"

    iso_run cleanup del1 "$SOURCE" "$ISO_ROOT"
    iso_expect_blocked "TAMPER_$label" "$reason" "$rc"
    assert_preserved "TAMPER_$label" "$ISO_ROOT/del1" "$C1"

    mv -f "$file.orig" "$file"
}

tamper_case STATE_ABORTED 's#^CBS_ISOLATION_STATE=.*#CBS_ISOLATION_STATE=ABORTED#' PROOF_STATE_ABORTED 67
tamper_case STATE_CREATING 's#^CBS_ISOLATION_STATE=.*#CBS_ISOLATION_STATE=CREATING#' PROOF_STATE_CREATING 67
tamper_case STATE_UNKNOWN 's#^CBS_ISOLATION_STATE=.*#CBS_ISOLATION_STATE=WHATEVER#' PROOF_STATE_INVALID 67
tamper_case CREATED_BY 's#^CBS_ISOLATION_CREATED_BY=.*#CBS_ISOLATION_CREATED_BY=SOMEONE#' PROOF_MISMATCH_CREATED_BY 67
tamper_case VERSION 's#^CBS_ISOLATION_PROOF_VERSION=.*#CBS_ISOLATION_PROOF_VERSION=2#' PROOF_MISMATCH_VERSION 67
tamper_case ID 's#^CBS_ISOLATION_ID=.*#CBS_ISOLATION_ID=other#' PROOF_MISMATCH_ID 67
tamper_case ROOT 's#^CBS_ISOLATION_ROOT=.*#CBS_ISOLATION_ROOT=/elsewhere#' PROOF_MISMATCH_ROOT 67
tamper_case PATH 's#^CBS_ISOLATION_PATH=.*#CBS_ISOLATION_PATH=/elsewhere/del1#' PROOF_MISMATCH_PATH 67
tamper_case SOURCE 's#^CBS_ISOLATION_SOURCE_REPOSITORY=.*#CBS_ISOLATION_SOURCE_REPOSITORY=/elsewhere/source#' SOURCE_MISMATCH 67
tamper_case GIT_DIR 's#^CBS_ISOLATION_WORKTREE_GIT_DIR=.*#CBS_ISOLATION_WORKTREE_GIT_DIR=/elsewhere/gitdir#' GIT_DIR_MISMATCH 67
tamper_case ORIGIN 's#^CBS_ISOLATION_ORIGIN=.*#CBS_ISOLATION_ORIGIN=https://example.invalid/forged.git#' ORIGIN_MISMATCH 66
tamper_case COMMIT "s#^CBS_ISOLATION_COMMIT=.*#CBS_ISOLATION_COMMIT=$C2#" HEAD_MISMATCH 68
tamper_case DUPLICATE_KEY '/^CBS_ISOLATION_ID=/p' PROOF_MALFORMED 67
tamper_case MISSING_KEY '/^CBS_ISOLATION_CREATED_BY=/d' PROOF_MALFORMED 67
tamper_case UNKNOWN_KEY '$a\
CBS_ISOLATION_EXTRA=1' PROOF_MALFORMED 67
tamper_case GARBAGE_LINE '$a\
rm -rf /' PROOF_MALFORMED 67
tamper_case EMPTY_VALUE 's#^CBS_ISOLATION_TOKEN=.*#CBS_ISOLATION_TOKEN=#' PROOF_MALFORMED 67
tamper_case BAD_TOKEN 's#^CBS_ISOLATION_TOKEN=.*#CBS_ISOLATION_TOKEN=not-a-token#' PROOF_MALFORMED 67

# Empty proof file.
cp "$PROOF_DIR/del1.proof" "$PROOF_DIR/del1.proof.orig"
: > "$PROOF_DIR/del1.proof"
iso_run cleanup del1 "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "TAMPER_EMPTY_FILE" "PROOF_MALFORMED" 67
assert_preserved "TAMPER_EMPTY_FILE" "$ISO_ROOT/del1" "$C1"
mv -f "$PROOF_DIR/del1.proof.orig" "$PROOF_DIR/del1.proof"

# Proof replaced by a symlink to a genuine copy.
mv "$PROOF_DIR/del1.proof" "$TMP/del1.proof.real"
ln -s "$TMP/del1.proof.real" "$PROOF_DIR/del1.proof"
iso_run cleanup del1 "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "TAMPER_PROOF_SYMLINK" "PROOF_SYMLINK" 67
assert_preserved "TAMPER_PROOF_SYMLINK" "$ISO_ROOT/del1" "$C1"
rm "$PROOF_DIR/del1.proof"
mv "$TMP/del1.proof.real" "$PROOF_DIR/del1.proof"

# After all the tampering the genuine resource is still verifiable.
iso_run verify del1 "$SOURCE" "$ISO_ROOT"
iso_expect_pass "VERIFY_AFTER_TAMPER"

iso_assert_source_untouched "TAMPER_SOURCE"

iso_pass "REFUSE_TAMPERED_PROOFS"

# ---------------------------------------------------------------- refusal: wrong context

# Wrong source repository (same origin, other repository).
OTHER_SOURCE="$TMP/other-source"
git clone -q "$SOURCE" "$OTHER_SOURCE" 2>/dev/null
git -C "$OTHER_SOURCE" remote set-url origin "$ISO_ORIGIN"

iso_run cleanup del1 "$OTHER_SOURCE" "$ISO_ROOT"
iso_expect_blocked "WRONG_SOURCE" "SOURCE_MISMATCH" 67
assert_preserved "WRONG_SOURCE" "$ISO_ROOT/del1" "$C1"

# Wrong (other, authorized) root: no proof there.
iso_make_root "$TMP/other-root"
iso_run cleanup del1 "$SOURCE" "$TMP/other-root"
iso_expect_blocked "WRONG_ROOT" "PROOF_MISSING" 67
assert_preserved "WRONG_ROOT" "$ISO_ROOT/del1" "$C1"

# Root no longer authorized (marker removed).
mv "$ISO_ROOT/.cbs-isolation-root" "$TMP/marker.saved"
iso_run cleanup del1 "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "ROOT_UNAUTHORIZED" "ROOT_NOT_AUTHORIZED" 61
assert_preserved "ROOT_UNAUTHORIZED" "$ISO_ROOT/del1" "$C1"
mv "$TMP/marker.saved" "$ISO_ROOT/.cbs-isolation-root"

# Origin of the source changed since creation.
git -C "$SOURCE" remote set-url origin "https://example.invalid/moved.git"
iso_run cleanup del1 "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "ORIGIN_CHANGED" "ORIGIN_MISMATCH" 66
assert_preserved "ORIGIN_CHANGED" "$ISO_ROOT/del1" "$C1"
git -C "$SOURCE" remote set-url origin "$ISO_ORIGIN"

# Source reached through a symlink.
ln -s "$SOURCE" "$TMP/source-link"
iso_run cleanup del1 "$TMP/source-link" "$ISO_ROOT"
iso_expect_blocked "SOURCE_SYMLINK" "SOURCE_SYMLINK" 62
assert_preserved "SOURCE_SYMLINK" "$ISO_ROOT/del1" "$C1"

iso_assert_source_untouched "WRONG_CONTEXT_SOURCE"

iso_pass "REFUSE_WRONG_CONTEXT"

# ---------------------------------------------------------------- refusal: modified or concurrent state

# Untracked file inside the isolated worktree.
create_ok dirty-untracked "$C1"
printf '%s\n' "build-output" > "$ISO_ROOT/dirty-untracked/artifact.txt"
iso_run cleanup dirty-untracked "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "DIRTY_UNTRACKED" "WORKTREE_DIRTY" 68
[[ "$(iso_value GIT_STATUS)" == "DIRTY" ]] || iso_fail "DIRTY_UNTRACKED_STATUS"
[[ -f "$ISO_ROOT/dirty-untracked/artifact.txt" ]] || iso_fail "DIRTY_UNTRACKED_REMOVED"
assert_preserved "DIRTY_UNTRACKED" "$ISO_ROOT/dirty-untracked" "$C1"

# Modified tracked file.
create_ok dirty-tracked "$C1"
printf '%s\n' "edited" > "$ISO_ROOT/dirty-tracked/file.txt"
iso_run cleanup dirty-tracked "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "DIRTY_TRACKED" "WORKTREE_DIRTY" 68
[[ "$(cat "$ISO_ROOT/dirty-tracked/file.txt")" == "edited" ]] || iso_fail "DIRTY_TRACKED_CHANGED"

# HEAD moved to another commit.
create_ok moved "$C1"
git -C "$ISO_ROOT/moved" checkout -q --detach "$C2"
iso_run cleanup moved "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "HEAD_MOVED" "HEAD_MISMATCH" 68
[[ "$(iso_value COMMIT_OBSERVED)" == "$C2" ]] || iso_fail "HEAD_MOVED_OBSERVED"
[[ "$(iso_value COMMIT_EXPECTED)" == "$C1" ]] || iso_fail "HEAD_MOVED_EXPECTED"
assert_preserved "HEAD_MOVED" "$ISO_ROOT/moved" "$C2"

# HEAD re-attached to a branch pointing at the same commit.
create_ok attached "$C2"
git -C "$ISO_ROOT/attached" checkout -q dev-branch
iso_run cleanup attached "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "HEAD_ATTACHED" "NOT_DETACHED" 68
assert_preserved "HEAD_ATTACHED" "$ISO_ROOT/attached" "$C2"

# Path replaced by a symlink to the genuine worktree.
create_ok swapped "$C1"
mv "$ISO_ROOT/swapped" "$TMP/swapped.real"
ln -s "$TMP/swapped.real" "$ISO_ROOT/swapped"
iso_run cleanup swapped "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "PATH_SWAPPED_FOR_SYMLINK" "PATH_SYMLINK" 61
[[ -d "$TMP/swapped.real" ]] || iso_fail "PATH_SWAPPED_TARGET_REMOVED"
[[ -L "$ISO_ROOT/swapped" ]] || iso_fail "PATH_SWAPPED_LINK_REMOVED"

# Directory removed by someone else: nothing to clean, registration kept (no prune).
create_ok vanished "$C1"
VANISHED_COUNT="$(git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ' || true)"
rm -r "$ISO_ROOT/vanished"
iso_run cleanup vanished "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "PATH_VANISHED" "PATH_MISSING" 61
[[ -f "$PROOF_DIR/vanished.proof" ]] || iso_fail "PATH_VANISHED_PROOF_LOST"
[[ "$(git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ' || true)" == "$VANISHED_COUNT" ]] ||
    iso_fail "PATH_VANISHED_PRUNED"

iso_assert_source_untouched "STATE_REFUSALS_SOURCE"

iso_pass "REFUSE_MODIFIED_STATE"

# ---------------------------------------------------------------- controlled cleanup

DEL1_PATH="$ISO_ROOT/del1"
DEL1_GIT_DIR="$(proof_value del1 WORKTREE_GIT_DIR)"
DEL1_TOKEN="$(proof_value del1 TOKEN)"

KEEP_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/keep")"
PRE_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/pre-existing")"
PLAIN_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/plain-dir")"
DIRTY_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/dirty-untracked")"

[[ -d "$DEL1_GIT_DIR" ]] || iso_fail "CLEANUP_PRECONDITION_GIT_DIR"

iso_run cleanup del1 "$SOURCE" "$ISO_ROOT"
iso_expect_pass "CLEANUP"

[[ "$(iso_value PATH)" == "$DEL1_PATH" ]] || iso_fail "CLEANUP_PATH_FIELD"
[[ "$(iso_value REMOVED)" == "$DEL1_PATH" ]] || iso_fail "CLEANUP_REMOVED_FIELD"
[[ "$(iso_value PROOF_ID)" == "$DEL1_TOKEN" ]] || iso_fail "CLEANUP_PROOF_ID_FIELD"
[[ "$(iso_value REASON)" == "NONE" ]] || iso_fail "CLEANUP_REASON_FIELD"

[[ ! -e "$DEL1_PATH" && ! -L "$DEL1_PATH" ]] || iso_fail "CLEANUP_PATH_REMAINS"
[[ ! -e "$DEL1_GIT_DIR" ]] || iso_fail "CLEANUP_GIT_DIR_REMAINS"

if git -C "$SOURCE" worktree list --porcelain | grep -Fxq "worktree $DEL1_PATH"; then
    iso_fail "CLEANUP_STILL_REGISTERED"
fi

# Proof preserved, cleanup recorded.
[[ -f "$PROOF_DIR/del1.proof" ]] || iso_fail "CLEANUP_PROOF_REMOVED"
[[ -f "$PROOF_DIR/del1.cleaned" ]] || iso_fail "CLEANUP_RECORD_MISSING"
grep -Fxq "CBS_ISOLATION_TOKEN=$DEL1_TOKEN" "$PROOF_DIR/del1.cleaned" || iso_fail "CLEANUP_RECORD_TOKEN"
grep -Fxq "CBS_ISOLATION_ID=del1" "$PROOF_DIR/del1.cleaned" || iso_fail "CLEANUP_RECORD_ID"

# Everything else is intact: other CBS worktree, pre-existing resources, source.
assert_preserved "CLEANUP_KEEP" "$ISO_ROOT/keep" "$C2"
assert_preserved "CLEANUP_PRE_EXISTING" "$ISO_ROOT/pre-existing" "$C1"
assert_preserved "CLEANUP_DIRTY_OTHER" "$ISO_ROOT/dirty-untracked" "$C1"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/keep")" == "$KEEP_BEFORE" ]] || iso_fail "CLEANUP_KEEP_CHANGED"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/pre-existing")" == "$PRE_BEFORE" ]] || iso_fail "CLEANUP_PRE_EXISTING_CHANGED"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/plain-dir")" == "$PLAIN_BEFORE" ]] || iso_fail "CLEANUP_PLAIN_DIR_CHANGED"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/dirty-untracked")" == "$DIRTY_BEFORE" ]] || iso_fail "CLEANUP_DIRTY_OTHER_CHANGED"
[[ -d "$ISO_ROOT" && -f "$ISO_ROOT/.cbs-isolation-root" ]] || iso_fail "CLEANUP_ROOT_TOUCHED"
[[ -d "$TMP/outside-wt" ]] || iso_fail "CLEANUP_OUTSIDE_TOUCHED"

iso_assert_source_untouched "CLEANUP_SOURCE"

iso_pass "CONTROLLED_CLEANUP"

# ---------------------------------------------------------------- no second cleanup, no identifier reuse

iso_run cleanup del1 "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "CLEANUP_TWICE" "ALREADY_CLEANED" 67

iso_run verify del1 "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "VERIFY_CLEANED" "ALREADY_CLEANED" 67

iso_run create del1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "REUSE_CLEANED_ID" "ID_ALREADY_USED" 61
[[ ! -e "$DEL1_PATH" ]] || iso_fail "REUSE_CLEANED_ID_CREATED"

iso_pass "NO_SECOND_CLEANUP_NO_REUSE"

# ---------------------------------------------------------------- cleanup of the remaining CBS resource

iso_run cleanup keep "$SOURCE" "$ISO_ROOT"
iso_expect_pass "CLEANUP_KEEP"
[[ ! -e "$ISO_ROOT/keep" ]] || iso_fail "CLEANUP_KEEP_REMAINS"
assert_preserved "CLEANUP_KEEP_PRE_EXISTING" "$ISO_ROOT/pre-existing" "$C1"
iso_assert_source_untouched "CLEANUP_KEEP_SOURCE"

iso_pass "CLEANUP_SECOND_RESOURCE"

echo "${TEST_PREFIX}_RESULT=PASS"
