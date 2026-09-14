#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBSERVER="$ROOT/cbs/worktree/worktree_observer.sh"
CORE="/home/sscheidegger/projects/core-platform"

fail() {
    echo "TEST_WORKTREE_OBSERVER_RESULT=FAIL" >&2
    echo "TEST_WORKTREE_OBSERVER_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/worktree/contract.sh"

OUTPUT="$("$OBSERVER" "$CORE")"

grep -Fq \
    'CBS_WORKTREE_REPOSITORY=/home/sscheidegger/projects/core-platform' \
    <<<"$OUTPUT" ||
    fail "REAL_REPOSITORY"

grep -Fq \
    'CBS_WORKTREE_PATH=/home/sscheidegger/projects/core-platform' \
    <<<"$OUTPUT" ||
    fail "PRIMARY_WORKTREE"

grep -Fq \
    'CBS_WORKTREE_BRANCH=fix/b06-keycloak-kong-e2e' \
    <<<"$OUTPUT" ||
    fail "PRIMARY_BRANCH"

grep -Fq \
    'CBS_WORKTREE_PATH=/home/sscheidegger/projects/b17-step13-3-fresh-worktree' \
    <<<"$OUTPUT" ||
    fail "FIRST_DETACHED"

grep -Fq \
    'CBS_WORKTREE_PATH=/home/sscheidegger/projects/b17-step13-clean-worktree' \
    <<<"$OUTPUT" ||
    fail "SECOND_DETACHED"

grep -Fq \
    'CBS_WORKTREE_PATH=/home/sscheidegger/projects/core-platform-release' \
    <<<"$OUTPUT" ||
    fail "RELEASE_WORKTREE"

DETACHED_COUNT="$(
    grep -Fc 'CBS_WORKTREE_BRANCH_STATE=DETACHED' <<<"$OUTPUT"
)"

[[ "$DETACHED_COUNT" -ge 3 ]] ||
    fail "DETACHED_COUNT"

EXPECTED_WORKTREE_COUNT="$(
    git -C "$CORE" worktree list --porcelain |
    grep -c '^worktree '
)"

grep -Fq "CBS_WORKTREE_COUNT=$EXPECTED_WORKTREE_COUNT" <<<"$OUTPUT" ||
    fail "WORKTREE_COUNT"

grep -Fq 'CBS_WORKTREE_OBSERVATION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "OBSERVATION_RESULT"

set +e
MISSING_OUTPUT="$("$OBSERVER" 2>&1)"
MISSING_RC=$?
set -e

[[ "$MISSING_RC" -eq "$CBS_RC_WORKTREE_USAGE" ]] ||
    fail "MISSING_REPOSITORY_RC"

grep -Fq \
    'CBS_WORKTREE_ERROR=REPOSITORY_REQUIRED' \
    <<<"$MISSING_OUTPUT" ||
    fail "MISSING_REPOSITORY_ERROR"

set +e
INVALID_OUTPUT="$("$OBSERVER" /tmp/cbs-b17-invalid-repository 2>&1)"
INVALID_RC=$?
set -e

[[ "$INVALID_RC" -eq "$CBS_RC_WORKTREE_INVALID_REPOSITORY" ]] ||
    fail "INVALID_REPOSITORY_RC"

grep -Fq \
    'CBS_WORKTREE_STATE=INVALID_REPOSITORY' \
    <<<"$INVALID_OUTPUT" ||
    fail "INVALID_REPOSITORY_STATE"

echo "TEST_WORKTREE_OBSERVER_REAL=PASS"
echo "TEST_WORKTREE_OBSERVER_ATTACHED=PASS"
echo "TEST_WORKTREE_OBSERVER_DETACHED=PASS"
echo "TEST_WORKTREE_OBSERVER_USAGE=PASS"
echo "TEST_WORKTREE_OBSERVER_INVALID_REPOSITORY=PASS"
echo "TEST_WORKTREE_OBSERVER_RESULT=PASS"
