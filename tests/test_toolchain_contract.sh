#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/toolchain/contract.sh"

fail() {
    echo "TEST_TOOLCHAIN_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_TOOLCHAIN_CONTRACT_FAILURE=$1" >&2
    return 1
}

[[ -f "$CONTRACT" ]] ||
    fail "CONTRACT_MISSING"

source "$CONTRACT"

[[ "${CBS_TOOLCHAIN_CONTRACT_VERSION:-}" == "1" ]] ||
    fail "VERSION"

for state in \
    MISSING \
    PRESENT_COMPATIBLE \
    PRESENT_INCOMPATIBLE \
    INVALID \
    UNKNOWN
do
    cbs_toolchain_installation_state_is_valid "$state" ||
        fail "INSTALLATION_STATE_$state"
done

echo "TEST_TOOLCHAIN_CONTRACT_INSTALLATION_STATES=PASS"

for decision in \
    REUSE \
    INSTALL \
    RECONCILE \
    BLOCK
do
    cbs_toolchain_decision_is_valid "$decision" ||
        fail "DECISION_$decision"
done

echo "TEST_TOOLCHAIN_CONTRACT_DECISIONS=PASS"

for state in \
    NOT_QUALIFIED \
    QUALIFIED \
    FAILED
do
    cbs_toolchain_qualification_state_is_valid "$state" ||
        fail "QUALIFICATION_STATE_$state"
done

echo "TEST_TOOLCHAIN_CONTRACT_QUALIFICATION_STATES=PASS"

[[ -n "${CBS_RC_TOOLCHAIN_INVALID:-}" ]] ||
    fail "RC_INVALID_MISSING"

[[ -n "${CBS_RC_TOOLCHAIN_UNKNOWN_PROVIDER:-}" ]] ||
    fail "RC_UNKNOWN_PROVIDER_MISSING"

[[ -n "${CBS_RC_TOOLCHAIN_PROVIDER_FAILURE:-}" ]] ||
    fail "RC_PROVIDER_FAILURE_MISSING"

[[ -n "${CBS_RC_TOOLCHAIN_USAGE:-}" ]] ||
    fail "RC_USAGE_MISSING"

echo "TEST_TOOLCHAIN_CONTRACT_RETURN_CODES=PASS"

source "$CONTRACT"

[[ "$CBS_TOOLCHAIN_CONTRACT_VERSION" == "1" ]] ||
    fail "DOUBLE_SOURCE"

echo "TEST_TOOLCHAIN_CONTRACT_SOURCE_IDEMPOTENCE=PASS"
echo "TEST_TOOLCHAIN_CONTRACT_RESULT=PASS"
