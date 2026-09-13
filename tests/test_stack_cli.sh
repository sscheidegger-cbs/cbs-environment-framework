#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"
MANIFEST="$ROOT/stacks/core-platform/stack.env"

fail() {
    echo "TEST_STACK_CLI_RESULT=FAIL" >&2
    echo "TEST_STACK_CLI_FAILURE=$1" >&2
    exit 1
}

OUTPUT="$(
    "$CBS" stack resolve "$MANIFEST"
)"

grep -Fq 'CBS_STACK_ID=core-platform' <<<"$OUTPUT" ||
    fail "RESOLVE_ID"

grep -Fq 'CBS_STACK_STATE=READY' <<<"$OUTPUT" ||
    fail "RESOLVE_STATE"

grep -Fq 'CBS_STACK_RESOLUTION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "RESOLVE_RESULT"

echo "TEST_STACK_CLI_RESOLVE=PASS"

OUTPUT="$(
    "$CBS" stack prerequisites "$MANIFEST"
)"

grep -Fq \
    'CBS_STACK_PREREQUISITE_REQUIRED_COUNT=5' \
    <<<"$OUTPUT" ||
    fail "PREREQUISITE_COUNT"

grep -Fq \
    'CBS_STACK_PREREQUISITE_FAILURE_COUNT=0' \
    <<<"$OUTPUT" ||
    fail "PREREQUISITE_FAILURE_COUNT"

grep -Fq 'CBS_STACK_STATE=READY' <<<"$OUTPUT" ||
    fail "PREREQUISITE_STATE"

grep -Fq \
    'CBS_STACK_PREREQUISITE_EVALUATION_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "PREREQUISITE_RESULT"

echo "TEST_STACK_CLI_PREREQUISITES=PASS"

set +e
OUTPUT="$(
    "$CBS" stack unknown 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 2 ]] ||
    fail "UNKNOWN_RC"

grep -Fq 'CBS_ERROR=UNKNOWN_STACK_COMMAND' <<<"$OUTPUT" ||
    fail "UNKNOWN_ERROR"

echo "TEST_STACK_CLI_UNKNOWN_COMMAND=PASS"

HELP="$("$CBS" help)"

grep -Fq 'cbs stack resolve <manifest>' <<<"$HELP" ||
    fail "HELP_RESOLVE"

grep -Fq 'cbs stack prerequisites <manifest>' <<<"$HELP" ||
    fail "HELP_PREREQUISITES"

echo "TEST_STACK_CLI_HELP=PASS"

echo "TEST_STACK_CLI_RESULT=PASS"
