#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"
CONTEXT="$ROOT/config/contexts/core-platform.local.env"

fail() {
    echo "TEST_STATUS_RESULT=FAIL" >&2
    echo "TEST_STATUS_FAILURE=$1" >&2
    exit 1
}

OUTPUT="$("$CBS" status "$CONTEXT")"

grep -Fq 'CBS_CONTEXT_CLIENT=ourea' <<<"$OUTPUT" ||
    fail "CLIENT"

grep -Fq 'CBS_CONTEXT_ENTITY_TYPE=platform' <<<"$OUTPUT" ||
    fail "ENTITY_TYPE"

grep -Fq 'CBS_CONTEXT_ENTITY_NAME=core-platform' <<<"$OUTPUT" ||
    fail "ENTITY_NAME"

grep -Fq 'CBS_CONTEXT_ENVIRONMENT=LOCAL' <<<"$OUTPUT" ||
    fail "ENVIRONMENT"

grep -Fq 'CBS_CONTEXT_DRIFT=NO' <<<"$OUTPUT" ||
    fail "UNEXPECTED_DRIFT"

grep -Fq 'CBS_CONTEXT_DRIFT_REPOSITORY_PATH=NO' <<<"$OUTPUT" ||
    fail "PATH_DRIFT"

grep -Fq 'CBS_CONTEXT_DRIFT_BRANCH=NO' <<<"$OUTPUT" ||
    fail "BRANCH_DRIFT"

grep -Eq '^CBS_OBSERVED_HEAD=[0-9a-f]{40}$' <<<"$OUTPUT" ||
    fail "HEAD"

set +e
NO_CONTEXT_OUTPUT="$("$CBS" status 2>&1)"
NO_CONTEXT_RC=$?
set -e

[[ "$NO_CONTEXT_RC" -eq 2 ]] ||
    fail "MISSING_CONTEXT_RC"

grep -Fq 'CBS_ERROR=CONTEXT_FILE_REQUIRED' <<<"$NO_CONTEXT_OUTPUT" ||
    fail "MISSING_CONTEXT_ERROR"

echo "TEST_STATUS_CONTEXT=PASS"
echo "TEST_STATUS_GIT_OBSERVATION=PASS"
echo "TEST_STATUS_NO_DRIFT=PASS"
echo "TEST_STATUS_MISSING_CONTEXT=PASS"
echo "TEST_STATUS_RESULT=PASS"
