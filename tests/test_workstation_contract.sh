#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/workstation/contract.sh"

fail() {
    echo "TEST_WORKSTATION_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_WORKSTATION_CONTRACT_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"

[[ "$CBS_WORKSTATION_CONTRACT_VERSION" == "1" ]] ||
    fail "VERSION"

[[ "$CBS_RC_OK" -eq 0 ]] ||
    fail "RC_OK"

[[ "$CBS_RC_PREREQUISITE_FAILURE" -eq 10 ]] ||
    fail "RC_PREREQUISITE_FAILURE"

[[ "$CBS_RC_ISOLATION_CONFLICT" -eq 20 ]] ||
    fail "RC_ISOLATION_CONFLICT"

[[ "$CBS_RC_INVALID_INPUT" -eq 30 ]] ||
    fail "RC_INVALID_INPUT"

[[ "$CBS_RC_INVALID_CONTEXT" -eq 64 ]] ||
    fail "RC_INVALID_CONTEXT"

for value in \
    "$CBS_RESOURCE_EXPECTED" \
    "$CBS_RESOURCE_EXTERNAL" \
    "$CBS_RESOURCE_CONFLICT" \
    "$CBS_RESOURCE_UNKNOWN"
do
    cbs_workstation_contract_validate_resource_classification "$value" ||
        fail "RESOURCE_CLASSIFICATION_$value"
done

set +e
cbs_workstation_contract_validate_resource_classification "INVALID"
INVALID_RESOURCE_RC=$?
set -e

[[ "$INVALID_RESOURCE_RC" -eq "$CBS_RC_INVALID_INPUT" ]] ||
    fail "INVALID_RESOURCE_RC"

for value in \
    "$CBS_PREREQUISITE_PRESENT" \
    "$CBS_PREREQUISITE_MISSING" \
    "$CBS_PREREQUISITE_UNAVAILABLE" \
    "$CBS_PREREQUISITE_UNKNOWN"
do
    cbs_workstation_contract_validate_prerequisite_state "$value" ||
        fail "PREREQUISITE_STATE_$value"
done

for value in \
    "$CBS_WORKSTATION_READY" \
    "$CBS_WORKSTATION_INCOMPLETE" \
    "$CBS_WORKSTATION_CONFLICT" \
    "$CBS_WORKSTATION_UNKNOWN"
do
    cbs_workstation_contract_validate_workstation_state "$value" ||
        fail "WORKSTATION_STATE_$value"
done

echo "TEST_WORKSTATION_CONTRACT_VERSION=PASS"
echo "TEST_WORKSTATION_CONTRACT_RETURN_CODES=PASS"
echo "TEST_WORKSTATION_CONTRACT_RESOURCE_CLASSIFICATION=PASS"
echo "TEST_WORKSTATION_CONTRACT_PREREQUISITE_STATE=PASS"
echo "TEST_WORKSTATION_CONTRACT_WORKSTATION_STATE=PASS"
echo "TEST_WORKSTATION_CONTRACT_RESULT=PASS"
