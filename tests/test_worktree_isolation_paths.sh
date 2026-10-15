#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_PATHS"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

iso_fixture_init

echo "${TEST_PREFIX}_FIXTURE=PASS"

worktree_count() {
    git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ' || true
}

# A refusal must leave neither a registered worktree nor a proof directory.
assert_nothing_created() {
    local label="$1"
    local root="$2"

    [[ "$(worktree_count)" == "$WORKTREES_BEFORE" ]] ||
        iso_fail "${label}_WORKTREE_REGISTERED"

    [[ ! -e "$root/.cbs-isolation" ]] ||
        iso_fail "${label}_PROOF_DIR_CREATED"

    iso_assert_source_untouched "${label}_SOURCE"
}

iso_snapshot_source
WORKTREES_BEFORE="$(worktree_count)"

# ---------------------------------------------------------------- unauthorized roots

# No marker.
mkdir -p "$TMP/no-marker"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/no-marker"
iso_expect_blocked "ROOT_NO_MARKER" "ROOT_NOT_AUTHORIZED" 61
[[ ! -e "$TMP/no-marker/id1" ]] || iso_fail "ROOT_NO_MARKER_CREATED"
assert_nothing_created "ROOT_NO_MARKER" "$TMP/no-marker"

# Marker with wrong content.
mkdir -p "$TMP/bad-marker"
printf '%s\n' "SOMETHING_ELSE" > "$TMP/bad-marker/.cbs-isolation-root"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/bad-marker"
iso_expect_blocked "ROOT_BAD_MARKER" "ROOT_NOT_AUTHORIZED" 61
assert_nothing_created "ROOT_BAD_MARKER" "$TMP/bad-marker"

# Marker is a symlink to a valid marker.
mkdir -p "$TMP/link-marker"
printf '%s\n' "CBS_ISOLATION_ROOT_V1" > "$TMP/marker-target"
ln -s "$TMP/marker-target" "$TMP/link-marker/.cbs-isolation-root"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/link-marker"
iso_expect_blocked "ROOT_SYMLINK_MARKER" "ROOT_NOT_AUTHORIZED" 61
assert_nothing_created "ROOT_SYMLINK_MARKER" "$TMP/link-marker"

# Marker is a directory.
mkdir -p "$TMP/dir-marker/.cbs-isolation-root"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/dir-marker"
iso_expect_blocked "ROOT_DIR_MARKER" "ROOT_NOT_AUTHORIZED" 61
assert_nothing_created "ROOT_DIR_MARKER" "$TMP/dir-marker"

# Relative root.
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "isolation-root"
iso_expect_blocked "ROOT_RELATIVE" "ROOT_NOT_ABSOLUTE" 61
assert_nothing_created "ROOT_RELATIVE" "$ISO_ROOT"

# Filesystem root.
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "/"
iso_expect_blocked "ROOT_FILESYSTEM" "ROOT_FORBIDDEN" 61
[[ ! -e "/id1" ]] || iso_fail "ROOT_FILESYSTEM_CREATED"

# Missing root.
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/missing-root"
iso_expect_blocked "ROOT_MISSING" "ROOT_MISSING" 61
[[ ! -e "$TMP/missing-root" ]] || iso_fail "ROOT_MISSING_CREATED"

# Root is a regular file.
printf '%s\n' "file" > "$TMP/root-is-file"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/root-is-file"
iso_expect_blocked "ROOT_IS_FILE" "ROOT_MISSING" 61

# Non canonical spellings of a valid root.
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT/"
iso_expect_blocked "ROOT_TRAILING_SLASH" "ROOT_NOT_CANONICAL" 61

iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT/../isolation-root"
iso_expect_blocked "ROOT_DOTDOT" "ROOT_NOT_CANONICAL" 61

iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT/./"
iso_expect_blocked "ROOT_DOT" "ROOT_NOT_CANONICAL" 61

assert_nothing_created "ROOT_NON_CANONICAL" "$ISO_ROOT"

# Root overlapping the source repository.
iso_make_root "$SOURCE/iso-inside"
iso_snapshot_source
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$SOURCE/iso-inside"
iso_expect_blocked "ROOT_INSIDE_SOURCE" "ROOT_OVERLAPS_SOURCE" 61
[[ ! -e "$SOURCE/iso-inside/id1" ]] || iso_fail "ROOT_INSIDE_SOURCE_CREATED"
assert_nothing_created "ROOT_INSIDE_SOURCE" "$SOURCE/iso-inside"
rm -r "$SOURCE/iso-inside/.cbs-isolation-root"
rmdir "$SOURCE/iso-inside"
iso_snapshot_source

iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$SOURCE"
iso_expect_blocked "ROOT_IS_SOURCE" "ROOT_OVERLAPS_SOURCE" 61

printf '%s\n' "CBS_ISOLATION_ROOT_V1" > "$TMP/.cbs-isolation-root"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP"
iso_expect_blocked "ROOT_CONTAINS_SOURCE" "ROOT_OVERLAPS_SOURCE" 61
rm "$TMP/.cbs-isolation-root"

# Root writable by group or others.
chmod 777 "$ISO_ROOT"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "ROOT_WORLD_WRITABLE" "ROOT_WRITABLE_BY_OTHERS" 61

chmod 775 "$ISO_ROOT"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "ROOT_GROUP_WRITABLE" "ROOT_WRITABLE_BY_OTHERS" 61

chmod 755 "$ISO_ROOT"
assert_nothing_created "ROOT_WRITABLE" "$ISO_ROOT"

iso_pass "UNAUTHORIZED_ROOTS"

# ---------------------------------------------------------------- symlinks

# Root is a symlink to a valid, authorized root.
REAL_ROOT="$TMP/real-root"
iso_make_root "$REAL_ROOT"
ln -s "$REAL_ROOT" "$TMP/root-link"

REAL_ROOT_BEFORE="$(iso_tree_fingerprint "$REAL_ROOT")"

iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/root-link"
iso_expect_blocked "ROOT_SYMLINK" "ROOT_SYMLINK" 61
[[ "$(iso_tree_fingerprint "$REAL_ROOT")" == "$REAL_ROOT_BEFORE" ]] || iso_fail "ROOT_SYMLINK_TARGET_CHANGED"

# A parent component of the root is a symlink.
mkdir -p "$TMP/real-parent"
iso_make_root "$TMP/real-parent/root"
ln -s "$TMP/real-parent" "$TMP/parent-link"

iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/parent-link/root"
iso_expect_blocked "ROOT_PARENT_SYMLINK" "ROOT_NOT_CANONICAL" 61
[[ ! -e "$TMP/real-parent/root/id1" ]] || iso_fail "ROOT_PARENT_SYMLINK_CREATED"

# Source repository reached through a symlink.
ln -s "$SOURCE" "$TMP/source-link"
iso_run create id1 "$TMP/source-link" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "SOURCE_SYMLINK" "SOURCE_SYMLINK" 62

ln -s "$TMP" "$TMP/tmp-link"
iso_run create id1 "$TMP/tmp-link/source" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "SOURCE_PARENT_SYMLINK" "SOURCE_NOT_CANONICAL" 62

# Target path is a symlink to a directory outside the root.
mkdir -p "$TMP/outside"
printf '%s\n' "outside-content" > "$TMP/outside/keep.txt"
OUTSIDE_BEFORE="$(iso_tree_fingerprint "$TMP/outside")"
ln -s "$TMP/outside" "$ISO_ROOT/linked"

iso_run create linked "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "PATH_SYMLINK_TO_DIR" "PATH_SYMLINK" 61
[[ -L "$ISO_ROOT/linked" ]] || iso_fail "PATH_SYMLINK_REMOVED"
[[ "$(iso_tree_fingerprint "$TMP/outside")" == "$OUTSIDE_BEFORE" ]] || iso_fail "PATH_SYMLINK_TARGET_CHANGED"

# Target path is a dangling symlink.
ln -s "$TMP/does-not-exist-anywhere" "$ISO_ROOT/dangling"
iso_run create dangling "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "PATH_DANGLING_SYMLINK" "PATH_SYMLINK" 61
[[ ! -e "$TMP/does-not-exist-anywhere" ]] || iso_fail "PATH_DANGLING_TARGET_CREATED"

# Proof directory is a symlink.
iso_make_root "$TMP/root-proof-link"
mkdir -p "$TMP/proof-elsewhere"
ln -s "$TMP/proof-elsewhere" "$TMP/root-proof-link/.cbs-isolation"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/root-proof-link"
iso_expect_blocked "PROOF_DIR_SYMLINK" "PROOF_DIR_INVALID" 61
[[ -z "$(ls -A "$TMP/proof-elsewhere")" ]] || iso_fail "PROOF_DIR_SYMLINK_TARGET_WRITTEN"
[[ ! -e "$TMP/root-proof-link/id1" ]] || iso_fail "PROOF_DIR_SYMLINK_PATH_CREATED"

# Proof directory is a regular file.
iso_make_root "$TMP/root-proof-file"
printf '%s\n' "x" > "$TMP/root-proof-file/.cbs-isolation"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/root-proof-file"
iso_expect_blocked "PROOF_DIR_FILE" "PROOF_DIR_INVALID" 61

# Proof file for the identifier is a dangling symlink.
iso_make_root "$TMP/root-proof-entry"
mkdir -m 700 "$TMP/root-proof-entry/.cbs-isolation"
ln -s "$TMP/proof-target-missing" "$TMP/root-proof-entry/.cbs-isolation/id1.proof"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/root-proof-entry"
iso_expect_blocked "PROOF_ENTRY_SYMLINK" "ID_ALREADY_USED" 61
[[ ! -e "$TMP/proof-target-missing" ]] || iso_fail "PROOF_ENTRY_TARGET_CREATED"
[[ ! -e "$TMP/root-proof-entry/id1" ]] || iso_fail "PROOF_ENTRY_PATH_CREATED"

[[ "$(worktree_count)" == "$WORKTREES_BEFORE" ]] || iso_fail "SYMLINKS_WORKTREE_REGISTERED"
iso_assert_source_untouched "SYMLINKS_SOURCE"

iso_pass "SYMLINKS"

# ---------------------------------------------------------------- collisions

# Existing non-empty directory.
mkdir -p "$ISO_ROOT/existing-dir"
printf '%s\n' "precious" > "$ISO_ROOT/existing-dir/data.txt"
EXISTING_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/existing-dir")"

iso_run create existing-dir "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_DIR" "PATH_EXISTS" 61
[[ "$(iso_tree_fingerprint "$ISO_ROOT/existing-dir")" == "$EXISTING_BEFORE" ]] || iso_fail "COLLISION_DIR_CHANGED"

# Existing empty directory is not adopted.
mkdir -p "$ISO_ROOT/empty-dir"
iso_run create empty-dir "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_EMPTY_DIR" "PATH_EXISTS" 61
[[ -z "$(ls -A "$ISO_ROOT/empty-dir")" ]] || iso_fail "COLLISION_EMPTY_DIR_ADOPTED"

# Existing regular file.
printf '%s\n' "file" > "$ISO_ROOT/existing-file"
iso_run create existing-file "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_FILE" "PATH_EXISTS" 61
[[ "$(cat "$ISO_ROOT/existing-file")" == "file" ]] || iso_fail "COLLISION_FILE_CHANGED"

# Pre-existing Git worktree (not created by CBS) at the target path.
git -C "$SOURCE" worktree add --detach "$ISO_ROOT/pre-existing" "$C2" >/dev/null 2>&1
PRE_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/pre-existing")"
PRE_COUNT="$(worktree_count)"

iso_run create pre-existing "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_WORKTREE" "PATH_EXISTS" 61
[[ "$(git -C "$ISO_ROOT/pre-existing" rev-parse HEAD)" == "$C2" ]] || iso_fail "COLLISION_WORKTREE_HEAD"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/pre-existing")" == "$PRE_BEFORE" ]] || iso_fail "COLLISION_WORKTREE_CHANGED"
[[ "$(worktree_count)" == "$PRE_COUNT" ]] || iso_fail "COLLISION_WORKTREE_COUNT"

# Stale registration (directory removed, Git entry kept): refused, never pruned.
git -C "$SOURCE" worktree add --detach "$ISO_ROOT/stale" "$C1" >/dev/null 2>&1
rm -r "$ISO_ROOT/stale"
STALE_COUNT="$(worktree_count)"

iso_run create stale "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_STALE_REGISTRATION" "PATH_REGISTERED" 61
[[ ! -e "$ISO_ROOT/stale" ]] || iso_fail "COLLISION_STALE_CREATED"
[[ "$(worktree_count)" == "$STALE_COUNT" ]] || iso_fail "COLLISION_STALE_PRUNED"

# Identifier already used by a completed cleanup: still refused.
mkdir -m 700 -p "$ISO_ROOT/.cbs-isolation"
printf '%s\n' "CBS_ISOLATION_CLEANED_AT=2026-01-01T00:00:00Z" > "$ISO_ROOT/.cbs-isolation/was-cleaned.cleaned"
iso_run create was-cleaned "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "COLLISION_CLEANED_ID" "ID_ALREADY_USED" 61
[[ ! -e "$ISO_ROOT/was-cleaned" ]] || iso_fail "COLLISION_CLEANED_CREATED"

iso_assert_source_untouched "COLLISIONS_SOURCE"

iso_pass "COLLISIONS"

# ---------------------------------------------------------------- failure and controlled rollback

# A required smudge filter that fails makes the checkout fail after the
# worktree has been reserved: CBS must roll back only what it created.
FAIL_SOURCE="$TMP/fail-source"
FAIL_ROOT="$TMP/fail-root"
iso_make_root "$FAIL_ROOT"
mkdir -p "$FAIL_SOURCE"
git -C "$FAIL_SOURCE" init -q
git -C "$FAIL_SOURCE" config user.name "CBS D04b-C Test"
git -C "$FAIL_SOURCE" config user.email "d04b-c-test@example.invalid"
git -C "$FAIL_SOURCE" remote add origin "$ISO_ORIGIN"
printf '%s\n' "* filter=cbsfail" > "$FAIL_SOURCE/.gitattributes"
printf '%s\n' "content" > "$FAIL_SOURCE/data.txt"
git -C "$FAIL_SOURCE" add .gitattributes data.txt
git -C "$FAIL_SOURCE" commit -qm "with filter"
FAIL_COMMIT="$(git -C "$FAIL_SOURCE" rev-parse HEAD)"
git -C "$FAIL_SOURCE" config filter.cbsfail.clean cat
git -C "$FAIL_SOURCE" config filter.cbsfail.smudge false
git -C "$FAIL_SOURCE" config filter.cbsfail.required true

# The source itself must stay fully usable (status works, clean tree).
git -C "$FAIL_SOURCE" status --porcelain >/dev/null 2>&1 || iso_fail "ROLLBACK_FIXTURE_STATUS"
[[ -z "$(git -C "$FAIL_SOURCE" status --porcelain)" ]] || iso_fail "ROLLBACK_FIXTURE_NOT_CLEAN"

FAIL_WORKTREES_BEFORE="$(git -C "$FAIL_SOURCE" worktree list --porcelain | grep -c '^worktree ' || true)"

iso_run create rollback "$FAIL_SOURCE" "$ISO_ORIGIN" "$FAIL_COMMIT" "$FAIL_ROOT"

[[ "$(iso_value RESULT)" == "FAIL" ]] || iso_fail "ROLLBACK_RESULT_$(iso_value RESULT)_$(iso_value REASON)"
[[ "$ISO_RC" -eq 69 ]] || iso_fail "ROLLBACK_RC_$ISO_RC"
[[ "$(iso_value REASON)" == "GIT_WORKTREE_ADD_FAILED" ]] || iso_fail "ROLLBACK_REASON_$(iso_value REASON)"
[[ "$(iso_value ROLLBACK)" == "DONE" ]] || iso_fail "ROLLBACK_FIELD_$(iso_value ROLLBACK)"
[[ ! -e "$FAIL_ROOT/rollback" ]] || iso_fail "ROLLBACK_PATH_REMAINS"
[[ "$(git -C "$FAIL_SOURCE" worktree list --porcelain | grep -c '^worktree ' || true)" == "$FAIL_WORKTREES_BEFORE" ]] ||
    iso_fail "ROLLBACK_WORKTREE_REMAINS"
[[ "$(git -C "$FAIL_SOURCE" rev-parse HEAD)" == "$FAIL_COMMIT" ]] || iso_fail "ROLLBACK_SOURCE_HEAD"
[[ -z "$(git -C "$FAIL_SOURCE" status --porcelain)" ]] || iso_fail "ROLLBACK_SOURCE_DIRTY"

# The proof is preserved as ABORTED and the identifier stays burnt.
grep -Fxq "CBS_ISOLATION_STATE=ABORTED" "$FAIL_ROOT/.cbs-isolation/rollback.proof" || iso_fail "ROLLBACK_PROOF_STATE"
grep -Fxq "CBS_ISOLATION_ABORT_REASON=GIT_WORKTREE_ADD_FAILED" "$FAIL_ROOT/.cbs-isolation/rollback.proof" ||
    iso_fail "ROLLBACK_PROOF_REASON"

iso_run create rollback "$FAIL_SOURCE" "$ISO_ORIGIN" "$FAIL_COMMIT" "$FAIL_ROOT"
iso_expect_blocked "ROLLBACK_ID_BURNT" "ID_ALREADY_USED" 61

# An aborted proof never authorizes a cleanup.
iso_run cleanup rollback "$FAIL_SOURCE" "$FAIL_ROOT"
iso_expect_blocked "ROLLBACK_CLEANUP_REFUSED" "PROOF_STATE_ABORTED" 67

iso_pass "FAILURE_ROLLBACK"

echo "${TEST_PREFIX}_RESULT=PASS"
