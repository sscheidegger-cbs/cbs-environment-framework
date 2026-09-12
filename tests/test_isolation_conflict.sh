#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT/cbs/workstation/contract.sh"
source "$ROOT/cbs/workstation/isolation_checker.sh"

fail() {
    echo "TEST_ISOLATION_CONFLICT_RESULT=FAIL" >&2
    echo "TEST_ISOLATION_CONFLICT_FAILURE=$1" >&2
    exit 1
}

EXPECTED="$(
    cbs_isolation_classify_claim \
        "core-platform-postgres" \
        "core-platform-postgres"
)"

[[ "$EXPECTED" == "$CBS_RESOURCE_EXPECTED" ]] ||
    fail "EXPECTED_OWNER"

CONFLICT="$(
    cbs_isolation_classify_claim \
        "core-platform-postgres" \
        "other-project-postgres"
)"

[[ "$CONFLICT" == "$CBS_RESOURCE_CONFLICT" ]] ||
    fail "CONFLICT_OWNER"

UNKNOWN_EXPECTED="$(
    cbs_isolation_classify_claim \
        "" \
        "other-project-postgres"
)"

[[ "$UNKNOWN_EXPECTED" == "$CBS_RESOURCE_UNKNOWN" ]] ||
    fail "UNKNOWN_EXPECTED_OWNER"

UNKNOWN_OBSERVED="$(
    cbs_isolation_classify_claim \
        "core-platform-postgres" \
        ""
)"

[[ "$UNKNOWN_OBSERVED" == "$CBS_RESOURCE_UNKNOWN" ]] ||
    fail "UNKNOWN_OBSERVED_OWNER"

echo "TEST_ISOLATION_CLAIM_EXPECTED=PASS"
echo "TEST_ISOLATION_CLAIM_CONFLICT=PASS"
echo "TEST_ISOLATION_CLAIM_UNKNOWN=PASS"
echo "TEST_ISOLATION_CONFLICT_RESULT=PASS"
