#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT/cbs/platform/platform_resolver.sh"
MANIFEST="$ROOT/platforms/core-platform/platform.env"

fail() {
    echo "TEST_PLATFORM_RESOLVER_RESULT=FAIL" >&2
    echo "TEST_PLATFORM_RESOLVER_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/platform/contract.sh"

OUTPUT="$("$RESOLVER" "$MANIFEST")"

grep -Fq 'CBS_PLATFORM_ID=core-platform' <<<"$OUTPUT" ||
    fail "PLATFORM_ID"

grep -Fq 'CBS_PLATFORM_VERSION=1' <<<"$OUTPUT" ||
    fail "VERSION"

grep -Fq 'CBS_PLATFORM_STACK_ID=core-platform' <<<"$OUTPUT" ||
    fail "STACK_ID"

grep -Fq 'CBS_PLATFORM_INSTANCE_ID=core-platform-local' <<<"$OUTPUT" ||
    fail "INSTANCE_ID"

echo "TEST_PLATFORM_RESOLVER_IDENTITY=PASS"

REPOSITORY="$(
    awk -F= '
        $1 == "CBS_PLATFORM_REPOSITORY" {
            print $2
        }
    ' <<<"$OUTPUT"
)"

[[ "$REPOSITORY" == "/home/sscheidegger/projects/core-platform" ]] ||
    fail "REPOSITORY_$REPOSITORY"

echo "TEST_PLATFORM_RESOLVER_REPOSITORY=PASS"

[[ "$(grep -Fc 'CBS_PLATFORM_HOOK_ACTION=' <<<"$OUTPUT")" -eq 5 ]] ||
    fail "ACTION_COUNT"

[[ "$(grep -Fc 'CBS_PLATFORM_HOOK_STATE=PRESENT' <<<"$OUTPUT")" -eq 5 ]] ||
    fail "HOOK_PRESENT_COUNT"

grep -Fq 'CBS_PLATFORM_HOOK_MISSING_COUNT=0' <<<"$OUTPUT" ||
    fail "MISSING_COUNT"

grep -Fq 'CBS_PLATFORM_HOOK_NOT_EXECUTABLE_COUNT=0' <<<"$OUTPUT" ||
    fail "NOT_EXECUTABLE_COUNT"

echo "TEST_PLATFORM_RESOLVER_HOOKS=PASS"

grep -Fq 'CBS_PLATFORM_STATE=READY' <<<"$OUTPUT" ||
    fail "STATE"

grep -Fq 'CBS_PLATFORM_RESOLUTION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "RESULT"

echo "TEST_PLATFORM_RESOLVER_STATE=PASS"

set +e
OUTPUT="$("$RESOLVER" 2>&1)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_USAGE" ]] ||
    fail "USAGE_RC"

grep -Fq 'CBS_PLATFORM_ERROR=MANIFEST_REQUIRED' <<<"$OUTPUT" ||
    fail "USAGE_ERROR"

echo "TEST_PLATFORM_RESOLVER_USAGE=PASS"

set +e
OUTPUT="$(
    "$RESOLVER" /tmp/cbs-platform-missing.env 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_INVALID" ]] ||
    fail "INVALID_RC"

grep -Fq 'CBS_PLATFORM_ERROR=MANIFEST_INVALID' <<<"$OUTPUT" ||
    fail "INVALID_ERROR"

echo "TEST_PLATFORM_RESOLVER_INVALID=PASS"

echo "TEST_PLATFORM_RESOLVER_RESULT=PASS"
