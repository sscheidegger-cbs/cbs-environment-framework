#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/toolchain/toolchain_manager.sh"

fail() {
    echo "TEST_TOOLCHAIN_MANAGER_RESULT=FAIL" >&2
    echo "TEST_TOOLCHAIN_MANAGER_FAILURE=$1" >&2
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
CBS_TOOLCHAIN_VERSION=1.2.3
CBS_TOOLCHAIN_PROVIDER=synthetic
MANIFEST

OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" resolve "$MANIFEST"
)"

grep -Fq 'CBS_TOOLCHAIN_ID=synthetic-sdk' <<<"$OUTPUT" ||
    fail "ID"

grep -Fq 'CBS_TOOLCHAIN_VERSION=1.2.3' <<<"$OUTPUT" ||
    fail "VERSION"

grep -Fq 'CBS_TOOLCHAIN_PROVIDER=synthetic' <<<"$OUTPUT" ||
    fail "PROVIDER"

grep -Fq 'CBS_TOOLCHAIN_INSTALLATION_STATE=MISSING' <<<"$OUTPUT" ||
    fail "MISSING_STATE"

grep -Fq \
    "CBS_TOOLCHAIN_RESOLVED_PATH=$TOOLCHAIN_ROOT/synthetic-sdk/1.2.3" \
    <<<"$OUTPUT" ||
    fail "RESOLVED_PATH"

grep -Fq 'CBS_TOOLCHAIN_DECISION=INSTALL' <<<"$OUTPUT" ||
    fail "INSTALL_DECISION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=NONE' <<<"$OUTPUT" ||
    fail "READ_ONLY"

grep -Fq 'CBS_TOOLCHAIN_RESOLUTION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "RESOLUTION_RESULT"

[[ ! -e "$TOOLCHAIN_ROOT/synthetic-sdk/1.2.3" ]] ||
    fail "UNEXPECTED_MUTATION"

echo "TEST_TOOLCHAIN_MANAGER_MISSING_READ_ONLY=PASS"

INSTALL_DIR="$TOOLCHAIN_ROOT/synthetic-sdk/1.2.3"
mkdir -p "$INSTALL_DIR/bin"

cat > "$INSTALL_DIR/bin/synthetic" <<'BINARY'
#!/usr/bin/env bash
echo synthetic
BINARY

chmod +x "$INSTALL_DIR/bin/synthetic"

OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" resolve "$MANIFEST"
)"

grep -Fq 'CBS_TOOLCHAIN_INSTALLATION_STATE=PRESENT_COMPATIBLE' <<<"$OUTPUT" ||
    fail "COMPATIBLE_STATE"

grep -Fq 'CBS_TOOLCHAIN_DECISION=REUSE' <<<"$OUTPUT" ||
    fail "REUSE_DECISION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=NONE' <<<"$OUTPUT" ||
    fail "REUSE_READ_ONLY"

echo "TEST_TOOLCHAIN_MANAGER_REUSE=PASS"

set +e
UNKNOWN_OUTPUT="$(
    cat > "$TMP/unknown.env" <<'MANIFEST'
CBS_TOOLCHAIN_ID=unknown-sdk
CBS_TOOLCHAIN_VERSION=9.9.9
CBS_TOOLCHAIN_PROVIDER=does-not-exist
MANIFEST

    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" resolve "$TMP/unknown.env" 2>&1
)"
UNKNOWN_RC=$?
set -e

[[ "$UNKNOWN_RC" -eq 81 ]] ||
    fail "UNKNOWN_PROVIDER_RC"

grep -Fq 'CBS_TOOLCHAIN_ERROR=UNKNOWN_PROVIDER' <<<"$UNKNOWN_OUTPUT" ||
    fail "UNKNOWN_PROVIDER_ERROR"

echo "TEST_TOOLCHAIN_MANAGER_UNKNOWN_PROVIDER=PASS"

echo "TEST_TOOLCHAIN_MANAGER_RESULT=PASS"
