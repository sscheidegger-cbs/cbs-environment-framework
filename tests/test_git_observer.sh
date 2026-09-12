#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_LIB="$ROOT/cbs/context/context.sh"
GIT_LIB="$ROOT/cbs/context/git_observer.sh"
CONTEXT="$ROOT/config/contexts/core-platform.local.env"

source "$CONTEXT_LIB"
source "$GIT_LIB"

fail() {
    echo "TEST_GIT_OBSERVER_RESULT=FAIL" >&2
    echo "TEST_GIT_OBSERVER_FAILURE=$1" >&2
    exit 1
}

cbs_context_load "$CONTEXT"
cbs_git_observe_and_compare

[[ "$CBS_OBSERVED_REPOSITORY_PATH" == "$CBS_CONTEXT_REPOSITORY_PATH" ]] || fail "REPOSITORY_PATH"
[[ "$CBS_OBSERVED_BRANCH" == "$CBS_CONTEXT_BRANCH" ]] || fail "BRANCH"
[[ -n "$CBS_OBSERVED_HEAD" ]] || fail "HEAD_EMPTY"
[[ "$CBS_CONTEXT_DRIFT" == "NO" ]] || fail "UNEXPECTED_DRIFT"
[[ "$CBS_CONTEXT_DRIFT_REPOSITORY_PATH" == "NO" ]] || fail "UNEXPECTED_PATH_DRIFT"
[[ "$CBS_CONTEXT_DRIFT_BRANCH" == "NO" ]] || fail "UNEXPECTED_BRANCH_DRIFT"

ORIGINAL_BRANCH="$CBS_CONTEXT_BRANCH"
CBS_CONTEXT_BRANCH="invalid-test-branch"
cbs_git_compare_context

[[ "$CBS_CONTEXT_DRIFT" == "YES" ]] || fail "DRIFT_NOT_DETECTED"
[[ "$CBS_CONTEXT_DRIFT_BRANCH" == "YES" ]] || fail "BRANCH_DRIFT_NOT_DETECTED"
[[ "$CBS_CONTEXT_DRIFT_REPOSITORY_PATH" == "NO" ]] || fail "FALSE_PATH_DRIFT"

CBS_CONTEXT_BRANCH="$ORIGINAL_BRANCH"

echo "TEST_GIT_OBSERVER_READ=PASS"
echo "TEST_GIT_OBSERVER_HEAD=PASS"
echo "TEST_GIT_OBSERVER_NO_DRIFT=PASS"
echo "TEST_GIT_OBSERVER_BRANCH_DRIFT=PASS"
echo "TEST_GIT_OBSERVER_RESULT=PASS"
