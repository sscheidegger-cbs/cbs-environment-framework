#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_CREATE"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

iso_fixture_init
CBS="$ROOT/bin/cbs"

echo "${TEST_PREFIX}_FIXTURE=PASS"

[[ "$C1" != "$C2" ]] || iso_fail "FIXTURE_COMMITS"

iso_snapshot_source

# ---------------------------------------------------------------- create at exact commit

iso_run create alpha "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_pass "CREATE"

WT="$ISO_ROOT/alpha"

[[ "$(iso_value PATH)" == "$WT" ]] || iso_fail "CREATE_PATH_FIELD"
[[ "$(iso_value ID)" == "alpha" ]] || iso_fail "CREATE_ID_FIELD"
[[ "$(iso_value COMMIT_EXPECTED)" == "$C1" ]] || iso_fail "CREATE_EXPECTED_FIELD"
[[ "$(iso_value COMMIT_OBSERVED)" == "$C1" ]] || iso_fail "CREATE_OBSERVED_FIELD"
[[ "$(iso_value GIT_STATUS)" == "CLEAN" ]] || iso_fail "CREATE_GIT_STATUS_FIELD"
[[ "$(iso_value REASON)" == "NONE" ]] || iso_fail "CREATE_REASON_FIELD"
[[ "$(iso_value RC)" == "0" ]] || iso_fail "CREATE_RC_FIELD"
TOKEN_PATTERN='^[0-9a-f]{32}$'
[[ "$(iso_value PROOF_ID)" =~ $TOKEN_PATTERN ]] || iso_fail "CREATE_PROOF_ID_FIELD"

[[ -d "$WT" && ! -L "$WT" ]] || iso_fail "CREATE_PATH_EXISTS"

# Exact commit: the checked out content is the one of C1, not of source HEAD (C2).
[[ "$(git -C "$WT" rev-parse HEAD)" == "$C1" ]] || iso_fail "CREATE_HEAD_EXACT"
[[ "$(cat "$WT/file.txt")" == "first" ]] || iso_fail "CREATE_CONTENT_EXACT"
[[ ! -e "$WT/extra.txt" ]] || iso_fail "CREATE_CONTENT_NOT_C2"

iso_pass "EXACT_COMMIT"

# ---------------------------------------------------------------- detached HEAD

[[ -z "$(git -C "$WT" branch --show-current)" ]] || iso_fail "DETACHED_NOT_DETACHED"
[[ -z "$(git -C "$WT" status --porcelain)" ]] || iso_fail "DETACHED_NOT_CLEAN"

git -C "$SOURCE" worktree list --porcelain | grep -Fxq "worktree $WT" ||
    iso_fail "DETACHED_NOT_LISTED"
git -C "$SOURCE" worktree list --porcelain | grep -Fxq "detached" ||
    iso_fail "DETACHED_MARKER"

iso_pass "DETACHED_HEAD"

# ---------------------------------------------------------------- provenance proof

PROOF="$ISO_ROOT/.cbs-isolation/alpha.proof"

[[ -f "$PROOF" && ! -L "$PROOF" ]] || iso_fail "PROOF_MISSING"

grep -Fxq "CBS_ISOLATION_PROOF_VERSION=1" "$PROOF" || iso_fail "PROOF_VERSION"
grep -Fxq "CBS_ISOLATION_ID=alpha" "$PROOF" || iso_fail "PROOF_ID"
grep -Fxq "CBS_ISOLATION_CREATED_BY=CBS" "$PROOF" || iso_fail "PROOF_CREATED_BY"
grep -Fxq "CBS_ISOLATION_STATE=READY" "$PROOF" || iso_fail "PROOF_STATE"
grep -Fxq "CBS_ISOLATION_SOURCE_REPOSITORY=$SOURCE" "$PROOF" || iso_fail "PROOF_SOURCE"
grep -Fxq "CBS_ISOLATION_ORIGIN=$ISO_ORIGIN" "$PROOF" || iso_fail "PROOF_ORIGIN"
grep -Fxq "CBS_ISOLATION_COMMIT=$C1" "$PROOF" || iso_fail "PROOF_COMMIT"
grep -Fxq "CBS_ISOLATION_ROOT=$ISO_ROOT" "$PROOF" || iso_fail "PROOF_ROOT"
grep -Fxq "CBS_ISOLATION_PATH=$WT" "$PROOF" || iso_fail "PROOF_PATH"
grep -Fxq "CBS_ISOLATION_RESOURCE_PROOF_FILE=$PROOF" "$PROOF" || iso_fail "PROOF_RESOURCE"
grep -Fxq "CBS_ISOLATION_TOKEN=$(iso_value PROOF_ID)" "$PROOF" || iso_fail "PROOF_TOKEN"
grep -Eq '^CBS_ISOLATION_CREATED_AT=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$PROOF" ||
    iso_fail "PROOF_CREATED_AT"

PROOF_GIT_DIR="$(sed -n 's/^CBS_ISOLATION_WORKTREE_GIT_DIR=//p' "$PROOF")"
[[ -d "$PROOF_GIT_DIR" ]] || iso_fail "PROOF_GIT_DIR_EXISTS"
[[ "$PROOF_GIT_DIR" == "$(cd -P "$SOURCE/.git" && pwd -P)/worktrees/"* ]] ||
    iso_fail "PROOF_GIT_DIR_ASSOCIATION"

# The proof lives outside the isolated worktree.
[[ ! -e "$WT/.cbs-isolation" ]] || iso_fail "PROOF_INSIDE_WORKTREE"

iso_pass "PROVENANCE"

# ---------------------------------------------------------------- source preserved

iso_assert_source_untouched "SOURCE_PRESERVED_AFTER_CREATE"

iso_pass "SOURCE_PRESERVED"

# ---------------------------------------------------------------- verify (read-only)

iso_run verify alpha "$SOURCE" "$ISO_ROOT"
iso_expect_pass "VERIFY"
[[ "$(iso_value COMMIT_OBSERVED)" == "$C1" ]] || iso_fail "VERIFY_OBSERVED"
[[ "$(iso_value GIT_STATUS)" == "CLEAN" ]] || iso_fail "VERIFY_STATUS"

iso_assert_source_untouched "SOURCE_PRESERVED_AFTER_VERIFY"

iso_pass "VERIFY"

# ---------------------------------------------------------------- no implicit reuse

TREE_BEFORE="$(iso_tree_fingerprint "$WT")"
PROOF_BEFORE="$(cat "$PROOF")"

iso_run create alpha "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "REUSE_SAME_PARAMETERS" "ID_ALREADY_USED" 61

[[ "$(iso_tree_fingerprint "$WT")" == "$TREE_BEFORE" ]] || iso_fail "REUSE_TREE_CHANGED"
[[ "$(cat "$PROOF")" == "$PROOF_BEFORE" ]] || iso_fail "REUSE_PROOF_CHANGED"

iso_run create alpha "$SOURCE" "$ISO_ORIGIN" "$C2" "$ISO_ROOT"
iso_expect_blocked "REUSE_OTHER_COMMIT" "ID_ALREADY_USED" 61

[[ "$(git -C "$WT" rev-parse HEAD)" == "$C1" ]] || iso_fail "REUSE_HEAD_CHANGED"

iso_pass "NO_IMPLICIT_REUSE"

# ---------------------------------------------------------------- second isolation at another commit

iso_run create beta "$SOURCE" "$ISO_ORIGIN" "$C2" "$ISO_ROOT"
iso_expect_pass "CREATE_SECOND"

[[ "$(git -C "$ISO_ROOT/beta" rev-parse HEAD)" == "$C2" ]] || iso_fail "SECOND_HEAD"
[[ "$(git -C "$WT" rev-parse HEAD)" == "$C1" ]] || iso_fail "FIRST_HEAD_AFTER_SECOND"
[[ "$(iso_value PROOF_ID)" != "$(sed -n 's/^CBS_ISOLATION_TOKEN=//p' "$PROOF")" ]] ||
    iso_fail "SECOND_TOKEN_UNIQUE"

iso_assert_source_untouched "SOURCE_PRESERVED_AFTER_SECOND"

iso_pass "SECOND_ISOLATION"

# ---------------------------------------------------------------- invalid commits

BLOB="$(git -C "$SOURCE" rev-parse "$C1:file.txt")"
TREE="$(git -C "$SOURCE" rev-parse "$C1^{tree}")"
git -C "$SOURCE" tag -a annotated-tag -m "annotated" "$C1"
TAG_OBJECT="$(git -C "$SOURCE" rev-parse annotated-tag)"
ABSENT="0123456789abcdef0123456789abcdef01234567"
UPPER="$(printf '%s' "$C1" | tr 'a-f' 'A-F')"

iso_snapshot_source

for case_name in \
    SHORT:"${C1:0:12}" \
    REF_HEAD:HEAD \
    REF_BRANCH:dev-branch \
    REF_TAG:annotated-tag \
    PARENT_EXPR:"${C2}~1" \
    UPPERCASE:"$UPPER" \
    EMPTY: \
    GARBAGE:"not-a-commit"
do
    label="${case_name%%:*}"
    value="${case_name#*:}"

    iso_run create "bad-$label" "$SOURCE" "$ISO_ORIGIN" "$value" "$ISO_ROOT"

    if [[ "$label" == "EMPTY" ]]; then
        iso_expect_blocked "COMMIT_$label" "USAGE" 64
    else
        iso_expect_blocked "COMMIT_$label" "COMMIT_NOT_FULL_SHA" 65
    fi

    [[ ! -e "$ISO_ROOT/bad-$label" ]] || iso_fail "COMMIT_${label}_PATH_CREATED"
    [[ ! -e "$ISO_ROOT/.cbs-isolation/bad-$label.proof" ]] || iso_fail "COMMIT_${label}_PROOF_CREATED"
done

iso_run create bad-absent "$SOURCE" "$ISO_ORIGIN" "$ABSENT" "$ISO_ROOT"
iso_expect_blocked "COMMIT_ABSENT" "COMMIT_NOT_AVAILABLE" 65

iso_run create bad-blob "$SOURCE" "$ISO_ORIGIN" "$BLOB" "$ISO_ROOT"
iso_expect_blocked "COMMIT_BLOB" "COMMIT_NOT_A_COMMIT" 65

iso_run create bad-tree "$SOURCE" "$ISO_ORIGIN" "$TREE" "$ISO_ROOT"
iso_expect_blocked "COMMIT_TREE" "COMMIT_NOT_A_COMMIT" 65

iso_run create bad-tag "$SOURCE" "$ISO_ORIGIN" "$TAG_OBJECT" "$ISO_ROOT"
iso_expect_blocked "COMMIT_TAG_OBJECT" "COMMIT_NOT_A_COMMIT" 65

[[ "$(iso_value GIT_STATUS)" == "NOT_RUN" ]] || iso_fail "COMMIT_NOT_RUN_STATUS"
[[ "$(iso_value COMMIT_OBSERVED)" == "NOT_RUN" ]] || iso_fail "COMMIT_NOT_RUN_OBSERVED"
[[ "$(iso_value PROOF_ID)" == "NOT_RUN" ]] || iso_fail "COMMIT_NOT_RUN_PROOF"

for name in bad-absent bad-blob bad-tree bad-tag; do
    [[ ! -e "$ISO_ROOT/$name" ]] || iso_fail "COMMIT_${name}_PATH_CREATED"
done

iso_assert_source_untouched "SOURCE_PRESERVED_AFTER_COMMIT_REFUSALS"

iso_pass "INVALID_COMMITS"

# ---------------------------------------------------------------- invalid origins

iso_run create wrong-origin "$SOURCE" "https://example.invalid/other/repository.git" "$C1" "$ISO_ROOT"
iso_expect_blocked "ORIGIN_MISMATCH" "ORIGIN_MISMATCH" 66
[[ ! -e "$ISO_ROOT/wrong-origin" ]] || iso_fail "ORIGIN_MISMATCH_PATH_CREATED"

# Prefix / case variations are different origins.
iso_run create wrong-origin "$SOURCE" "${ISO_ORIGIN}x" "$C1" "$ISO_ROOT"
iso_expect_blocked "ORIGIN_PREFIX" "ORIGIN_MISMATCH" 66

iso_run create wrong-origin "$SOURCE" "$(printf '%s' "$ISO_ORIGIN" | tr 'a-z' 'A-Z')" "$C1" "$ISO_ROOT"
iso_expect_blocked "ORIGIN_CASE" "ORIGIN_MISMATCH" 66

# Repository without origin.
NO_ORIGIN="$TMP/no-origin"
mkdir -p "$NO_ORIGIN"
git -C "$NO_ORIGIN" init -q
git -C "$NO_ORIGIN" config user.name "CBS D04b-C Test"
git -C "$NO_ORIGIN" config user.email "d04b-c-test@example.invalid"
printf '%s\n' "x" > "$NO_ORIGIN/x.txt"
git -C "$NO_ORIGIN" add x.txt
git -C "$NO_ORIGIN" commit -qm "x"
NO_ORIGIN_COMMIT="$(git -C "$NO_ORIGIN" rev-parse HEAD)"

iso_run create no-origin "$NO_ORIGIN" "$ISO_ORIGIN" "$NO_ORIGIN_COMMIT" "$ISO_ROOT"
iso_expect_blocked "ORIGIN_MISSING" "ORIGIN_MISSING" 66
[[ ! -e "$ISO_ROOT/no-origin" ]] || iso_fail "ORIGIN_MISSING_PATH_CREATED"

# Commit of another repository is not available in this source.
OTHER_COMMIT="$NO_ORIGIN_COMMIT"
iso_run create foreign-commit "$SOURCE" "$ISO_ORIGIN" "$OTHER_COMMIT" "$ISO_ROOT"
iso_expect_blocked "FOREIGN_COMMIT" "COMMIT_NOT_AVAILABLE" 65

# Origin with embedded credentials: accepted, never printed, never stored.
CRED_SOURCE="$TMP/cred-source"
CRED_ORIGIN="https://ci-user:s3cr3t-fixture-token@example.invalid/cbs/cred.git"
git clone -q "$SOURCE" "$CRED_SOURCE" 2>/dev/null
git -C "$CRED_SOURCE" remote set-url origin "$CRED_ORIGIN"
CRED_COMMIT="$(git -C "$CRED_SOURCE" rev-parse HEAD)"

iso_run create cred-ok "$CRED_SOURCE" "$CRED_ORIGIN" "$CRED_COMMIT" "$ISO_ROOT"
iso_expect_pass "ORIGIN_CREDENTIALS"

if grep -Fq "s3cr3t-fixture-token" <<<"$ISO_OUT"; then
    iso_fail "SECRET_LEAK_STDOUT"
fi

if grep -Fq "s3cr3t-fixture-token" "$ISO_ROOT/.cbs-isolation/cred-ok.proof"; then
    iso_fail "SECRET_LEAK_PROOF"
fi

iso_run create cred-bad "$CRED_SOURCE" "https://ci-user:another-secret-value@example.invalid/cbs/cred.git" "$CRED_COMMIT" "$ISO_ROOT"
iso_expect_blocked "ORIGIN_CREDENTIALS_MISMATCH" "ORIGIN_MISMATCH" 66

if grep -Fq "another-secret-value" <<<"$ISO_OUT"; then
    iso_fail "SECRET_LEAK_MISMATCH_OUTPUT"
fi

if grep -Fq "s3cr3t-fixture-token" <<<"$ISO_OUT"; then
    iso_fail "SECRET_LEAK_MISMATCH_OUTPUT_ACTUAL"
fi

iso_assert_source_untouched "SOURCE_PRESERVED_AFTER_ORIGIN_REFUSALS"

iso_pass "INVALID_ORIGINS"

# ---------------------------------------------------------------- invalid source / usage

iso_run create src-missing "$TMP/does-not-exist" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "SOURCE_MISSING" "SOURCE_MISSING" 62

mkdir -p "$TMP/not-a-repo"
iso_run create src-not-repo "$TMP/not-a-repo" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "SOURCE_NOT_REPOSITORY" "SOURCE_NOT_REPOSITORY" 62

mkdir -p "$SOURCE/subdir"
iso_run create src-subdir "$SOURCE/subdir" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "SOURCE_NOT_TOPLEVEL" "SOURCE_NOT_TOPLEVEL" 62
rmdir "$SOURCE/subdir"

iso_run create src-relative "source" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "SOURCE_RELATIVE" "SOURCE_NOT_ABSOLUTE" 62

iso_run create "bad/id" "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "ID_SLASH" "ID_INVALID" 64

iso_run create "../escape" "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "ID_TRAVERSAL" "ID_INVALID" 64
[[ ! -e "$TMP/escape" ]] || iso_fail "ID_TRAVERSAL_CREATED"

iso_run create "" "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "USAGE_EMPTY_ID" "USAGE" 64

iso_run create only-one-arg
iso_expect_blocked "USAGE_ARGS" "USAGE" 64

iso_run create a b c d e f
iso_expect_blocked "USAGE_TOO_MANY_ARGS" "USAGE" 64

iso_run frobnicate
iso_expect_blocked "USAGE_UNKNOWN_COMMAND" "USAGE" 64

iso_run
iso_expect_blocked "USAGE_NO_COMMAND" "USAGE" 64

iso_assert_source_untouched "SOURCE_PRESERVED_AFTER_USAGE_REFUSALS"

iso_pass "INVALID_SOURCE_AND_USAGE"

# ---------------------------------------------------------------- non-regression of existing contracts

# Existing observer sees the isolated worktrees as DETACHED and CLEAN.
CHECK_OUT="$("$CBS" worktree check "$SOURCE")"

grep -Fq "CBS_WORKTREE_OBSERVATION_RESULT=PASS" <<<"$CHECK_OUT" || iso_fail "NONREG_OBSERVER_RESULT"
grep -Fq "CBS_WORKTREE_PATH=$WT" <<<"$CHECK_OUT" || iso_fail "NONREG_OBSERVER_PATH"
grep -Fq "CBS_WORKTREE_BRANCH_STATE=DETACHED" <<<"$CHECK_OUT" || iso_fail "NONREG_OBSERVER_DETACHED"
grep -Fq "CBS_WORKTREE_HEAD=$C1" <<<"$CHECK_OUT" || iso_fail "NONREG_OBSERVER_HEAD"

# Existing 'worktree ensure' keeps refusing a path it does not recognise.
set +e
ENSURE_OUT="$("$CBS" worktree ensure "$SOURCE" "$WT" dev-branch 2>&1)"
ENSURE_RC=$?
set -e

[[ "$ENSURE_RC" -eq 61 ]] || iso_fail "NONREG_ENSURE_PATH_CONFLICT_RC"
grep -Fq "CBS_WORKTREE_STATE=PATH_CONFLICT" <<<"$ENSURE_OUT" || iso_fail "NONREG_ENSURE_PATH_CONFLICT_STATE"
[[ "$(git -C "$WT" rev-parse HEAD)" == "$C1" ]] || iso_fail "NONREG_ENSURE_HEAD_CHANGED"

# Existing 'worktree ensure' keeps creating attached worktrees.
ENSURE_OUT="$("$CBS" worktree ensure "$SOURCE" "$TMP/ensured" dev-branch)"
grep -Fq "CBS_WORKTREE_ACTION=CREATE" <<<"$ENSURE_OUT" || iso_fail "NONREG_ENSURE_CREATE"
[[ "$(git -C "$TMP/ensured" branch --show-current)" == "dev-branch" ]] || iso_fail "NONREG_ENSURE_BRANCH"

# The isolation capability is not exposed through the CBS entry point.
set +e
"$CBS" worktree isolate >/dev/null 2>&1
ISOLATE_RC=$?
set -e
[[ "$ISOLATE_RC" -eq 2 ]] || iso_fail "NONREG_CLI_UNCHANGED"

iso_pass "NON_REGRESSION_EXISTING_CONTRACTS"

echo "${TEST_PREFIX}_RESULT=PASS"
