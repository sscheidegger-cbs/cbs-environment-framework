#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/instance/contract.sh"

fail() {
    echo "TEST_INSTANCE_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_INSTANCE_CONTRACT_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"

[[ "$CBS_INSTANCE_CONTRACT_VERSION" == "1" ]] ||
    fail "VERSION"

echo "TEST_INSTANCE_CONTRACT_VERSION=PASS"

for state in \
    READY \
    STOPPED \
    PARTIAL \
    CONFLICT \
    INVALID \
    UNKNOWN
do
    cbs_instance_state_is_valid "$state" ||
        fail "INSTANCE_STATE_$state"
done

echo "TEST_INSTANCE_CONTRACT_STATES=PASS"

for resource in \
    CONTAINER \
    NETWORK \
    VOLUME \
    PORT
do
    cbs_instance_resource_type_is_valid "$resource" ||
        fail "RESOURCE_TYPE_$resource"
done

echo "TEST_INSTANCE_CONTRACT_RESOURCE_TYPES=PASS"

for state in \
    AVAILABLE \
    EXPECTED \
    CONFLICT \
    UNKNOWN
do
    cbs_instance_resource_state_is_valid "$state" ||
        fail "RESOURCE_STATE_$state"
done

echo "TEST_INSTANCE_CONTRACT_RESOURCE_STATES=PASS"

for action in \
    REUSE \
    CREATE \
    BLOCK \
    OBSERVE
do
    cbs_instance_action_is_valid "$action" ||
        fail "ACTION_$action"
done

echo "TEST_INSTANCE_CONTRACT_ACTIONS=PASS"

[[ "$(cbs_instance_action_from_state READY)" == "REUSE" ]] ||
    fail "READY_ACTION"

[[ "$(cbs_instance_action_from_state STOPPED)" == "REUSE" ]] ||
    fail "STOPPED_ACTION"

[[ "$(cbs_instance_action_from_state CONFLICT)" == "BLOCK" ]] ||
    fail "CONFLICT_ACTION"

[[ "$(cbs_instance_action_from_state INVALID)" == "BLOCK" ]] ||
    fail "INVALID_ACTION"

[[ "$(cbs_instance_action_from_state PARTIAL)" == "OBSERVE" ]] ||
    fail "PARTIAL_ACTION"

[[ "$(cbs_instance_action_from_state UNKNOWN)" == "OBSERVE" ]] ||
    fail "UNKNOWN_ACTION"

echo "TEST_INSTANCE_CONTRACT_STATE_ACTION_MAPPING=PASS"

[[ "$CBS_RC_INSTANCE_CONFLICT" -eq 80 ]]
[[ "$CBS_RC_INSTANCE_INVALID" -eq 81 ]]
[[ "$CBS_RC_INSTANCE_UNKNOWN" -eq 82 ]]
[[ "$CBS_RC_INSTANCE_USAGE" -eq 64 ]]

echo "TEST_INSTANCE_CONTRACT_RETURN_CODES=PASS"

source "$CONTRACT"

[[ "$CBS_INSTANCE_CONTRACT_VERSION" == "1" ]] ||
    fail "DOUBLE_SOURCE"

echo "TEST_INSTANCE_CONTRACT_SOURCE_IDEMPOTENCE=PASS"

echo "TEST_INSTANCE_CONTRACT_RESULT=PASS"
