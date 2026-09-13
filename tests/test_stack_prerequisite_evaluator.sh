#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVALUATOR="$ROOT/cbs/stack/stack_prerequisite_evaluator.sh"
MANIFEST="$ROOT/stacks/core-platform/stack.env"

fail() {
    echo "TEST_STACK_PREREQUISITE_EVALUATOR_RESULT=FAIL" >&2
    echo "TEST_STACK_PREREQUISITE_EVALUATOR_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/stack/contract.sh"

OUTPUT="$("$EVALUATOR" "$MANIFEST")"

for prerequisite in \
    GIT \
    UV \
    DOCKER \
    DOCKER_COMPOSE \
    PYTHON_312
do
    grep -Fq \
        "CBS_STACK_PREREQUISITE_NAME=$prerequisite" \
        <<<"$OUTPUT" ||
        fail "PREREQUISITE_$prerequisite"

    grep -A2 -F \
        "CBS_STACK_PREREQUISITE_NAME=$prerequisite" \
        <<<"$OUTPUT" |
        grep -Fq 'CBS_STACK_PREREQUISITE_OBSERVED_STATE=PRESENT' ||
        fail "PREREQUISITE_STATE_$prerequisite"
done

echo "TEST_STACK_PREREQUISITE_EVALUATOR_REQUIRED=PASS"

grep -Fq \
    'CBS_STACK_PREREQUISITE_REQUIRED_COUNT=5' \
    <<<"$OUTPUT" ||
    fail "REQUIRED_COUNT"

grep -Fq \
    'CBS_STACK_PREREQUISITE_FAILURE_COUNT=0' \
    <<<"$OUTPUT" ||
    fail "FAILURE_COUNT"

grep -Fq \
    'CBS_STACK_STATE=READY' \
    <<<"$OUTPUT" ||
    fail "STACK_STATE"

grep -Fq \
    'CBS_STACK_PREREQUISITE_EVALUATION_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "RESULT"

echo "TEST_STACK_PREREQUISITE_EVALUATOR_READY=PASS"

set +e
MISSING_OUTPUT="$("$EVALUATOR" 2>&1)"
MISSING_RC=$?
set -e

[[ "$MISSING_RC" -eq "$CBS_RC_STACK_USAGE" ]] ||
    fail "MISSING_MANIFEST_RC"

grep -Fq \
    'CBS_STACK_PREREQUISITE_ERROR=MANIFEST_REQUIRED' \
    <<<"$MISSING_OUTPUT" ||
    fail "MISSING_MANIFEST_ERROR"

echo "TEST_STACK_PREREQUISITE_EVALUATOR_USAGE=PASS"

set +e
INVALID_OUTPUT="$(
    "$EVALUATOR" /tmp/cbs-b17-stack-missing.env 2>&1
)"
INVALID_RC=$?
set -e

[[ "$INVALID_RC" -eq "$CBS_RC_STACK_INVALID" ]] ||
    fail "INVALID_MANIFEST_RC"

grep -Fq \
    'CBS_STACK_PREREQUISITE_ERROR=MANIFEST_INVALID' \
    <<<"$INVALID_OUTPUT" ||
    fail "INVALID_MANIFEST_ERROR"

echo "TEST_STACK_PREREQUISITE_EVALUATOR_INVALID=PASS"

echo "TEST_STACK_PREREQUISITE_EVALUATOR_RESULT=PASS"
