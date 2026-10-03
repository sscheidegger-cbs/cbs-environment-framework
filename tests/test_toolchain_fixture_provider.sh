#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="$ROOT/tests/fixtures/providers/synthetic.sh"

fail() {
    echo "TEST_TOOLCHAIN_FIXTURE_PROVIDER_RESULT=FAIL" >&2
    echo "TEST_TOOLCHAIN_FIXTURE_PROVIDER_FAILURE=$1" >&2
    return 1
}

[[ -x "$PROVIDER" ]] ||
    fail "PROVIDER_MISSING"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TOOLCHAIN_ROOT="$TMP/toolchains"
TOOLCHAIN_ID="synthetic-sdk"
TOOLCHAIN_VERSION="3.5.7"
RESOLVED_PATH="$TOOLCHAIN_ROOT/$TOOLCHAIN_ID/$TOOLCHAIN_VERSION"

mkdir -p "$TOOLCHAIN_ROOT"

printf '%s\n' '--- DETECT missing ---'

OUTPUT="$(
    "$PROVIDER" \
        DETECT \
        "$TOOLCHAIN_ID" \
        "$TOOLCHAIN_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING' \
    <<<"$OUTPUT" ||
    fail "DETECT_MISSING_STATE"

grep -Fq \
    "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$RESOLVED_PATH" \
    <<<"$OUTPUT" ||
    fail "DETECT_MISSING_PATH"

echo "TEST_TOOLCHAIN_FIXTURE_PROVIDER_DETECT_MISSING=PASS"

printf '%s\n' '--- ENSURE ---'

OUTPUT="$(
    "$PROVIDER" \
        ENSURE \
        "$TOOLCHAIN_ID" \
        "$TOOLCHAIN_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "ENSURE_RESULT"

[[ -x "$RESOLVED_PATH/bin/synthetic" ]] ||
    fail "ENSURE_BINARY"

echo "TEST_TOOLCHAIN_FIXTURE_PROVIDER_ENSURE=PASS"

printf '%s\n' '--- DETECT compatible ---'

OUTPUT="$(
    "$PROVIDER" \
        DETECT \
        "$TOOLCHAIN_ID" \
        "$TOOLCHAIN_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE' \
    <<<"$OUTPUT" ||
    fail "DETECT_COMPATIBLE_STATE"

echo "TEST_TOOLCHAIN_FIXTURE_PROVIDER_DETECT_COMPATIBLE=PASS"

printf '%s\n' '--- VERIFY ---'

OUTPUT="$(
    "$PROVIDER" \
        VERIFY \
        "$TOOLCHAIN_ID" \
        "$TOOLCHAIN_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=3.5.7' \
    <<<"$OUTPUT" ||
    fail "VERIFY_VERSION"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "VERIFY_RESULT"

echo "TEST_TOOLCHAIN_FIXTURE_PROVIDER_VERIFY=PASS"

printf '%s\n' '--- unsupported operation ---'

set +e
OUTPUT="$(
    "$PROVIDER" \
        INVALID_OPERATION \
        "$TOOLCHAIN_ID" \
        "$TOOLCHAIN_VERSION" \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

[[ "$RC" -ne 0 ]] ||
    fail "UNSUPPORTED_OPERATION_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ERROR=UNSUPPORTED_OPERATION' \
    <<<"$OUTPUT" ||
    fail "UNSUPPORTED_OPERATION_ERROR"

echo "TEST_TOOLCHAIN_FIXTURE_PROVIDER_UNSUPPORTED=PASS"

echo "TEST_TOOLCHAIN_FIXTURE_PROVIDER_RESULT=PASS"
