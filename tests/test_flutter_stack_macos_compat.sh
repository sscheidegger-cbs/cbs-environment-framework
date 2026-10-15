#!/usr/bin/env bash

# D04b-A: Flutter Stack compatibility with macOS/iOS.
#
# Hermetic cross-platform contract test. The host operating system is pinned
# with a synthetic `uname`, and Flutter / Xcode / Android SDK installations
# are synthetic trees under a temporary toolchain root. No real toolchain is
# read, installed or modified, and no network access is performed.
#
# Real components under test: stacks/flutter/stack.env, bin/cbs, the Stack
# resolver / evaluator / manager / environment, the Toolchain Manager and the
# flutter, xcode and android-sdk providers.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"
MANIFEST="$ROOT/stacks/flutter/stack.env"
ANDROID_PROVIDER="$ROOT/cbs/toolchain/providers/android-sdk.sh"
TOOLCHAIN_MANAGER="$ROOT/cbs/toolchain/toolchain_manager.sh"

fail() {
    echo "TEST_FLUTTER_STACK_MACOS_COMPAT_RESULT=FAIL" >&2
    echo "TEST_FLUTTER_STACK_MACOS_COMPAT_FAILURE=$1" >&2
    return 1
}

expect_line() {
    local output="${1:-}"
    local line="${2:-}"
    local failure="${3:-}"

    grep -Fxq -- "$line" <<<"$output" ||
        fail "$failure"
}

expect_no_match() {
    local output="${1:-}"
    local pattern="${2:-}"
    local failure="${3:-}"

    if grep -Eq -- "$pattern" <<<"$output"; then
        fail "$failure"
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TOOLCHAIN_ROOT="$TMP/toolchains"
DARWIN_BIN="$TMP/darwin-bin"
LINUX_BIN="$TMP/linux-bin"
FLUTTER_VERSION="3.47.6"
DART_VERSION="3.13.5"

mkdir -p "$TOOLCHAIN_ROOT" "$DARWIN_BIN" "$LINUX_BIN"

make_fake_uname() {
    local directory="${1:-}"
    local system="${2:-}"

    cat > "$directory/uname" <<SCRIPT
#!/usr/bin/env bash
if [[ "\${1:-}" == "-s" ]]; then
    echo "$system"
else
    exec /usr/bin/uname "\$@"
fi
SCRIPT

    chmod +x "$directory/uname"
}

make_fake_uname "$DARWIN_BIN" "Darwin"
make_fake_uname "$LINUX_BIN" "Linux"

# Synthetic Xcode 27.0 toolchain (macOS only).
cat > "$DARWIN_BIN/xcode-select" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-p" ]]; then
    echo "/Applications/Xcode.app/Contents/Developer"
    exit 0
fi
exit 1
SCRIPT

cat > "$DARWIN_BIN/xcodebuild" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
    printf 'Xcode 27.0\nBuild version 27A0000\n'
    exit 0
fi
exit 1
SCRIPT

cat > "$DARWIN_BIN/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
case "$*" in
    "--sdk iphoneos --show-sdk-version"|\
    "--sdk iphonesimulator --show-sdk-version")
        echo "27.0"
        ;;
    "--find simctl"|"--find clang")
        echo "/usr/bin/synthetic"
        ;;
    *)
        exit 1
        ;;
esac
SCRIPT

chmod +x \
    "$DARWIN_BIN/xcode-select" \
    "$DARWIN_BIN/xcodebuild" \
    "$DARWIN_BIN/xcrun"

# Synthetic pre-existing Flutter installation, shared by both hosts.
FLUTTER_ROOT_FIXTURE="$TOOLCHAIN_ROOT/flutter/$FLUTTER_VERSION"
mkdir -p "$FLUTTER_ROOT_FIXTURE/bin"

cat > "$FLUTTER_ROOT_FIXTURE/bin/flutter" <<BINARY
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
    echo "Flutter $FLUTTER_VERSION"
    echo "Dart $DART_VERSION"
fi
BINARY

cat > "$FLUTTER_ROOT_FIXTURE/bin/dart" <<BINARY
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
    echo "Dart SDK version: $DART_VERSION"
fi
BINARY

chmod +x \
    "$FLUTTER_ROOT_FIXTURE/bin/flutter" \
    "$FLUTTER_ROOT_FIXTURE/bin/dart"

snapshot_tree() {
    (
        cd "$1"
        find . | LC_ALL=C sort
        find . -type f -exec cksum {} + | LC_ALL=C sort
    )
}

FLUTTER_SNAPSHOT_BEFORE="$(snapshot_tree "$TOOLCHAIN_ROOT/flutter")"
MANIFEST_CKSUM_BEFORE="$(cksum < "$MANIFEST")"

# Run a command with the pinned host and the synthetic toolchain root.
# Sets OUTPUT and RC.
run_on_host() {
    local host_bin="${1:-}"
    shift

    set +e
    OUTPUT="$(
        PATH="$host_bin:$PATH" \
        CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
        "$@" 2>&1
    )"
    RC=$?
    set -e
}

###########################################################################
printf '%s\n' '--- DARWIN: android-sdk PROVIDER IS NOT_APPLICABLE ---'
###########################################################################

run_on_host "$DARWIN_BIN" \
    "$ANDROID_PROVIDER" DETECT android-sdk 36 "$TOOLCHAIN_ROOT"

printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "DARWIN_ANDROID_DETECT_RC"

expect_line "$OUTPUT" \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=NOT_APPLICABLE' \
    "DARWIN_ANDROID_DETECT_STATE"

expect_line "$OUTPUT" \
    'CBS_TOOLCHAIN_PROVIDER_REASON=HOST_PLATFORM_UNSUPPORTED' \
    "DARWIN_ANDROID_DETECT_REASON"

expect_line "$OUTPUT" \
    "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$TOOLCHAIN_ROOT/android-sdk/36" \
    "DARWIN_ANDROID_DETECT_PATH"

for operation in ENSURE VERIFY
do
    run_on_host "$DARWIN_BIN" \
        "$ANDROID_PROVIDER" "$operation" android-sdk 36 "$TOOLCHAIN_ROOT"

    printf '%s\n' "$OUTPUT"

    [[ "$RC" -eq 82 ]] ||
        fail "DARWIN_ANDROID_${operation}_RC"

    expect_line "$OUTPUT" \
        'CBS_TOOLCHAIN_PROVIDER_ERROR=HOST_PLATFORM_UNSUPPORTED' \
        "DARWIN_ANDROID_${operation}_REASON"
done

[[ ! -e "$TOOLCHAIN_ROOT/android-sdk" ]] ||
    fail "DARWIN_ANDROID_PROVIDER_MUTATED"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_PROVIDER=PASS"

###########################################################################
printf '%s\n' '--- DARWIN: TOOLCHAIN MANAGER KEEPS NOT_APPLICABLE SEMANTICS ---'
###########################################################################

ANDROID_TOOLCHAIN_MANIFEST="$TMP/android-sdk.env"

cat > "$ANDROID_TOOLCHAIN_MANIFEST" <<'MANIFEST'
CBS_TOOLCHAIN_ID=android-sdk
CBS_TOOLCHAIN_VERSION=36
CBS_TOOLCHAIN_PROVIDER=android-sdk
MANIFEST

run_on_host "$DARWIN_BIN" \
    "$TOOLCHAIN_MANAGER" resolve "$ANDROID_TOOLCHAIN_MANIFEST"

printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "DARWIN_MANAGER_RESOLVE_RC"

expect_line "$OUTPUT" \
    'CBS_TOOLCHAIN_INSTALLATION_STATE=NOT_APPLICABLE' \
    "DARWIN_MANAGER_STATE"

expect_line "$OUTPUT" \
    'CBS_TOOLCHAIN_DECISION=BLOCK' \
    "DARWIN_MANAGER_DECISION"

expect_line "$OUTPUT" \
    'CBS_TOOLCHAIN_MUTATION=NONE' \
    "DARWIN_MANAGER_MUTATION"

# Direct ensure must block without invoking the provider ENSURE operation.
run_on_host "$DARWIN_BIN" \
    "$TOOLCHAIN_MANAGER" ensure "$ANDROID_TOOLCHAIN_MANIFEST"

printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "DARWIN_MANAGER_ENSURE_RC"

expect_line "$OUTPUT" \
    'CBS_TOOLCHAIN_ERROR=BLOCKED' \
    "DARWIN_MANAGER_ENSURE_BLOCK"

[[ ! -e "$TOOLCHAIN_ROOT/android-sdk" ]] ||
    fail "DARWIN_MANAGER_MUTATED"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_MANAGER=PASS"

###########################################################################
printf '%s\n' '--- DARWIN: FLUTTER STACK RESOLVES WITHOUT ANDROID SDK ---'
###########################################################################

run_on_host "$DARWIN_BIN" "$CBS" stack resolve "$MANIFEST"

[[ "$RC" -eq 0 ]] ||
    fail "DARWIN_STACK_RESOLVE_RC"

expect_line "$OUTPUT" \
    'CBS_STACK_RESOLUTION_RESULT=PASS' \
    "DARWIN_STACK_RESOLVE_RESULT"

# Manifest contract preserved: Android SDK stays REQUIRED in the declaration.
expect_line "$OUTPUT" \
    'CBS_STACK_MANAGED_TOOLCHAIN_ID=ANDROID_SDK' \
    "DARWIN_STACK_ANDROID_DECLARED"

run_on_host "$DARWIN_BIN" \
    "$ROOT/cbs/stack/stack_toolchain_evaluator.sh" "$MANIFEST"

printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "DARWIN_EVALUATE_RC"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_REQUIRED_COUNT=3' \
    "DARWIN_EVALUATE_REQUIRED_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_MISSING_COUNT=0' \
    "DARWIN_EVALUATE_MISSING_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_NOT_APPLICABLE_COUNT=1' \
    "DARWIN_EVALUATE_NOT_APPLICABLE_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_FAILURE_COUNT=0' \
    "DARWIN_EVALUATE_FAILURE_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_EVALUATION_RESULT=PASS' \
    "DARWIN_EVALUATE_RESULT"

expect_line "$OUTPUT" \
    'CBS_STACK_MANAGED_TOOLCHAIN_INSTALLATION_STATE=NOT_APPLICABLE' \
    "DARWIN_EVALUATE_ANDROID_STATE"

expect_line "$OUTPUT" \
    'CBS_STACK_MANAGED_TOOLCHAIN_INSTALLATION_STATE=PRESENT_COMPATIBLE' \
    "DARWIN_EVALUATE_COMPATIBLE_STATE"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_EVALUATE=PASS"

###########################################################################
printf '%s\n' '--- DARWIN: STACK ENVIRONMENT IS READY FOR iOS ---'
###########################################################################

run_on_host "$DARWIN_BIN" "$CBS" stack environment "$MANIFEST"

printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "DARWIN_ENVIRONMENT_RC"

expect_line "$OUTPUT" \
    'export CBS_STACK_ENVIRONMENT_STATE=READY' \
    "DARWIN_ENVIRONMENT_STATE"

expect_line "$OUTPUT" \
    'export CBS_STACK_ENVIRONMENT_NOT_APPLICABLE_COUNT=1' \
    "DARWIN_ENVIRONMENT_NOT_APPLICABLE_COUNT"

expect_line "$OUTPUT" \
    "export FLUTTER_ROOT=$FLUTTER_ROOT_FIXTURE" \
    "DARWIN_ENVIRONMENT_FLUTTER_ROOT"

expect_line "$OUTPUT" \
    'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer' \
    "DARWIN_ENVIRONMENT_DEVELOPER_DIR"

expect_no_match "$OUTPUT" \
    '^export (CBS_ANDROID_SDK_ROOT|ANDROID_SDK_ROOT|ANDROID_HOME)=' \
    "DARWIN_ENVIRONMENT_ANDROID_EXPORTED"

expect_no_match "$OUTPUT" \
    '^export PATH=.*android-sdk' \
    "DARWIN_ENVIRONMENT_ANDROID_PATH"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_ENVIRONMENT=PASS"

###########################################################################
printf '%s\n' '--- DARWIN: STACK ENSURE DOES NOT PROVISION ANDROID SDK ---'
###########################################################################

run_on_host "$DARWIN_BIN" "$CBS" stack toolchains ensure "$MANIFEST"

printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "DARWIN_ENSURE_RC"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_REQUIRED_COUNT=3' \
    "DARWIN_ENSURE_REQUIRED_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_ENSURED_COUNT=2' \
    "DARWIN_ENSURE_ENSURED_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_NOT_APPLICABLE_COUNT=1' \
    "DARWIN_ENSURE_NOT_APPLICABLE_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_FAILURE_COUNT=0' \
    "DARWIN_ENSURE_FAILURE_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_ENSURE_RESULT=PASS' \
    "DARWIN_ENSURE_RESULT"

expect_line "$OUTPUT" \
    'CBS_STACK_MANAGED_TOOLCHAIN_ACTION=REUSE' \
    "DARWIN_ENSURE_REUSE"

[[ ! -e "$TOOLCHAIN_ROOT/android-sdk" ]] ||
    fail "DARWIN_ENSURE_ANDROID_SDK_CREATED"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_ENSURE=PASS"

###########################################################################
printf '%s\n' '--- DARWIN: XCODE REMAINS ENFORCED (NO FALSE READY) ---'
###########################################################################

NO_XCODE_BIN="$TMP/darwin-no-xcode-bin"
mkdir -p "$NO_XCODE_BIN"
make_fake_uname "$NO_XCODE_BIN" "Darwin"

# Restrict PATH so no real Xcode tool can be found.
set +e
OUTPUT="$(
    PATH="$NO_XCODE_BIN:/usr/bin:/bin" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$CBS" stack environment "$MANIFEST" 2>&1
)"
RC=$?
set -e

printf '%s\n' "$OUTPUT"

if PATH="/usr/bin:/bin" command -v xcode-select >/dev/null 2>&1
then
    echo "TEST_FLUTTER_STACK_MACOS_COMPAT_XCODE_ENFORCED=SKIPPED_REAL_XCODE_IN_SYSTEM_PATH"
else
    [[ "$RC" -eq 71 ]] ||
        fail "DARWIN_NO_XCODE_RC"

    expect_line "$OUTPUT" \
        'CBS_STACK_ENVIRONMENT_ERROR=REQUIRED_TOOLCHAIN_NOT_READY' \
        "DARWIN_NO_XCODE_ERROR"

    expect_line "$OUTPUT" \
        'CBS_STACK_MANAGED_TOOLCHAIN_ID=XCODE' \
        "DARWIN_NO_XCODE_ID"

    expect_line "$OUTPUT" \
        'CBS_STACK_MANAGED_TOOLCHAIN_STATE=MISSING' \
        "DARWIN_NO_XCODE_STATE"

    echo "TEST_FLUTTER_STACK_MACOS_COMPAT_XCODE_ENFORCED=PASS"
fi

###########################################################################
printf '%s\n' '--- LINUX: ANDROID SDK REMAINS REQUIRED (NON-REGRESSION) ---'
###########################################################################

# Without an Android SDK, a Linux host must still be blocked.
run_on_host "$LINUX_BIN" \
    "$ANDROID_PROVIDER" DETECT android-sdk 36 "$TOOLCHAIN_ROOT"

[[ "$RC" -eq 0 ]] ||
    fail "LINUX_ANDROID_DETECT_RC"

expect_line "$OUTPUT" \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING' \
    "LINUX_ANDROID_DETECT_MISSING"

run_on_host "$LINUX_BIN" "$CBS" stack environment "$MANIFEST"

printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 71 ]] ||
    fail "LINUX_ENVIRONMENT_BLOCK_RC"

expect_line "$OUTPUT" \
    'CBS_STACK_ENVIRONMENT_ERROR=REQUIRED_TOOLCHAIN_NOT_READY' \
    "LINUX_ENVIRONMENT_BLOCK_ERROR"

expect_line "$OUTPUT" \
    'CBS_STACK_MANAGED_TOOLCHAIN_ID=ANDROID_SDK' \
    "LINUX_ENVIRONMENT_BLOCK_ID"

expect_line "$OUTPUT" \
    'CBS_STACK_MANAGED_TOOLCHAIN_STATE=MISSING' \
    "LINUX_ENVIRONMENT_BLOCK_STATE"

expect_line "$OUTPUT" \
    'CBS_STACK_MANAGED_TOOLCHAIN_DECISION=INSTALL' \
    "LINUX_ENVIRONMENT_BLOCK_DECISION"

[[ ! -e "$TOOLCHAIN_ROOT/android-sdk" ]] ||
    fail "LINUX_ENVIRONMENT_MUTATED"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_LINUX_REQUIRES_ANDROID=PASS"

###########################################################################
printf '%s\n' '--- LINUX: ANDROID SDK EXPORTS PRESERVED, XCODE NOT_APPLICABLE ---'
###########################################################################

# Synthetic Android SDK layout accepted by the provider DETECT contract.
ANDROID_ROOT="$TOOLCHAIN_ROOT/android-sdk/36"

mkdir -p \
    "$ANDROID_ROOT/cmdline-tools/23.0/bin" \
    "$ANDROID_ROOT/platform-tools" \
    "$ANDROID_ROOT/build-tools/36.0.0" \
    "$ANDROID_ROOT/platforms/android-36" \
    "$ANDROID_ROOT/ndk/28.2.13676358" \
    "$ANDROID_ROOT/emulator" \
    "$ANDROID_ROOT/system-images/android-36/google_apis_playstore/x86_64"

for executable in \
    "$ANDROID_ROOT/cmdline-tools/23.0/bin/sdkmanager" \
    "$ANDROID_ROOT/platform-tools/adb" \
    "$ANDROID_ROOT/build-tools/36.0.0/aapt2" \
    "$ANDROID_ROOT/emulator/emulator"
do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$executable"
    chmod +x "$executable"
done

: > "$ANDROID_ROOT/platforms/android-36/android.jar"
: > "$ANDROID_ROOT/system-images/android-36/google_apis_playstore/x86_64/source.properties"

run_on_host "$LINUX_BIN" "$CBS" stack environment "$MANIFEST"

printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "LINUX_ENVIRONMENT_RC"

expect_line "$OUTPUT" \
    'export CBS_STACK_ENVIRONMENT_STATE=READY' \
    "LINUX_ENVIRONMENT_STATE"

expect_line "$OUTPUT" \
    "export ANDROID_HOME=$ANDROID_ROOT" \
    "LINUX_ENVIRONMENT_ANDROID_HOME"

expect_line "$OUTPUT" \
    "export ANDROID_SDK_ROOT=$ANDROID_ROOT" \
    "LINUX_ENVIRONMENT_ANDROID_SDK_ROOT"

expect_line "$OUTPUT" \
    "export FLUTTER_ROOT=$FLUTTER_ROOT_FIXTURE" \
    "LINUX_ENVIRONMENT_FLUTTER_ROOT"

expect_line "$OUTPUT" \
    'export CBS_STACK_ENVIRONMENT_NOT_APPLICABLE_COUNT=1' \
    "LINUX_ENVIRONMENT_NOT_APPLICABLE_COUNT"

expect_no_match "$OUTPUT" \
    '^export DEVELOPER_DIR=' \
    "LINUX_ENVIRONMENT_DEVELOPER_DIR"

run_on_host "$LINUX_BIN" \
    "$ROOT/cbs/stack/stack_toolchain_evaluator.sh" "$MANIFEST"

[[ "$RC" -eq 0 ]] ||
    fail "LINUX_EVALUATE_RC"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_REQUIRED_COUNT=3' \
    "LINUX_EVALUATE_REQUIRED_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_MISSING_COUNT=0' \
    "LINUX_EVALUATE_MISSING_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_NOT_APPLICABLE_COUNT=1' \
    "LINUX_EVALUATE_NOT_APPLICABLE_COUNT"

expect_line "$OUTPUT" \
    'CBS_STACK_TOOLCHAIN_EVALUATION_RESULT=PASS' \
    "LINUX_EVALUATE_RESULT"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_LINUX_NON_REGRESSION=PASS"

###########################################################################
printf '%s\n' '--- PRESERVATION: FLUTTER INSTALLATION AND MANIFEST UNTOUCHED ---'
###########################################################################

FLUTTER_SNAPSHOT_AFTER="$(snapshot_tree "$TOOLCHAIN_ROOT/flutter")"

[[ "$FLUTTER_SNAPSHOT_BEFORE" == "$FLUTTER_SNAPSHOT_AFTER" ]] ||
    fail "FLUTTER_INSTALLATION_MODIFIED"

[[ "$MANIFEST_CKSUM_BEFORE" == "$(cksum < "$MANIFEST")" ]] ||
    fail "STACK_MANIFEST_MODIFIED"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_PRESERVATION=PASS"

echo "TEST_FLUTTER_STACK_MACOS_COMPAT_RESULT=PASS"
