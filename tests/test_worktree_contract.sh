#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/worktree/contract.sh"

fail() {
    echo "TEST_WORKTREE_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_WORKTREE_CONTRACT_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"

[[ "$CBS_WORKTREE_CONTRACT_VERSION" == "1" ]] ||
    fail "VERSION"

echo "TEST_WORKTREE_CONTRACT_VERSION=PASS"

for state in \
    READY \
    MISSING \
    BRANCH_CONFLICT \
    PATH_CONFLICT \
    INVALID_REPOSITORY \
    UNKNOWN
do
    cbs_worktree_state_is_valid "$state" ||
        fail "STATE_$state"
done

echo "TEST_WORKTREE_CONTRACT_STATES=PASS"

for state in \
    ATTACHED \
    DETACHED \
    ABSENT \
    UNKNOWN
do
    cbs_worktree_branch_state_is_valid "$state" ||
        fail "BRANCH_STATE_$state"
done

echo "TEST_WORKTREE_CONTRACT_BRANCH_STATES=PASS"

[[ "$(cbs_worktree_action_for_state READY)" == "REUSE" ]] ||
    fail "READY_ACTION"

[[ "$(cbs_worktree_action_for_state MISSING)" == "CREATE" ]] ||
    fail "MISSING_ACTION"

for state in \
    BRANCH_CONFLICT \
    PATH_CONFLICT \
    INVALID_REPOSITORY \
    UNKNOWN
do
    [[ "$(cbs_worktree_action_for_state "$state")" == "BLOCK" ]] ||
        fail "BLOCK_ACTION_$state"
done

echo "TEST_WORKTREE_CONTRACT_ACTIONS=PASS"

[[ "$CBS_RC_WORKTREE_BRANCH_CONFLICT" -eq 60 ]]
[[ "$CBS_RC_WORKTREE_PATH_CONFLICT" -eq 61 ]]
[[ "$CBS_RC_WORKTREE_INVALID_REPOSITORY" -eq 62 ]]
[[ "$CBS_RC_WORKTREE_UNKNOWN" -eq 63 ]]
[[ "$CBS_RC_WORKTREE_USAGE" -eq 64 ]]

echo "TEST_WORKTREE_CONTRACT_RETURN_CODES=PASS"

echo "TEST_WORKTREE_CONTRACT_RESULT=PASS"
