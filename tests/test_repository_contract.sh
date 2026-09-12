#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/workspace/repository_contract.sh"

fail() {
    echo "TEST_REPOSITORY_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_REPOSITORY_CONTRACT_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"

[[ "$CBS_REPOSITORY_CONTRACT_VERSION" == "1" ]] ||
    fail "VERSION"

[[ "$CBS_REPOSITORY_RC_OK" -eq 0 ]] ||
    fail "RC_OK"

[[ "$CBS_REPOSITORY_RC_MISSING" -eq 50 ]] ||
    fail "RC_MISSING"

[[ "$CBS_REPOSITORY_RC_NOT_GIT" -eq 51 ]] ||
    fail "RC_NOT_GIT"

[[ "$CBS_REPOSITORY_RC_REMOTE_MISMATCH" -eq 52 ]] ||
    fail "RC_REMOTE_MISMATCH"

[[ "$CBS_REPOSITORY_RC_UNKNOWN" -eq 53 ]] ||
    fail "RC_UNKNOWN"

[[ "$CBS_REPOSITORY_RC_USAGE" -eq 64 ]] ||
    fail "RC_USAGE"

TMP="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP"
}

trap cleanup EXIT

EXPECTED_ORIGIN="git@example.invalid:cbs/test.git"

STATE="$(
    cbs_repository_state \
        "$TMP/missing" \
        "$EXPECTED_ORIGIN"
)"

[[ "$STATE" == "$CBS_REPOSITORY_MISSING" ]] ||
    fail "MISSING_STATE"

mkdir "$TMP/not-git"

STATE="$(
    cbs_repository_state \
        "$TMP/not-git" \
        "$EXPECTED_ORIGIN"
)"

[[ "$STATE" == "$CBS_REPOSITORY_NOT_GIT" ]] ||
    fail "NOT_GIT_STATE"

mkdir "$TMP/repository"

git -C "$TMP/repository" init -q
git -C "$TMP/repository" remote add origin "$EXPECTED_ORIGIN"

STATE="$(
    cbs_repository_state \
        "$TMP/repository" \
        "$EXPECTED_ORIGIN"
)"

[[ "$STATE" == "$CBS_REPOSITORY_READY" ]] ||
    fail "READY_STATE"

STATE="$(
    cbs_repository_state \
        "$TMP/repository" \
        "git@example.invalid:cbs/other.git"
)"

[[ "$STATE" == "$CBS_REPOSITORY_REMOTE_MISMATCH" ]] ||
    fail "REMOTE_MISMATCH_STATE"

STATE="$(
    cbs_repository_state "" ""
)"

[[ "$STATE" == "$CBS_REPOSITORY_UNKNOWN" ]] ||
    fail "UNKNOWN_STATE"

WORKTREE_STATE="$(
    cbs_repository_worktree_state "$TMP/repository"
)"

[[ "$WORKTREE_STATE" == "$CBS_REPOSITORY_WORKTREE_CLEAN" ]] ||
    fail "CLEAN_WORKTREE_STATE"

touch "$TMP/repository/untracked.txt"

WORKTREE_STATE="$(
    cbs_repository_worktree_state "$TMP/repository"
)"

[[ "$WORKTREE_STATE" == "$CBS_REPOSITORY_WORKTREE_DIRTY" ]] ||
    fail "DIRTY_WORKTREE_STATE"

set +e
cbs_repository_rc_from_state "$CBS_REPOSITORY_READY"
RC=$?
set -e

[[ "$RC" -eq "$CBS_REPOSITORY_RC_OK" ]] ||
    fail "READY_RC"

set +e
cbs_repository_rc_from_state "$CBS_REPOSITORY_MISSING"
RC=$?
set -e

[[ "$RC" -eq "$CBS_REPOSITORY_RC_MISSING" ]] ||
    fail "MISSING_RC"

set +e
cbs_repository_rc_from_state "$CBS_REPOSITORY_NOT_GIT"
RC=$?
set -e

[[ "$RC" -eq "$CBS_REPOSITORY_RC_NOT_GIT" ]] ||
    fail "NOT_GIT_RC"

set +e
cbs_repository_rc_from_state "$CBS_REPOSITORY_REMOTE_MISMATCH"
RC=$?
set -e

[[ "$RC" -eq "$CBS_REPOSITORY_RC_REMOTE_MISMATCH" ]] ||
    fail "REMOTE_MISMATCH_RC"

set +e
cbs_repository_rc_from_state "$CBS_REPOSITORY_UNKNOWN"
RC=$?
set -e

[[ "$RC" -eq "$CBS_REPOSITORY_RC_UNKNOWN" ]] ||
    fail "UNKNOWN_RC"

echo "TEST_REPOSITORY_CONTRACT_VERSION=PASS"
echo "TEST_REPOSITORY_CONTRACT_MISSING=PASS"
echo "TEST_REPOSITORY_CONTRACT_NOT_GIT=PASS"
echo "TEST_REPOSITORY_CONTRACT_READY=PASS"
echo "TEST_REPOSITORY_CONTRACT_REMOTE_MISMATCH=PASS"
echo "TEST_REPOSITORY_CONTRACT_WORKTREE_STATE=PASS"
echo "TEST_REPOSITORY_CONTRACT_RETURN_CODES=PASS"
echo "TEST_REPOSITORY_CONTRACT_RESULT=PASS"
