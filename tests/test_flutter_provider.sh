#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="$ROOT/cbs/toolchain/providers/flutter.sh"

fail() {
    echo "TEST_FLUTTER_PROVIDER_RESULT=FAIL" >&2
    echo "TEST_FLUTTER_PROVIDER_FAILURE=$1" >&2
    return 1
}

[[ -x "$PROVIDER" ]] ||
    fail "PROVIDER_MISSING"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TOOLCHAIN_ROOT="$TMP/toolchains"
RELEASE_ROOT="$TMP/releases"
ARCHIVE_BUILD="$TMP/archive-build"

FLUTTER_VERSION="3.47.6"
DART_VERSION="3.13.5"
TOOLCHAIN_ID="flutter"
RESOLVED_PATH="$TOOLCHAIN_ROOT/$TOOLCHAIN_ID/$FLUTTER_VERSION"

mkdir -p \
    "$TOOLCHAIN_ROOT" \
    "$RELEASE_ROOT/stable/linux" \
    "$ARCHIVE_BUILD/flutter/bin"

cat > "$ARCHIVE_BUILD/flutter/bin/flutter" <<BINARY
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
    echo "Flutter $FLUTTER_VERSION"
    echo "Dart $DART_VERSION"
else
    echo "synthetic flutter"
fi
BINARY

cat > "$ARCHIVE_BUILD/flutter/bin/dart" <<BINARY
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
    echo "Dart SDK version: $DART_VERSION"
else
    echo "synthetic dart"
fi
BINARY

chmod +x \
    "$ARCHIVE_BUILD/flutter/bin/flutter" \
    "$ARCHIVE_BUILD/flutter/bin/dart"

ARCHIVE="$RELEASE_ROOT/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

tar \
    -C "$ARCHIVE_BUILD" \
    -cJf "$ARCHIVE" \
    flutter

SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"

cat > "$TMP/releases_linux.json" <<JSON
{
  "base_url": "file://$RELEASE_ROOT",
  "current_release": {
    "stable": "synthetic-hash"
  },
  "releases": [
    {
      "hash": "synthetic-hash",
      "channel": "stable",
      "version": "$FLUTTER_VERSION",
      "dart_sdk_version": "$DART_VERSION",
      "archive": "stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz",
      "sha256": "$SHA256"
    }
  ]
}
JSON

printf '%s\n' '--- DETECT missing ---'

OUTPUT="$(
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$PROVIDER" \
        DETECT \
        "$TOOLCHAIN_ID" \
        "$FLUTTER_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING' \
    <<<"$OUTPUT" ||
    fail "DETECT_MISSING"

grep -Fq \
    "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$RESOLVED_PATH" \
    <<<"$OUTPUT" ||
    fail "DETECT_PATH"

echo "TEST_FLUTTER_PROVIDER_DETECT_MISSING=PASS"

printf '%s\n' '--- ENSURE ---'

OUTPUT="$(
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$PROVIDER" \
        ENSURE \
        "$TOOLCHAIN_ID" \
        "$FLUTTER_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "ENSURE_RESULT"

[[ -x "$RESOLVED_PATH/bin/flutter" ]] ||
    fail "FLUTTER_BINARY"

[[ -x "$RESOLVED_PATH/bin/dart" ]] ||
    fail "DART_BINARY"

echo "TEST_FLUTTER_PROVIDER_ENSURE=PASS"

printf '%s\n' '--- DETECT compatible ---'

OUTPUT="$(
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$PROVIDER" \
        DETECT \
        "$TOOLCHAIN_ID" \
        "$FLUTTER_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE' \
    <<<"$OUTPUT" ||
    fail "DETECT_COMPATIBLE"

echo "TEST_FLUTTER_PROVIDER_DETECT_COMPATIBLE=PASS"

printf '%s\n' '--- VERIFY Flutter + bundled Dart ---'

OUTPUT="$(
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$PROVIDER" \
        VERIFY \
        "$TOOLCHAIN_ID" \
        "$FLUTTER_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    "CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=$FLUTTER_VERSION" \
    <<<"$OUTPUT" ||
    fail "FLUTTER_VERSION"

grep -Fq \
    "CBS_FLUTTER_DART_VERSION_OBSERVED=$DART_VERSION" \
    <<<"$OUTPUT" ||
    fail "DART_VERSION"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "VERIFY_RESULT"

echo "TEST_FLUTTER_PROVIDER_VERIFY=PASS"

printf '%s\n' '--- MULTI-VERSION PATH MODEL ---'

SECOND_VERSION="3.46.0"

OUTPUT="$(
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$PROVIDER" \
        DETECT \
        "$TOOLCHAIN_ID" \
        "$SECOND_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

grep -Fq \
    "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$TOOLCHAIN_ROOT/flutter/$SECOND_VERSION" \
    <<<"$OUTPUT" ||
    fail "MULTI_VERSION_PATH"

[[ -x "$RESOLVED_PATH/bin/flutter" ]] ||
    fail "FIRST_VERSION_PRESERVED"

echo "TEST_FLUTTER_PROVIDER_MULTI_VERSION_MODEL=PASS"

echo "TEST_FLUTTER_PROVIDER_RESULT=PASS"
