#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"
MANIFEST="$ROOT/instances/core-platform/instance.env"

fail() {
    echo "TEST_INSTANCE_CLI_RESULT=FAIL" >&2
    echo "TEST_INSTANCE_CLI_FAILURE=$1" >&2
    exit 1
}

OUTPUT="$(
    "$CBS" instance check "$MANIFEST"
)"

grep -Fq 'CBS_INSTANCE_ID=core-platform-local' <<<"$OUTPUT" ||
    fail "CHECK_ID"

grep -Fq 'CBS_INSTANCE_STATE=READY' <<<"$OUTPUT" ||
    fail "CHECK_STATE"

grep -Fq 'CBS_INSTANCE_ACTION=REUSE' <<<"$OUTPUT" ||
    fail "CHECK_ACTION"

grep -Fq 'CBS_INSTANCE_OBSERVATION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "CHECK_RESULT"

echo "TEST_INSTANCE_CLI_CHECK=PASS"

OUTPUT="$(
    "$CBS" instance ensure "$MANIFEST"
)"

grep -Fq \
    'CBS_INSTANCE_MANAGER_STATE_BEFORE=READY' \
    <<<"$OUTPUT" ||
    fail "ENSURE_STATE"

grep -Fq \
    'CBS_INSTANCE_MANAGER_ACTION=REUSE' \
    <<<"$OUTPUT" ||
    fail "ENSURE_ACTION"

grep -Fq \
    'CBS_INSTANCE_MANAGER_MUTATION=NONE' \
    <<<"$OUTPUT" ||
    fail "ENSURE_MUTATION"

grep -Fq \
    'CBS_INSTANCE_MANAGER_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "ENSURE_RESULT"

echo "TEST_INSTANCE_CLI_ENSURE=PASS"

set +e
OUTPUT="$(
    "$CBS" instance unknown 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 2 ]] ||
    fail "UNKNOWN_RC"

grep -Fq \
    'CBS_ERROR=UNKNOWN_INSTANCE_COMMAND' \
    <<<"$OUTPUT" ||
    fail "UNKNOWN_ERROR"

echo "TEST_INSTANCE_CLI_UNKNOWN_COMMAND=PASS"

set +e
OUTPUT="$(
    "$CBS" instance check 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 64 ]] ||
    fail "CHECK_MISSING_MANIFEST_RC"

grep -Fq \
    'CBS_INSTANCE_ERROR=MANIFEST_REQUIRED' \
    <<<"$OUTPUT" ||
    fail "CHECK_MISSING_MANIFEST_ERROR"

echo "TEST_INSTANCE_CLI_CHECK_USAGE=PASS"

set +e
OUTPUT="$(
    "$CBS" instance ensure 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 64 ]] ||
    fail "ENSURE_MISSING_MANIFEST_RC"

grep -Fq \
    'CBS_INSTANCE_MANAGER_ERROR=MANIFEST_REQUIRED' \
    <<<"$OUTPUT" ||
    fail "ENSURE_MISSING_MANIFEST_ERROR"

echo "TEST_INSTANCE_CLI_ENSURE_USAGE=PASS"

HELP="$("$CBS" help)"

grep -Fq \
    'cbs instance check <manifest>' \
    <<<"$HELP" ||
    fail "HELP_CHECK"

grep -Fq \
    'cbs instance ensure <manifest>' \
    <<<"$HELP" ||
    fail "HELP_ENSURE"

echo "TEST_INSTANCE_CLI_HELP=PASS"

echo "TEST_INSTANCE_CLI_RESULT=PASS"
