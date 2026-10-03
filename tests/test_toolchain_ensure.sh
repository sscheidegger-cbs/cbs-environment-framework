#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/toolchain/toolchain_manager.sh"

fail() {
    echo "TEST_TOOLCHAIN_ENSURE_RESULT=FAIL" >&2
    echo "TEST_TOOLCHAIN_ENSURE_FAILURE=$1" >&2
    return 1
}

[[ -x "$MANAGER" ]] ||
    fail "MANAGER_MISSING"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROVIDER_DIR="$ROOT/tests/fixtures/providers"
TOOLCHAIN_ROOT="$TMP/toolchains"
MANIFEST="$TMP/toolchain.env"

mkdir -p "$TOOLCHAIN_ROOT"


cat > "$MANIFEST" <<'MANIFEST'
CBS_TOOLCHAIN_ID=synthetic-sdk
CBS_TOOLCHAIN_VERSION=2.4.6
CBS_TOOLCHAIN_PROVIDER=synthetic
MANIFEST

printf '%s\n' '--- resolve must remain read-only ---'

RESOLVE_OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" resolve "$MANIFEST"
)"

grep -Fq 'CBS_TOOLCHAIN_DECISION=INSTALL' <<<"$RESOLVE_OUTPUT" ||
    fail "RESOLVE_INSTALL_DECISION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=NONE' <<<"$RESOLVE_OUTPUT" ||
    fail "RESOLVE_NOT_READ_ONLY"

[[ ! -e "$TOOLCHAIN_ROOT/synthetic-sdk/2.4.6" ]] ||
    fail "RESOLVE_MUTATED"

echo "TEST_TOOLCHAIN_ENSURE_RESOLVE_READ_ONLY=PASS"

printf '%s\n' '--- explicit ensure installs and verifies ---'

ENSURE_OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" ensure "$MANIFEST"
)"

grep -Fq 'CBS_TOOLCHAIN_ACTION=INSTALL' <<<"$ENSURE_OUTPUT" ||
    fail "ENSURE_INSTALL_ACTION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=PERFORMED' <<<"$ENSURE_OUTPUT" ||
    fail "ENSURE_MUTATION"

grep -Fq 'CBS_TOOLCHAIN_VERSION_OBSERVED=2.4.6' <<<"$ENSURE_OUTPUT" ||
    fail "ENSURE_VERSION_OBSERVED"

grep -Fq 'CBS_TOOLCHAIN_VERIFICATION_RESULT=PASS' <<<"$ENSURE_OUTPUT" ||
    fail "ENSURE_VERIFY"

grep -Fq 'CBS_TOOLCHAIN_ENSURE_RESULT=PASS' <<<"$ENSURE_OUTPUT" ||
    fail "ENSURE_RESULT"

[[ -x "$TOOLCHAIN_ROOT/synthetic-sdk/2.4.6/bin/synthetic" ]] ||
    fail "ENSURE_BINARY_MISSING"

echo "TEST_TOOLCHAIN_ENSURE_INSTALL=PASS"

printf '%s\n' '--- second ensure must reuse without mutation ---'

REUSE_OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" ensure "$MANIFEST"
)"

grep -Fq 'CBS_TOOLCHAIN_ACTION=REUSE' <<<"$REUSE_OUTPUT" ||
    fail "REUSE_ACTION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=NONE' <<<"$REUSE_OUTPUT" ||
    fail "REUSE_MUTATION"

grep -Fq 'CBS_TOOLCHAIN_VERSION_OBSERVED=2.4.6' <<<"$REUSE_OUTPUT" ||
    fail "REUSE_VERSION_OBSERVED"

grep -Fq 'CBS_TOOLCHAIN_VERIFICATION_RESULT=PASS' <<<"$REUSE_OUTPUT" ||
    fail "REUSE_VERIFY"

grep -Fq 'CBS_TOOLCHAIN_ENSURE_RESULT=PASS' <<<"$REUSE_OUTPUT" ||
    fail "REUSE_RESULT"

echo "TEST_TOOLCHAIN_ENSURE_REUSE=PASS"

echo "TEST_TOOLCHAIN_ENSURE_RESULT=PASS"
