#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/stack/contract.sh"

fail() {
    echo "TEST_STACK_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_STACK_CONTRACT_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"

[[ "$CBS_STACK_CONTRACT_VERSION" == "1" ]] ||
    fail "VERSION"

echo "TEST_STACK_CONTRACT_VERSION=PASS"

for state in \
    READY \
    INCOMPLETE \
    INVALID \
    UNKNOWN
do
    cbs_stack_state_is_valid "$state" ||
        fail "STACK_STATE_$state"
done

echo "TEST_STACK_CONTRACT_STATES=PASS"

for state in \
    PRESENT \
    MISSING \
    UNKNOWN
do
    cbs_stack_prerequisite_state_is_valid "$state" ||
        fail "PREREQUISITE_STATE_$state"
done

echo "TEST_STACK_CONTRACT_PREREQUISITE_STATES=PASS"

for requirement in \
    REQUIRED \
    OPTIONAL \
    DISABLED
do
    cbs_stack_component_requirement_is_valid "$requirement" ||
        fail "COMPONENT_REQUIREMENT_$requirement"
done

echo "TEST_STACK_CONTRACT_COMPONENT_REQUIREMENTS=PASS"

for capability in \
    start \
    check \
    status \
    qualify
do
    cbs_stack_capability_is_valid "$capability" ||
        fail "CAPABILITY_$capability"
done

echo "TEST_STACK_CONTRACT_CAPABILITIES=PASS"

[[ "$(cbs_stack_state_from_missing_required_count 0)" == "READY" ]] ||
    fail "READY_AGGREGATION"

[[ "$(cbs_stack_state_from_missing_required_count 1)" == "INCOMPLETE" ]] ||
    fail "INCOMPLETE_AGGREGATION"

[[ "$(cbs_stack_state_from_missing_required_count 5)" == "INCOMPLETE" ]] ||
    fail "MULTIPLE_MISSING_AGGREGATION"

echo "TEST_STACK_CONTRACT_AGGREGATION=PASS"

[[ "$CBS_RC_STACK_PREREQUISITE_MISSING" -eq 70 ]]
[[ "$CBS_RC_STACK_INVALID" -eq 71 ]]
[[ "$CBS_RC_STACK_UNKNOWN" -eq 72 ]]
[[ "$CBS_RC_STACK_USAGE" -eq 64 ]]

echo "TEST_STACK_CONTRACT_RETURN_CODES=PASS"

source "$CONTRACT"

[[ "$CBS_STACK_CONTRACT_VERSION" == "1" ]] ||
    fail "DOUBLE_SOURCE"

echo "TEST_STACK_CONTRACT_SOURCE_IDEMPOTENCE=PASS"

echo "TEST_STACK_CONTRACT_RESULT=PASS"
