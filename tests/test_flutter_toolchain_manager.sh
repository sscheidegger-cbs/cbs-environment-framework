#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/toolchain/toolchain_manager.sh"
PROVIDER_DIR="$ROOT/cbs/toolchain/providers"

fail() {
    echo "TEST_FLUTTER_TOOLCHAIN_MANAGER_RESULT=FAIL" >&2
    echo "TEST_FLUTTER_TOOLCHAIN_MANAGER_FAILURE=$1" >&2
    return 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TOOLCHAIN_ROOT="$TMP/toolchains"
RELEASE_ROOT="$TMP/releases"
ARCHIVE_BUILD="$TMP/archive-build"
MANIFEST="$TMP/flutter.env"

FLUTTER_VERSION="3.47.6"
DART_VERSION="3.13.5"

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

cat > "$MANIFEST" <<MANIFEST
CBS_TOOLCHAIN_ID=flutter
CBS_TOOLCHAIN_VERSION=$FLUTTER_VERSION
CBS_TOOLCHAIN_PROVIDER=flutter
MANIFEST

printf '%s\n' '--- RESOLVE BEFORE INSTALL ---'

OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$MANAGER" resolve "$MANIFEST"
)"

grep -Fq 'CBS_TOOLCHAIN_ID=flutter' <<<"$OUTPUT" ||
    fail "RESOLVE_ID"

grep -Fq "CBS_TOOLCHAIN_VERSION=$FLUTTER_VERSION" <<<"$OUTPUT" ||
    fail "RESOLVE_VERSION"

grep -Fq 'CBS_TOOLCHAIN_PROVIDER=flutter' <<<"$OUTPUT" ||
    fail "RESOLVE_PROVIDER"

grep -Fq 'CBS_TOOLCHAIN_INSTALLATION_STATE=MISSING' <<<"$OUTPUT" ||
    fail "RESOLVE_MISSING"

grep -Fq 'CBS_TOOLCHAIN_DECISION=INSTALL' <<<"$OUTPUT" ||
    fail "RESOLVE_INSTALL_DECISION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=NONE' <<<"$OUTPUT" ||
    fail "RESOLVE_MUTATION"

echo "TEST_FLUTTER_TOOLCHAIN_MANAGER_RESOLVE=PASS"

printf '%s\n' '--- ENSURE ---'

OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$MANAGER" ensure "$MANIFEST"
)"

grep -Fq 'CBS_TOOLCHAIN_ACTION=INSTALL' <<<"$OUTPUT" ||
    fail "ENSURE_ACTION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=PERFORMED' <<<"$OUTPUT" ||
    fail "ENSURE_MUTATION"

grep -Fq "CBS_TOOLCHAIN_VERSION_OBSERVED=$FLUTTER_VERSION" <<<"$OUTPUT" ||
    fail "ENSURE_FLUTTER_VERSION"

grep -Fq 'CBS_TOOLCHAIN_VERIFICATION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "ENSURE_VERIFY"

grep -Fq 'CBS_TOOLCHAIN_ENSURE_RESULT=PASS' <<<"$OUTPUT" ||
    fail "ENSURE_RESULT"

[[ -x "$TOOLCHAIN_ROOT/flutter/$FLUTTER_VERSION/bin/flutter" ]] ||
    fail "ENSURE_FLUTTER_BINARY"

[[ -x "$TOOLCHAIN_ROOT/flutter/$FLUTTER_VERSION/bin/dart" ]] ||
    fail "ENSURE_DART_BINARY"

echo "TEST_FLUTTER_TOOLCHAIN_MANAGER_ENSURE=PASS"

printf '%s\n' '--- REUSE ---'

OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$MANAGER" ensure "$MANIFEST"
)"

grep -Fq 'CBS_TOOLCHAIN_ACTION=REUSE' <<<"$OUTPUT" ||
    fail "REUSE_ACTION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=NONE' <<<"$OUTPUT" ||
    fail "REUSE_MUTATION"

grep -Fq 'CBS_TOOLCHAIN_ENSURE_RESULT=PASS' <<<"$OUTPUT" ||
    fail "REUSE_RESULT"

echo "TEST_FLUTTER_TOOLCHAIN_MANAGER_REUSE=PASS"

printf '%s\n' '--- EXPLICIT RESOLVED PATH ---'

EXPECTED_PATH="$TOOLCHAIN_ROOT/flutter/$FLUTTER_VERSION"

OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    CBS_FLUTTER_RELEASES_FILE="$TMP/releases_linux.json" \
    "$MANAGER" resolve "$MANIFEST"
)"

grep -Fq "CBS_TOOLCHAIN_RESOLVED_PATH=$EXPECTED_PATH" <<<"$OUTPUT" ||
    fail "RESOLVED_PATH"

echo "TEST_FLUTTER_TOOLCHAIN_MANAGER_PATH=PASS"

echo "TEST_FLUTTER_TOOLCHAIN_MANAGER_RESULT=PASS"
