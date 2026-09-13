#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/instance/instance_manager.sh"
MANIFEST="$ROOT/instances/core-platform/instance.env"

fail() {
    echo "TEST_INSTANCE_MANAGER_RESULT=FAIL" >&2
    echo "TEST_INSTANCE_MANAGER_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/instance/contract.sh"

OUTPUT="$("$MANAGER" "$MANIFEST")"

grep -Fq 'CBS_INSTANCE_MANAGER_STATE_BEFORE=READY' <<<"$OUTPUT" ||
    fail "REAL_STATE"

grep -Fq 'CBS_INSTANCE_MANAGER_ACTION=REUSE' <<<"$OUTPUT" ||
    fail "REAL_ACTION"

grep -Fq 'CBS_INSTANCE_MANAGER_MUTATION=NONE' <<<"$OUTPUT" ||
    fail "REAL_MUTATION"

grep -Fq 'CBS_INSTANCE_MANAGER_RESULT=PASS' <<<"$OUTPUT" ||
    fail "REAL_RESULT"

echo "TEST_INSTANCE_MANAGER_REUSE=PASS"

set +e
OUTPUT="$("$MANAGER" 2>&1)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_INSTANCE_USAGE" ]] ||
    fail "USAGE_RC"

grep -Fq 'CBS_INSTANCE_MANAGER_ERROR=MANIFEST_REQUIRED' <<<"$OUTPUT" ||
    fail "USAGE_ERROR"

echo "TEST_INSTANCE_MANAGER_USAGE=PASS"

set +e
OUTPUT="$(
    "$MANAGER" /tmp/cbs-instance-manager-missing.env 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_INSTANCE_INVALID" ]] ||
    fail "INVALID_RC"

grep -Fq 'CBS_INSTANCE_MANAGER_ERROR=MANIFEST_INVALID' <<<"$OUTPUT" ||
    fail "INVALID_ERROR"

echo "TEST_INSTANCE_MANAGER_INVALID=PASS"

echo "TEST_INSTANCE_MANAGER_RESULT=PASS"
