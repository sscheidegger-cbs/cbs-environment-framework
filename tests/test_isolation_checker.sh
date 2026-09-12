#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECKER="$ROOT/cbs/workstation/isolation_checker.sh"
CONTRACT="$ROOT/cbs/workstation/contract.sh"
CONTEXT="$ROOT/config/contexts/core-platform.local.env"

fail() {
    echo "TEST_ISOLATION_RESULT=FAIL" >&2
    echo "TEST_ISOLATION_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"
source "$CHECKER"

EXPECTED_CLASS="$(
    cbs_isolation_classify_named_resource \
        "core-platform-postgres" \
        "core-platform"
)"

[[ "$EXPECTED_CLASS" == "$CBS_RESOURCE_EXPECTED" ]] ||
    fail "EXPECTED_CLASSIFICATION"

EXTERNAL_CLASS="$(
    cbs_isolation_classify_named_resource \
        "core-poc-redis" \
        "core-platform"
)"

[[ "$EXTERNAL_CLASS" == "$CBS_RESOURCE_EXTERNAL" ]] ||
    fail "EXTERNAL_CLASSIFICATION"

EXPECTED_NETWORK="$(
    cbs_isolation_classify_named_resource \
        "core-platform-network" \
        "core-platform"
)"

[[ "$EXPECTED_NETWORK" == "$CBS_RESOURCE_EXPECTED" ]] ||
    fail "EXPECTED_NETWORK"

OUTPUT="$("$CHECKER" "$CONTEXT")"

grep -Fq \
    'CBS_ISOLATION_RESOURCE_NAME=core-platform-postgres' \
    <<<"$OUTPUT" ||
    fail "CORE_POSTGRES_NOT_OBSERVED"

grep -Fq \
    'CBS_ISOLATION_RESOURCE_NAME=core-platform-network' \
    <<<"$OUTPUT" ||
    fail "CORE_NETWORK_NOT_OBSERVED"

grep -Fq \
    'CBS_ISOLATION_CONFLICTS=0' \
    <<<"$OUTPUT" ||
    fail "UNEXPECTED_CONFLICT"

grep -Fq \
    'CBS_ISOLATION_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "RESULT_NOT_PASS"

set +e
NO_CONTEXT_OUTPUT="$("$CHECKER" 2>&1)"
NO_CONTEXT_RC=$?
set -e

[[ "$NO_CONTEXT_RC" -eq "$CBS_RC_INVALID_CONTEXT" ]] ||
    fail "MISSING_CONTEXT_RC"

grep -Fq \
    'CBS_ISOLATION_ERROR=CONTEXT_FILE_REQUIRED' \
    <<<"$NO_CONTEXT_OUTPUT" ||
    fail "MISSING_CONTEXT_ERROR"

echo "TEST_ISOLATION_EXPECTED_CLASSIFICATION=PASS"
echo "TEST_ISOLATION_EXTERNAL_CLASSIFICATION=PASS"
echo "TEST_ISOLATION_CONTEXT=PASS"
echo "TEST_ISOLATION_REAL_OBSERVATION=PASS"
echo "TEST_ISOLATION_NO_FALSE_PORT_CONFLICT=PASS"
echo "TEST_ISOLATION_RESULT=PASS"
