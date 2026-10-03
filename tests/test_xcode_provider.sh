#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="$ROOT/cbs/toolchain/providers/xcode.sh"

fail() {
    echo "TEST_XCODE_PROVIDER_RESULT=FAIL" >&2
    echo "TEST_XCODE_PROVIDER_FAILURE=$1" >&2
    return 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TOOLCHAIN_ROOT="$TMP/toolchains"

printf '%s\n' '--- XCODE PROVIDER EXISTS ---'

[[ -x "$PROVIDER" ]] ||
    fail "PROVIDER_MISSING"

printf '%s\n' '--- LINUX DETECT MUST BE NOT_APPLICABLE ---'

set +e
OUTPUT="$(
    "$PROVIDER" \
        DETECT \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_DETECT_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "DETECT_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=NOT_APPLICABLE' \
    <<<"$OUTPUT" ||
    fail "DETECT_STATE"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_REASON=HOST_PLATFORM_UNSUPPORTED' \
    <<<"$OUTPUT" ||
    fail "DETECT_REASON"

echo "TEST_XCODE_PROVIDER_LINUX_DETECT=PASS"

printf '%s\n' '--- LINUX ENSURE MUST REFUSE MUTATION ---'

set +e
OUTPUT="$(
    "$PROVIDER" \
        ENSURE \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_ENSURE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "ENSURE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ERROR=HOST_PLATFORM_UNSUPPORTED' \
    <<<"$OUTPUT" ||
    fail "ENSURE_REASON"

[[ ! -e "$TOOLCHAIN_ROOT/xcode/15" ]] ||
    fail "ENSURE_MUTATED"

echo "TEST_XCODE_PROVIDER_LINUX_ENSURE=PASS"

printf '%s\n' '--- LINUX VERIFY MUST REFUSE FALSE QUALIFICATION ---'

set +e
OUTPUT="$(
    "$PROVIDER" \
        VERIFY \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_VERIFY_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "VERIFY_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ERROR=HOST_PLATFORM_UNSUPPORTED' \
    <<<"$OUTPUT" ||
    fail "VERIFY_REASON"

echo "TEST_XCODE_PROVIDER_LINUX_VERIFY=PASS"


printf '%s\n' '--- SYNTHETIC MACOS DETECTION ---'

FAKE_BIN="$TMP/fake-bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/uname" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-s" ]]; then
    echo "Darwin"
else
    echo "Darwin"
fi
SCRIPT

chmod +x "$FAKE_BIN/uname"

printf '%s\n' '--- MACOS MISSING ---'

set +e
OUTPUT="$(
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$PROVIDER" \
        DETECT \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_MACOS_MISSING_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "MACOS_MISSING_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING' \
    <<<"$OUTPUT" ||
    fail "MACOS_MISSING_STATE"

echo "TEST_XCODE_PROVIDER_MACOS_MISSING=PASS"

printf '%s\n' '--- MACOS PRESENT COMPATIBLE ---'

cat > "$FAKE_BIN/xcode-select" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-p" ]]; then
    echo "/Applications/Xcode.app/Contents/Developer"
    exit 0
fi
exit 1
SCRIPT

cat > "$FAKE_BIN/xcodebuild" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
    cat <<'VERSION'
Xcode 16.4
Build version 16F6
VERSION
    exit 0
fi
exit 1
SCRIPT

chmod +x \
    "$FAKE_BIN/xcode-select" \
    "$FAKE_BIN/xcodebuild"

set +e
OUTPUT="$(
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$PROVIDER" \
        DETECT \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_MACOS_COMPATIBLE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "MACOS_COMPATIBLE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE' \
    <<<"$OUTPUT" ||
    fail "MACOS_COMPATIBLE_STATE"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=/Applications/Xcode.app/Contents/Developer' \
    <<<"$OUTPUT" ||
    fail "MACOS_COMPATIBLE_PATH"

echo "TEST_XCODE_PROVIDER_MACOS_COMPATIBLE=PASS"

printf '%s\n' '--- MACOS PRESENT INCOMPATIBLE ---'

cat > "$FAKE_BIN/xcodebuild" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
    cat <<'VERSION'
Xcode 14.3
Build version 14E222b
VERSION
    exit 0
fi
exit 1
SCRIPT

chmod +x "$FAKE_BIN/xcodebuild"

set +e
OUTPUT="$(
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$PROVIDER" \
        DETECT \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_MACOS_INCOMPATIBLE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "MACOS_INCOMPATIBLE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_INCOMPATIBLE' \
    <<<"$OUTPUT" ||
    fail "MACOS_INCOMPATIBLE_STATE"

echo "TEST_XCODE_PROVIDER_MACOS_INCOMPATIBLE=PASS"


printf '%s\n' '--- MACOS ENSURE MUST DECLARE EXTERNAL INSTALLATION ---'

set +e
OUTPUT="$(
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$PROVIDER" \
        ENSURE \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_MACOS_ENSURE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "MACOS_ENSURE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ERROR=EXTERNAL_INSTALLATION_REQUIRED' \
    <<<"$OUTPUT" ||
    fail "MACOS_ENSURE_POLICY"

[[ ! -e "$TOOLCHAIN_ROOT/xcode/15" ]] ||
    fail "MACOS_ENSURE_MUTATED"

echo "TEST_XCODE_PROVIDER_MACOS_ENSURE_EXTERNAL=PASS"

printf '%s\n' '--- SYNTHETIC MACOS VERIFY ---'

cat > "$FAKE_BIN/xcodebuild" <<'SCRIPT'
#!/usr/bin/env bash

if [[ "${1:-}" == "-version" ]]; then
    cat <<'VERSION'
Xcode 16.4
Build version 16F6
VERSION
    exit 0
fi

exit 1
SCRIPT

cat > "$FAKE_BIN/xcrun" <<'SCRIPT'
#!/usr/bin/env bash

case "$*" in
    "--sdk iphoneos --show-sdk-version")
        echo "18.5"
        exit 0
        ;;

    "--sdk iphonesimulator --show-sdk-version")
        echo "18.5"
        exit 0
        ;;

    "--find simctl")
        echo "/usr/bin/simctl"
        exit 0
        ;;

    "--find clang")
        echo "/usr/bin/clang"
        exit 0
        ;;

    *)
        exit 1
        ;;
esac
SCRIPT

chmod +x \
    "$FAKE_BIN/xcodebuild" \
    "$FAKE_BIN/xcrun"

set +e
OUTPUT="$(
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$PROVIDER" \
        VERIFY \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_MACOS_VERIFY_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "MACOS_VERIFY_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=16.4' \
    <<<"$OUTPUT" ||
    fail "MACOS_VERIFY_VERSION"

grep -Fq \
    'CBS_XCODE_BUILD_VERSION_OBSERVED=16F6' \
    <<<"$OUTPUT" ||
    fail "MACOS_VERIFY_BUILD_VERSION"

grep -Fq \
    'CBS_XCODE_IPHONEOS_SDK_VERSION_OBSERVED=18.5' \
    <<<"$OUTPUT" ||
    fail "MACOS_VERIFY_IPHONEOS_SDK"

grep -Fq \
    'CBS_XCODE_IPHONESIMULATOR_SDK_VERSION_OBSERVED=18.5' \
    <<<"$OUTPUT" ||
    fail "MACOS_VERIFY_IPHONESIMULATOR_SDK"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "MACOS_VERIFY_RESULT"

echo "TEST_XCODE_PROVIDER_MACOS_VERIFY=PASS"


printf '%s\n' '--- VERIFY MUST REJECT INCOMPATIBLE XCODE ---'

cat > "$FAKE_BIN/xcodebuild" <<'SCRIPT'
#!/usr/bin/env bash

if [[ "${1:-}" == "-version" ]]; then
    cat <<'VERSION'
Xcode 14.3
Build version 14E222b
VERSION
    exit 0
fi

exit 1
SCRIPT

chmod +x "$FAKE_BIN/xcodebuild"

set +e
OUTPUT="$(
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$PROVIDER" \
        VERIFY \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_MACOS_BAD_VERSION_VERIFY_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "MACOS_BAD_VERSION_VERIFY_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL' \
    <<<"$OUTPUT" ||
    fail "MACOS_BAD_VERSION_VERIFY_RESULT"

echo "TEST_XCODE_PROVIDER_MACOS_VERIFY_BAD_VERSION=PASS"


printf '%s\n' '--- VERIFY MUST REJECT MISSING IOS SDK ---'

cat > "$FAKE_BIN/xcodebuild" <<'SCRIPT'
#!/usr/bin/env bash

if [[ "${1:-}" == "-version" ]]; then
    cat <<'VERSION'
Xcode 16.4
Build version 16F6
VERSION
    exit 0
fi

exit 1
SCRIPT

cat > "$FAKE_BIN/xcrun" <<'SCRIPT'
#!/usr/bin/env bash

case "$*" in
    "--sdk iphoneos --show-sdk-version")
        exit 1
        ;;

    "--sdk iphonesimulator --show-sdk-version")
        echo "18.5"
        exit 0
        ;;

    "--find simctl")
        echo "/usr/bin/simctl"
        exit 0
        ;;

    "--find clang")
        echo "/usr/bin/clang"
        exit 0
        ;;

    *)
        exit 1
        ;;
esac
SCRIPT

chmod +x \
    "$FAKE_BIN/xcodebuild" \
    "$FAKE_BIN/xcrun"

set +e
OUTPUT="$(
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$PROVIDER" \
        VERIFY \
        xcode \
        15 \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf 'XCODE_MACOS_MISSING_SDK_VERIFY_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "MACOS_MISSING_SDK_VERIFY_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL' \
    <<<"$OUTPUT" ||
    fail "MACOS_MISSING_SDK_VERIFY_RESULT"

echo "TEST_XCODE_PROVIDER_MACOS_VERIFY_MISSING_SDK=PASS"

echo "TEST_XCODE_PROVIDER_RESULT=PASS"
