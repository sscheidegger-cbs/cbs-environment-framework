#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/toolchain/provider_contract.sh"

fail() {
    echo "TEST_TOOLCHAIN_PROVIDER_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_TOOLCHAIN_PROVIDER_CONTRACT_FAILURE=$1" >&2
    return 1
}

[[ -f "$CONTRACT" ]] ||
    fail "CONTRACT_MISSING"

source "$CONTRACT"

[[ "${CBS_TOOLCHAIN_PROVIDER_CONTRACT_VERSION:-}" == "1" ]] ||
    fail "VERSION"

for operation in \
    DETECT \
    ENSURE \
    VERIFY
do
    cbs_toolchain_provider_operation_is_valid "$operation" ||
        fail "OPERATION_$operation"
done

echo "TEST_TOOLCHAIN_PROVIDER_CONTRACT_OPERATIONS=PASS"

if cbs_toolchain_provider_operation_is_valid "RESOLVE"; then
    fail "RESOLVE_MUST_NOT_BE_PROVIDER_OPERATION"
fi

echo "TEST_TOOLCHAIN_PROVIDER_CONTRACT_RESOLVE_EXCLUDED=PASS"

source "$CONTRACT"

[[ "$CBS_TOOLCHAIN_PROVIDER_CONTRACT_VERSION" == "1" ]] ||
    fail "DOUBLE_SOURCE"

echo "TEST_TOOLCHAIN_PROVIDER_CONTRACT_SOURCE_IDEMPOTENCE=PASS"
echo "TEST_TOOLCHAIN_PROVIDER_CONTRACT_RESULT=PASS"
