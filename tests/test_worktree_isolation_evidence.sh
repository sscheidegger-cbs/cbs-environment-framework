#!/usr/bin/env bash

# D04b-C.1 safety regression: the evidence directory (.cbs-isolation).
#
# Ownership, permissions, absence of symlinks, refusal of substitutions and
# collisions, for both the directory and the proofs it holds.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_EVIDENCE"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

iso_fixture_init
iso_shim_init

echo "${TEST_PREFIX}_FIXTURE=PASS"

PROOF_DIR="$ISO_ROOT/.cbs-isolation"

owned_by_me() {
    [[ -n "$(find "$1" -maxdepth 0 -user "$(id -u)" 2>/dev/null)" ]]
}

assert_resource_intact() {
    local label="$1"
    local id="$2"
    local commit="$3"

    [[ -d "$ISO_ROOT/$id" ]] || iso_fail "${label}_PATH_REMOVED"
    [[ "$(git -C "$ISO_ROOT/$id" rev-parse HEAD)" == "$commit" ]] || iso_fail "${label}_HEAD_CHANGED"
    iso_is_registered "$ISO_ROOT/$id" || iso_fail "${label}_UNREGISTERED"
}

iso_snapshot_source

# ---------------------------------------------------------------- secure creation

iso_run create alpha "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_pass "CREATE_ALPHA"

[[ -d "$PROOF_DIR" && ! -L "$PROOF_DIR" ]] || iso_fail "DIR_MISSING"
owned_by_me "$PROOF_DIR" || iso_fail "DIR_NOT_OWNED"
iso_has_mode "$PROOF_DIR" 700 || iso_fail "DIR_MODE"

[[ -f "$PROOF_DIR/alpha.proof" && ! -L "$PROOF_DIR/alpha.proof" ]] || iso_fail "PROOF_NOT_REGULAR"
owned_by_me "$PROOF_DIR/alpha.proof" || iso_fail "PROOF_NOT_OWNED"
iso_has_mode "$PROOF_DIR/alpha.proof" 600 || iso_fail "PROOF_MODE"

# Nothing but the proof: no temporary file left behind.
[[ "$(ls -A "$PROOF_DIR")" == "alpha.proof" ]] || iso_fail "PROOF_DIR_LEFTOVERS"
[[ ! -e "$ISO_ROOT/.cbs-isolation.lock" ]] || iso_fail "LOCK_LEFTOVER"

iso_pass "SECURE_CREATION"

# The proof of an aborted creation is protected the same way.
iso_shim_reset
export CBS_SHIM_ADD_MODE="source-change"
iso_run_shim create aborted "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
unset CBS_SHIM_ADD_MODE
iso_expect_failed "ABORTED_CREATE" "SOURCE_CHANGED" 68
iso_has_mode "$PROOF_DIR/aborted.proof" 600 || iso_fail "ABORTED_PROOF_MODE"
git -C "$SOURCE" branch -D shim-extra >/dev/null 2>&1
iso_snapshot_source
iso_shim_reset

# ---------------------------------------------------------------- insecure existing evidence directory (create)

for mode in 755 750 705 770 777 707; do
    iso_make_root "$TMP/root-mode-$mode"
    mkdir -m "$mode" "$TMP/root-mode-$mode/.cbs-isolation"
    chmod "$mode" "$TMP/root-mode-$mode/.cbs-isolation"

    COUNT_BEFORE="$(iso_worktree_count)"
    iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/root-mode-$mode"
    iso_expect_blocked "CREATE_DIR_MODE_$mode" "PROOF_DIR_INSECURE" 61

    [[ ! -e "$TMP/root-mode-$mode/id1" ]] || iso_fail "CREATE_DIR_MODE_${mode}_PATH_CREATED"
    [[ -z "$(ls -A "$TMP/root-mode-$mode/.cbs-isolation")" ]] || iso_fail "CREATE_DIR_MODE_${mode}_WRITTEN"
    [[ "$(iso_worktree_count)" == "$COUNT_BEFORE" ]] || iso_fail "CREATE_DIR_MODE_${mode}_REGISTERED"
    iso_has_mode "$TMP/root-mode-$mode/.cbs-isolation" "$mode" || iso_fail "CREATE_DIR_MODE_${mode}_REPAIRED_SILENTLY"
done

iso_assert_source_untouched "CREATE_DIR_MODE_SOURCE"

iso_pass "REFUSE_INSECURE_DIR_ON_CREATE"

# ---------------------------------------------------------------- insecure evidence directory (verify, cleanup)

for mode in 755 770 707; do
    chmod "$mode" "$PROOF_DIR"

    iso_run verify alpha "$SOURCE" "$ISO_ROOT"
    iso_expect_blocked "VERIFY_DIR_MODE_$mode" "PROOF_DIR_INSECURE" 61

    iso_run cleanup alpha "$SOURCE" "$ISO_ROOT"
    iso_expect_blocked "CLEANUP_DIR_MODE_$mode" "PROOF_DIR_INSECURE" 61
    assert_resource_intact "CLEANUP_DIR_MODE_$mode" alpha "$C1"
done

chmod 700 "$PROOF_DIR"
iso_run verify alpha "$SOURCE" "$ISO_ROOT"
iso_expect_pass "VERIFY_DIR_RESTORED"

# Evidence directory replaced by a symlink to a copy of the genuine directory.
mv "$PROOF_DIR" "$TMP/proof-dir.real"
ln -s "$TMP/proof-dir.real" "$PROOF_DIR"
iso_run cleanup alpha "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "CLEANUP_DIR_SYMLINK" "PROOF_DIR_INVALID" 61
iso_run verify alpha "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "VERIFY_DIR_SYMLINK" "PROOF_DIR_INVALID" 61
assert_resource_intact "CLEANUP_DIR_SYMLINK" alpha "$C1"
[[ ! -e "$TMP/proof-dir.real/alpha.cleaned" ]] || iso_fail "CLEANUP_DIR_SYMLINK_WRITTEN"
rm "$PROOF_DIR"
mv "$TMP/proof-dir.real" "$PROOF_DIR"

# Evidence directory replaced by a regular file.
mv "$PROOF_DIR" "$TMP/proof-dir.saved"
printf '%s\n' "x" > "$PROOF_DIR"
iso_run cleanup alpha "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "CLEANUP_DIR_FILE" "PROOF_DIR_INVALID" 61
rm "$PROOF_DIR"
mv "$TMP/proof-dir.saved" "$PROOF_DIR"

# Foreign owner: only checkable with the privilege to give a file away.
if [[ "$(id -u)" == "0" ]]; then
    chown 65534 "$PROOF_DIR"
    iso_run cleanup alpha "$SOURCE" "$ISO_ROOT"
    iso_expect_blocked "CLEANUP_DIR_FOREIGN_OWNER" "PROOF_DIR_NOT_OWNED" 61
    chown "$(id -u)" "$PROOF_DIR"
    echo "${TEST_PREFIX}_FOREIGN_OWNER=PASS"
else
    echo "${TEST_PREFIX}_FOREIGN_OWNER=SKIPPED"
fi

iso_run verify alpha "$SOURCE" "$ISO_ROOT"
iso_expect_pass "VERIFY_AFTER_DIR_CHECKS"

iso_pass "REFUSE_INSECURE_OR_SUBSTITUTED_DIR"

# ---------------------------------------------------------------- insecure proof file

for mode in 664 666 620 602; do
    chmod "$mode" "$PROOF_DIR/alpha.proof"

    iso_run verify alpha "$SOURCE" "$ISO_ROOT"
    iso_expect_blocked "VERIFY_PROOF_MODE_$mode" "PROOF_INSECURE" 67

    iso_run cleanup alpha "$SOURCE" "$ISO_ROOT"
    iso_expect_blocked "CLEANUP_PROOF_MODE_$mode" "PROOF_INSECURE" 67
    assert_resource_intact "CLEANUP_PROOF_MODE_$mode" alpha "$C1"
done

chmod 600 "$PROOF_DIR/alpha.proof"

# Hard link to the proof: the proof could be rewritten through another name.
ln "$PROOF_DIR/alpha.proof" "$PROOF_DIR/alpha.proof.link"
iso_run cleanup alpha "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "CLEANUP_PROOF_HARDLINK" "PROOF_INSECURE" 67
assert_resource_intact "CLEANUP_PROOF_HARDLINK" alpha "$C1"
rm "$PROOF_DIR/alpha.proof.link"

iso_run verify alpha "$SOURCE" "$ISO_ROOT"
iso_expect_pass "VERIFY_AFTER_PROOF_CHECKS"

iso_pass "REFUSE_INSECURE_PROOF"

# ---------------------------------------------------------------- substituted proof content

iso_run create beta "$SOURCE" "$ISO_ORIGIN" "$C2" "$ISO_ROOT"
iso_expect_pass "CREATE_BETA"

cp "$PROOF_DIR/alpha.proof" "$PROOF_DIR/alpha.proof.orig"

# Proof of another resource under this name.
cp "$PROOF_DIR/beta.proof" "$PROOF_DIR/alpha.proof"
chmod 600 "$PROOF_DIR/alpha.proof"
iso_run cleanup alpha "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "SUBSTITUTED_OTHER_PROOF" "PROOF_MISMATCH_ID" 67
assert_resource_intact "SUBSTITUTED_OTHER_PROOF" alpha "$C1"
assert_resource_intact "SUBSTITUTED_OTHER_PROOF_BETA" beta "$C2"

substitute_case() {
    local label="$1"
    local expression="$2"
    local reason="$3"
    local rc="$4"

    sed -e "$expression" "$PROOF_DIR/alpha.proof.orig" > "$PROOF_DIR/alpha.proof"
    chmod 600 "$PROOF_DIR/alpha.proof"

    iso_run cleanup alpha "$SOURCE" "$ISO_ROOT"
    iso_expect_blocked "SUBSTITUTED_$label" "$reason" "$rc"
    assert_resource_intact "SUBSTITUTED_$label" alpha "$C1"
}

# Identity of the path / of the Git administrative directory forged.
substitute_case PATH_IDENTITY 's#^CBS_ISOLATION_PATH_IDENTITY=.*#CBS_ISOLATION_PATH_IDENTITY=1#' PATH_IDENTITY_MISMATCH 67
substitute_case GIT_DIR_IDENTITY 's#^CBS_ISOLATION_GIT_DIR_IDENTITY=.*#CBS_ISOLATION_GIT_DIR_IDENTITY=1#' GIT_DIR_IDENTITY_MISMATCH 67
substitute_case PATH_IDENTITY_TEXT 's#^CBS_ISOLATION_PATH_IDENTITY=.*#CBS_ISOLATION_PATH_IDENTITY=not-a-number#' PROOF_MALFORMED 67
substitute_case GIT_DIR_IDENTITY_NONE 's#^CBS_ISOLATION_GIT_DIR_IDENTITY=.*#CBS_ISOLATION_GIT_DIR_IDENTITY=NONE#' PROOF_MALFORMED 67
substitute_case IDENTITY_MISSING '/^CBS_ISOLATION_PATH_IDENTITY=/d' PROOF_MALFORMED 67

cp "$PROOF_DIR/alpha.proof.orig" "$PROOF_DIR/alpha.proof"
chmod 600 "$PROOF_DIR/alpha.proof"
rm "$PROOF_DIR/alpha.proof.orig"

iso_run verify alpha "$SOURCE" "$ISO_ROOT"
iso_expect_pass "VERIFY_AFTER_SUBSTITUTIONS"

iso_pass "REFUSE_SUBSTITUTED_PROOF"

# ---------------------------------------------------------------- collisions

# Proof name already taken by a directory or by a symlink: the identifier is burnt.
mkdir "$PROOF_DIR/taken-dir.proof"
iso_run create taken-dir "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_PROOF_DIR" "ID_ALREADY_USED" 61
[[ -d "$PROOF_DIR/taken-dir.proof" ]] || iso_fail "COLLISION_PROOF_DIR_REMOVED"
[[ ! -e "$ISO_ROOT/taken-dir" ]] || iso_fail "COLLISION_PROOF_DIR_CREATED"

printf '%s\n' "victim" > "$TMP/victim.txt"
ln -s "$TMP/victim.txt" "$PROOF_DIR/taken-link.proof"
iso_run create taken-link "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_PROOF_LINK" "ID_ALREADY_USED" 61
[[ "$(cat "$TMP/victim.txt")" == "victim" ]] || iso_fail "COLLISION_PROOF_LINK_TARGET_WRITTEN"

# A cleaned record planted as a symlink: the identifier is burnt as well.
ln -s "$TMP/victim.txt" "$PROOF_DIR/taken-clean.cleaned"
iso_run create taken-clean "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_CLEANED_LINK" "ID_ALREADY_USED" 61
[[ "$(cat "$TMP/victim.txt")" == "victim" ]] || iso_fail "COLLISION_CLEANED_TARGET_WRITTEN"

# A cleanup never writes its record through a planted symlink or file.
ln -s "$TMP/victim.txt" "$PROOF_DIR/beta.cleaned"
iso_run cleanup beta "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "COLLISION_CLEANUP_RECORD" "ALREADY_CLEANED" 67
[[ "$(cat "$TMP/victim.txt")" == "victim" ]] || iso_fail "COLLISION_CLEANUP_RECORD_WRITTEN"
assert_resource_intact "COLLISION_CLEANUP_RECORD" beta "$C2"
rm "$PROOF_DIR/beta.cleaned"

iso_assert_source_untouched "COLLISIONS_SOURCE"

iso_pass "REFUSE_COLLISIONS"

# ---------------------------------------------------------------- cleaned record

iso_run cleanup beta "$SOURCE" "$ISO_ROOT"
iso_expect_pass "CLEANUP_BETA"
[[ -f "$PROOF_DIR/beta.cleaned" && ! -L "$PROOF_DIR/beta.cleaned" ]] || iso_fail "CLEANED_NOT_REGULAR"
iso_has_mode "$PROOF_DIR/beta.cleaned" 600 || iso_fail "CLEANED_MODE"
[[ -f "$PROOF_DIR/beta.proof" ]] || iso_fail "CLEANED_PROOF_REMOVED"
iso_has_mode "$PROOF_DIR" 700 || iso_fail "CLEANED_DIR_MODE"
[[ ! -e "$ISO_ROOT/.cbs-isolation.lock" ]] || iso_fail "CLEANED_LOCK_LEFTOVER"

iso_pass "CLEANED_RECORD"

echo "${TEST_PREFIX}_RESULT=PASS"
