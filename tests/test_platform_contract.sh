#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTRACT="$ROOT/cbs/platform/contract.sh"

fail() {
    echo "TEST_PLATFORM_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_PLATFORM_CONTRACT_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"

[[ "$CBS_PLATFORM_CONTRACT_VERSION" == "1" ]] ||
    fail "VERSION"

echo "TEST_PLATFORM_CONTRACT_VERSION=PASS"

for state in \
    READY \
    INCOMPLETE \
    INVALID \
    UNKNOWN
do
    cbs_platform_state_is_valid "$state" ||
        fail "STATE_$state"
done

if cbs_platform_state_is_valid "NOT_A_STATE"; then
    fail "INVALID_STATE_ACCEPTED"
fi

echo "TEST_PLATFORM_CONTRACT_STATES=PASS"

for state in \
    PRESENT \
    MISSING \
    NOT_EXECUTABLE \
    UNKNOWN
do
    cbs_platform_hook_state_is_valid "$state" ||
        fail "HOOK_STATE_$state"
done

if cbs_platform_hook_state_is_valid "NOT_A_HOOK_STATE"; then
    fail "INVALID_HOOK_STATE_ACCEPTED"
fi

echo "TEST_PLATFORM_CONTRACT_HOOK_STATES=PASS"

for action in \
    start \
    check \
    status \
    stop \
    qualify
do
    cbs_platform_action_is_valid "$action" ||
        fail "ACTION_$action"
done

if cbs_platform_action_is_valid "deploy"; then
    fail "INVALID_ACTION_ACCEPTED"
fi

echo "TEST_PLATFORM_CONTRACT_ACTIONS=PASS"

[[ "$(cbs_platform_state_from_hook_failures 0 0)" == "READY" ]] ||
    fail "READY_AGGREGATION"

[[ "$(cbs_platform_state_from_hook_failures 1 0)" == "INCOMPLETE" ]] ||
    fail "MISSING_AGGREGATION"

[[ "$(cbs_platform_state_from_hook_failures 0 1)" == "INCOMPLETE" ]] ||
    fail "EXECUTABLE_AGGREGATION"

[[ "$(cbs_platform_state_from_hook_failures 2 3)" == "INCOMPLETE" ]] ||
    fail "MULTIPLE_FAILURE_AGGREGATION"

echo "TEST_PLATFORM_CONTRACT_AGGREGATION=PASS"

set +e
cbs_platform_state_from_hook_failures "x" 0 >/dev/null 2>&1
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_INVALID" ]] ||
    fail "INVALID_MISSING_COUNT_RC"

set +e
cbs_platform_state_from_hook_failures 0 "x" >/dev/null 2>&1
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_INVALID" ]] ||
    fail "INVALID_EXECUTABLE_COUNT_RC"

echo "TEST_PLATFORM_CONTRACT_RETURN_CODES=PASS"

source "$CONTRACT"

[[ "$CBS_PLATFORM_CONTRACT_VERSION" == "1" ]] ||
    fail "DOUBLE_SOURCE_VERSION"

echo "TEST_PLATFORM_CONTRACT_SOURCE_IDEMPOTENCE=PASS"

echo "TEST_PLATFORM_CONTRACT_RESULT=PASS"
