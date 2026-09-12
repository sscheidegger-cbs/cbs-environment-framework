#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OBSERVER="$ROOT/cbs/workspace/workspace_observer.sh"

WORKSPACE="/home/sscheidegger/projects"
REPOSITORY="$WORKSPACE/core-platform"
EXPECTED_ORIGIN="git@gitlab.com:core3234722/core-platform.git"

fail() {
    echo "TEST_WORKSPACE_OBSERVER_RESULT=FAIL" >&2
    echo "TEST_WORKSPACE_OBSERVER_FAILURE=$1" >&2
    exit 1
}

OUTPUT="$(
    "$OBSERVER" \
        "$WORKSPACE" \
        "$REPOSITORY" \
        "$EXPECTED_ORIGIN"
)"

grep -Fq \
    "CBS_WORKSPACE_PATH=$WORKSPACE" \
    <<<"$OUTPUT" ||
    fail "WORKSPACE_PATH"

grep -Fq \
    'CBS_WORKSPACE_PATH_CLASS=DIRECTORY' \
    <<<"$OUTPUT" ||
    fail "WORKSPACE_CLASS"

grep -Fq \
    'CBS_WORKSPACE_STATE=READY' \
    <<<"$OUTPUT" ||
    fail "WORKSPACE_STATE"

grep -Fq \
    "CBS_REPOSITORY_PATH=$REPOSITORY" \
    <<<"$OUTPUT" ||
    fail "REPOSITORY_PATH"

grep -Fq \
    "CBS_REPOSITORY_EXPECTED_ORIGIN=$EXPECTED_ORIGIN" \
    <<<"$OUTPUT" ||
    fail "EXPECTED_ORIGIN"

grep -Fq \
    "CBS_REPOSITORY_OBSERVED_ORIGIN=$EXPECTED_ORIGIN" \
    <<<"$OUTPUT" ||
    fail "OBSERVED_ORIGIN"

grep -Fq \
    'CBS_REPOSITORY_WORKTREE_STATE=DIRTY' \
    <<<"$OUTPUT" ||
    fail "REAL_DIRTY_STATE"

grep -Fq \
    'CBS_REPOSITORY_STATE=READY' \
    <<<"$OUTPUT" ||
    fail "REPOSITORY_STATE"

set +e
MISSING_OUTPUT="$(
    "$OBSERVER" \
        "$WORKSPACE" \
        "$WORKSPACE/does-not-exist" \
        "$EXPECTED_ORIGIN" \
        2>&1
)"
MISSING_RC=$?
set -e

[[ "$MISSING_RC" -eq 50 ]] ||
    fail "MISSING_REPOSITORY_RC"

grep -Fq \
    'CBS_REPOSITORY_STATE=MISSING' \
    <<<"$MISSING_OUTPUT" ||
    fail "MISSING_REPOSITORY_STATE"

set +e
NO_ARGS_OUTPUT="$("$OBSERVER" 2>&1)"
NO_ARGS_RC=$?
set -e

[[ "$NO_ARGS_RC" -eq 64 ]] ||
    fail "USAGE_RC"

grep -Fq \
    'CBS_WORKSPACE_ERROR=WORKSPACE_PATH_REQUIRED' \
    <<<"$NO_ARGS_OUTPUT" ||
    fail "USAGE_ERROR"

echo "TEST_WORKSPACE_OBSERVER_REAL=PASS"
echo "TEST_WORKSPACE_OBSERVER_DIRTY_NON_BLOCKING=PASS"
echo "TEST_WORKSPACE_OBSERVER_MISSING_REPOSITORY=PASS"
echo "TEST_WORKSPACE_OBSERVER_USAGE=PASS"
echo "TEST_WORKSPACE_OBSERVER_RESULT=PASS"
