#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"
MANIFEST="$ROOT/stacks/flutter/stack.env"

fail() {
    echo "TEST_STACK_TOOLCHAIN_CLI_RESULT=FAIL" >&2
    echo "TEST_STACK_TOOLCHAIN_CLI_FAILURE=$1" >&2
    return 1
}

printf '%s\n' '--- existing read-only commands remain valid ---'

OUTPUT="$("$CBS" stack resolve "$MANIFEST")"

grep -Fq 'CBS_STACK_RESOLUTION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "STACK_RESOLVE"

echo "TEST_STACK_TOOLCHAIN_CLI_RESOLVE_PRESERVED=PASS"

printf '%s\n' '--- explicit toolchain ensure ---'

set +e
OUTPUT="$(
    CBS_TOOLCHAIN_ROOT="$HOME/.cbs/toolchains" \
    "$CBS" stack toolchains ensure "$MANIFEST" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 71 ]] ||
    fail "ENSURE_RC"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_ID=FLUTTER' \
    <<<"$OUTPUT" ||
    fail "FLUTTER_ID"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_ACTION=REUSE' \
    <<<"$OUTPUT" ||
    fail "REUSE_ACTION"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_VERIFICATION_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "VERIFY"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_ID=ANDROID_SDK' \
    <<<"$OUTPUT" ||
    fail "ANDROID_SDK_ID"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_ID=XCODE' \
    <<<"$OUTPUT" ||
    fail "XCODE_ID"

grep -Fq \
    'CBS_TOOLCHAIN_ERROR=BLOCKED' \
    <<<"$OUTPUT" ||
    fail "XCODE_BLOCK"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_REQUIRED_COUNT=3' \
    <<<"$OUTPUT" ||
    fail "REQUIRED_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_ENSURED_COUNT=2' \
    <<<"$OUTPUT" ||
    fail "ENSURED_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_FAILURE_COUNT=1' \
    <<<"$OUTPUT" ||
    fail "FAILURE_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_ENSURE_RESULT=FAIL' \
    <<<"$OUTPUT" ||
    fail "RESULT"

echo "TEST_STACK_TOOLCHAIN_CLI_HOST_BOUND_BLOCK=PASS"

printf '%s\n' '--- help exposure ---'

HELP="$("$CBS" help)"

grep -Fq \
    'cbs stack toolchains ensure <manifest>' \
    <<<"$HELP" ||
    fail "HELP_ENSURE"

echo "TEST_STACK_TOOLCHAIN_CLI_HELP=PASS"

echo "TEST_STACK_TOOLCHAIN_CLI_RESULT=PASS"
