#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/cbs/worktree/worktree_observer.sh"

fail() {
    echo "TEST_WORKTREE_MUTATION_GATE_RESULT=FAIL" >&2
    echo "TEST_WORKTREE_MUTATION_GATE_FAILURE=$1" >&2
    exit 1
}

[[ "$(cbs_worktree_decide READY ATTACHED)" == "REUSE" ]] ||
    fail "READY_ATTACHED"

[[ "$(cbs_worktree_decide MISSING ABSENT)" == "CREATE" ]] ||
    fail "MISSING_ABSENT"

[[ "$(cbs_worktree_decide BRANCH_CONFLICT ATTACHED)" == "BLOCK" ]] ||
    fail "BRANCH_CONFLICT"

[[ "$(cbs_worktree_decide PATH_CONFLICT ABSENT)" == "BLOCK" ]] ||
    fail "PATH_CONFLICT"

[[ "$(cbs_worktree_decide INVALID_REPOSITORY UNKNOWN)" == "BLOCK" ]] ||
    fail "INVALID_REPOSITORY"

[[ "$(cbs_worktree_decide READY DETACHED)" == "BLOCK" ]] ||
    fail "DETACHED_READY"

[[ "$(cbs_worktree_decide UNKNOWN UNKNOWN)" == "BLOCK" ]] ||
    fail "UNKNOWN"

echo "TEST_WORKTREE_MUTATION_GATE_REUSE=PASS"
echo "TEST_WORKTREE_MUTATION_GATE_CREATE=PASS"
echo "TEST_WORKTREE_MUTATION_GATE_BRANCH_CONFLICT=PASS"
echo "TEST_WORKTREE_MUTATION_GATE_PATH_CONFLICT=PASS"
echo "TEST_WORKTREE_MUTATION_GATE_INVALID_REPOSITORY=PASS"
echo "TEST_WORKTREE_MUTATION_GATE_DETACHED=PASS"
echo "TEST_WORKTREE_MUTATION_GATE_UNKNOWN=PASS"
echo "TEST_WORKTREE_MUTATION_GATE_RESULT=PASS"
