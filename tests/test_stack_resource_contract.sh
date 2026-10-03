#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/stack/resource_contract.sh"

fail() {
    echo "TEST_STACK_RESOURCE_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_STACK_RESOURCE_CONTRACT_FAILURE=$1" >&2
    return 1
}

[[ -f "$CONTRACT" ]] ||
    fail "CONTRACT_MISSING"

source "$CONTRACT"

[[ "${CBS_STACK_RESOURCE_CONTRACT_VERSION:-}" == "1" ]] ||
    fail "VERSION"

for type in \
    SYSTEM_PREREQUISITE \
    MANAGED_TOOLCHAIN \
    PROJECT_DEPENDENCY \
    RUNTIME_COMPONENT \
    PLATFORM_CAPABILITY
do
    cbs_stack_resource_type_is_valid "$type" ||
        fail "TYPE_$type"
done

echo "TEST_STACK_RESOURCE_CONTRACT_TYPES=PASS"

for invalid in \
    "" \
    UNKNOWN \
    TOOLCHAIN \
    COMPONENT
do
    if cbs_stack_resource_type_is_valid "$invalid"; then
        fail "INVALID_TYPE_${invalid:-EMPTY}"
    fi
done

echo "TEST_STACK_RESOURCE_CONTRACT_INVALID_TYPES=PASS"

source "$CONTRACT"

[[ "$CBS_STACK_RESOURCE_CONTRACT_VERSION" == "1" ]] ||
    fail "DOUBLE_SOURCE"

echo "TEST_STACK_RESOURCE_CONTRACT_SOURCE_IDEMPOTENCE=PASS"
echo "TEST_STACK_RESOURCE_CONTRACT_RESULT=PASS"
