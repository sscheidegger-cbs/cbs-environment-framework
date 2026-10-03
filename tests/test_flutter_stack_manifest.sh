#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/stacks/flutter/stack.env"
EVALUATOR="$ROOT/cbs/stack/stack_toolchain_evaluator.sh"

fail() {
    echo "TEST_FLUTTER_STACK_MANIFEST_RESULT=FAIL" >&2
    echo "TEST_FLUTTER_STACK_MANIFEST_FAILURE=$1" >&2
    return 1
}

[[ -f "$MANIFEST" ]] ||
    fail "MANIFEST_MISSING"

set -a
source "$MANIFEST"
set +a

[[ "$CBS_STACK_ID" == "flutter" ]] ||
    fail "STACK_ID"

[[ "$CBS_STACK_VERSION" == "1" ]] ||
    fail "STACK_VERSION"

[[ "$CBS_STACK_MANAGED_TOOLCHAIN_IDS" == "FLUTTER" ]] ||
    fail "TOOLCHAIN_IDS"

[[ "$CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_REQUIREMENT" == "REQUIRED" ]] ||
    fail "TOOLCHAIN_REQUIREMENT"

[[ "$CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION" == "3.47.6" ]] ||
    fail "TOOLCHAIN_VERSION"

[[ "$CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_PROVIDER" == "flutter" ]] ||
    fail "TOOLCHAIN_PROVIDER"

echo "TEST_FLUTTER_STACK_MANIFEST_DECLARATION=PASS"

OUTPUT="$(
    CBS_TOOLCHAIN_ROOT="$HOME/.cbs/toolchains" \
    "$EVALUATOR" "$MANIFEST"
)"

grep -Fq \
    'CBS_STACK_RESOURCE_TYPE=MANAGED_TOOLCHAIN' \
    <<<"$OUTPUT" ||
    fail "RESOURCE_TYPE"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_ID=FLUTTER' \
    <<<"$OUTPUT" ||
    fail "TOOLCHAIN_ID"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_INSTALLATION_STATE=PRESENT_COMPATIBLE' \
    <<<"$OUTPUT" ||
    fail "INSTALLATION_STATE"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_DECISION=REUSE' \
    <<<"$OUTPUT" ||
    fail "REUSE_DECISION"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_MUTATION=NONE' \
    <<<"$OUTPUT" ||
    fail "READ_ONLY"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_REQUIRED_COUNT=1' \
    <<<"$OUTPUT" ||
    fail "REQUIRED_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_MISSING_COUNT=0' \
    <<<"$OUTPUT" ||
    fail "MISSING_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_EVALUATION_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "RESULT"

echo "TEST_FLUTTER_STACK_MANIFEST_REAL_REUSE=PASS"

echo "TEST_FLUTTER_STACK_MANIFEST_RESULT=PASS"
