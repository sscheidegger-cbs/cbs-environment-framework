#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="$ROOT/cbs/toolchain/providers/android-sdk.sh"

fail() {
    echo "TEST_ANDROID_SDK_PROVIDER_RESULT=FAIL" >&2
    echo "TEST_ANDROID_SDK_PROVIDER_FAILURE=$1" >&2
    return 1
}

printf '%s\n' '--- PROVIDER PRESENCE ---'

[[ -x "$PROVIDER" ]] ||
    fail "PROVIDER_MISSING"

printf '%s\n' '--- PROFILE CONTRACT ---'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TOOLCHAIN_ROOT="$TMP/toolchains"

TOOLCHAIN_ID="android-sdk"
PROFILE_VERSION="36"

set +e
OUTPUT="$(
    "$PROVIDER" \
        DETECT \
        "$TOOLCHAIN_ID" \
        "$PROFILE_VERSION" \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
RC=$?
set -e

printf '%s\n' "$OUTPUT"
printf 'ANDROID_SDK_PROVIDER_DETECT_RC=%s\n' "$RC"

[[ "$RC" -eq 0 ]] ||
    fail "DETECT_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING' \
    <<<"$OUTPUT" ||
    fail "DETECT_MISSING"

grep -Fq \
    "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$TOOLCHAIN_ROOT/android-sdk/36" \
    <<<"$OUTPUT" ||
    fail "RESOLVED_PATH"

echo "TEST_ANDROID_SDK_PROVIDER_DETECT_MISSING=PASS"

printf '%s\n' '--- TECHNOLOGY CONTRACT ---'

grep -Fq 'cmdline-tools;23.0' "$PROVIDER" ||
    fail "CMDLINE_TOOLS_PROFILE"

grep -Fq 'platforms;android-36' "$PROVIDER" ||
    fail "PLATFORM_PROFILE"

grep -Fq 'build-tools;36.0.0' "$PROVIDER" ||
    fail "BUILD_TOOLS_PROFILE"

grep -Fq 'platform-tools' "$PROVIDER" ||
    fail "PLATFORM_TOOLS_PROFILE"

grep -Fq 'ndk;28.2.13676358' "$PROVIDER" ||
    fail "NDK_PROFILE"

grep -Fq 'CBS_ANDROID_EMULATOR_PACKAGE="emulator"' "$PROVIDER" ||
    fail "EMULATOR_PROFILE"

grep -Fq 'system-images;android-36;google_apis_playstore;x86_64' "$PROVIDER" ||
    fail "SYSTEM_IMAGE_PROFILE"

echo "TEST_ANDROID_SDK_PROVIDER_PROFILE=PASS"



printf '%s\n' '--- PREPARE SYNTHETIC CMDLINE TOOLS ---'

FIXTURE_ROOT="$TMP/cmdline-fixture"
FIXTURE_ARCHIVE="$TMP/cmdline-tools.zip"

mkdir -p "$FIXTURE_ROOT/cmdline-tools/bin"

cat > "$FIXTURE_ROOT/cmdline-tools/bin/sdkmanager" <<'SDKMANAGER'
#!/usr/bin/env bash

set -Eeuo pipefail

sdk_root=""

for arg in "$@"; do
    case "$arg" in
        --sdk_root=*)
            sdk_root="${arg#--sdk_root=}"
            ;;
    esac
done

[[ -n "$sdk_root" ]] || exit 64

if [[ " $* " == *" --licenses "* ]]; then
    exit 0
fi

mkdir -p \
    "$sdk_root/platform-tools" \
    "$sdk_root/platforms/android-36" \
    "$sdk_root/build-tools/36.0.0" \
    "$sdk_root/ndk/28.2.13676358" \
    "$sdk_root/emulator" \
    "$sdk_root/system-images/android-36/google_apis_playstore/x86_64"

cat > "$sdk_root/platform-tools/adb" <<'ADB'
#!/usr/bin/env bash
echo "Android Debug Bridge version 1.0.41"
ADB
chmod +x "$sdk_root/platform-tools/adb"

cat > "$sdk_root/build-tools/36.0.0/aapt2" <<'AAPT2'
#!/usr/bin/env bash
echo "Android Asset Packaging Tool"
AAPT2
chmod +x "$sdk_root/build-tools/36.0.0/aapt2"

cat > "$sdk_root/emulator/emulator" <<'EMULATOR'
#!/usr/bin/env bash
echo "Android emulator version 37.2.12.0"
EMULATOR
chmod +x "$sdk_root/emulator/emulator"

: > "$sdk_root/platforms/android-36/android.jar"

cat > "$sdk_root/cmdline-tools/23.0/source.properties" <<'EOF_META'
Pkg.Revision=23.0
EOF_META

cat > "$sdk_root/platform-tools/source.properties" <<'EOF_META'
Pkg.Revision=37.0.1
EOF_META

cat > "$sdk_root/build-tools/36.0.0/source.properties" <<'EOF_META'
Pkg.Revision=36.0.0
EOF_META

cat > "$sdk_root/platforms/android-36/source.properties" <<'EOF_META'
Pkg.Revision=2
AndroidVersion.ApiLevel=36
EOF_META

cat > "$sdk_root/ndk/28.2.13676358/source.properties" <<'EOF_META'
Pkg.Revision=28.2.13676358
EOF_META

cat > "$sdk_root/emulator/source.properties" <<'EOF_META'
Pkg.Revision=37.2.12
EOF_META

cat > "$sdk_root/system-images/android-36/google_apis_playstore/x86_64/source.properties" <<'EOF_META'
Pkg.Revision=7
AndroidVersion.ApiLevel=36
SystemImage.Abi=x86_64
SystemImage.TagId=google_apis_playstore
EOF_META

exit 0
SDKMANAGER

chmod +x "$FIXTURE_ROOT/cmdline-tools/bin/sdkmanager"

python3 - "$FIXTURE_ROOT" "$FIXTURE_ARCHIVE" <<'PYZIP'
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
archive = Path(sys.argv[2])

with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
    for path in root.rglob("*"):
        if path.is_file():
            z.write(path, path.relative_to(root))
PYZIP

FIXTURE_SHA1="$(sha1sum "$FIXTURE_ARCHIVE" | awk '{print $1}')"

printf '%s\n' '--- ENSURE ---'

set +e
ENSURE_OUTPUT="$(
    CBS_ANDROID_CMDLINE_TOOLS_URL="file://$FIXTURE_ARCHIVE" \
    CBS_ANDROID_CMDLINE_TOOLS_SHA1="$FIXTURE_SHA1" \
    "$PROVIDER" \
        ENSURE \
        "$TOOLCHAIN_ID" \
        "$PROFILE_VERSION" \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
ENSURE_RC=$?
set -e

printf '%s\n' "$ENSURE_OUTPUT"
printf 'ANDROID_SDK_PROVIDER_ENSURE_RC=%s\n' "$ENSURE_RC"

[[ "$ENSURE_RC" -eq 0 ]] ||
    fail "ENSURE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=PASS' \
    <<<"$ENSURE_OUTPUT" ||
    fail "ENSURE_RESULT"

RESOLVED_PATH="$TOOLCHAIN_ROOT/android-sdk/36"

[[ -x "$RESOLVED_PATH/cmdline-tools/23.0/bin/sdkmanager" ]] ||
    fail "SDKMANAGER_MISSING"

[[ -x "$RESOLVED_PATH/platform-tools/adb" ]] ||
    fail "ADB_MISSING"

[[ -x "$RESOLVED_PATH/build-tools/36.0.0/aapt2" ]] ||
    fail "AAPT2_MISSING"

[[ -f "$RESOLVED_PATH/platforms/android-36/android.jar" ]] ||
    fail "PLATFORM_JAR_MISSING"

[[ -d "$RESOLVED_PATH/ndk/28.2.13676358" ]] ||
    fail "NDK_MISSING"

[[ -x "$RESOLVED_PATH/emulator/emulator" ]] ||
    fail "EMULATOR_MISSING"

[[ -f "$RESOLVED_PATH/system-images/android-36/google_apis_playstore/x86_64/source.properties" ]] ||
    fail "SYSTEM_IMAGE_MISSING"

echo "TEST_ANDROID_SDK_PROVIDER_ENSURE=PASS"

printf '%s\n' '--- DETECT AFTER ENSURE ---'

POST_OUTPUT="$(
    "$PROVIDER" \
        DETECT \
        "$TOOLCHAIN_ID" \
        "$PROFILE_VERSION" \
        "$TOOLCHAIN_ROOT"
)"

printf '%s\n' "$POST_OUTPUT"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE' \
    <<<"$POST_OUTPUT" ||
    fail "POST_ENSURE_DETECT"

echo "TEST_ANDROID_SDK_PROVIDER_POST_DETECT=PASS"


printf '%s\n' '--- VERIFY ---'

set +e
VERIFY_OUTPUT="$(
    "$PROVIDER" \
        VERIFY \
        "$TOOLCHAIN_ID" \
        "$PROFILE_VERSION" \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
VERIFY_RC=$?
set -e

printf '%s\n' "$VERIFY_OUTPUT"
printf 'ANDROID_SDK_PROVIDER_VERIFY_RC=%s\n' "$VERIFY_RC"

[[ "$VERIFY_RC" -eq 0 ]] ||
    fail "VERIFY_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS' \
    <<<"$VERIFY_OUTPUT" ||
    fail "VERIFY_RESULT"

grep -Fq \
    'CBS_ANDROID_SDK_PROFILE_OBSERVED=36' \
    <<<"$VERIFY_OUTPUT" ||
    fail "VERIFY_PROFILE"


grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=36' \
    <<<"$VERIFY_OUTPUT" ||
    fail "VERIFY_VERSION_OBSERVED"

grep -Fq \
    'CBS_ANDROID_SDK_PLATFORM_OBSERVED=android-36' \
    <<<"$VERIFY_OUTPUT" ||
    fail "VERIFY_PLATFORM"

grep -Fq \
    'CBS_ANDROID_SDK_BUILD_TOOLS_OBSERVED=36.0.0' \
    <<<"$VERIFY_OUTPUT" ||
    fail "VERIFY_BUILD_TOOLS"

grep -Fq \
    'CBS_ANDROID_SDK_NDK_OBSERVED=28.2.13676358' \
    <<<"$VERIFY_OUTPUT" ||
    fail "VERIFY_NDK"


grep -Fq \
    'CBS_ANDROID_SDK_CMDLINE_TOOLS_OBSERVED=23.0' \
    <<<"$VERIFY_OUTPUT" ||
    fail "VERIFY_CMDLINE_TOOLS_VERSION"

grep -Fq \
    'CBS_ANDROID_SDK_PLATFORM_TOOLS_OBSERVED=37.0.1' \
    <<<"$VERIFY_OUTPUT" ||
    fail "VERIFY_PLATFORM_TOOLS_VERSION"

echo "TEST_ANDROID_SDK_PROVIDER_VERIFY=PASS"


printf '%s\n' '--- VERIFY MUST REJECT WRONG PACKAGE VERSION ---'

sed -i \
    's/^Pkg.Revision=36.0.0$/Pkg.Revision=35.0.0/' \
    "$RESOLVED_PATH/build-tools/36.0.0/source.properties"

set +e
BAD_VERIFY_OUTPUT="$(
    "$PROVIDER" \
        VERIFY \
        "$TOOLCHAIN_ID" \
        "$PROFILE_VERSION" \
        "$TOOLCHAIN_ROOT" \
        2>&1
)"
BAD_VERIFY_RC=$?
set -e

printf '%s\n' "$BAD_VERIFY_OUTPUT"
printf 'ANDROID_SDK_PROVIDER_BAD_VERSION_VERIFY_RC=%s\n' "$BAD_VERIFY_RC"

[[ "$BAD_VERIFY_RC" -ne 0 ]] ||
    fail "VERIFY_WRONG_VERSION_MUST_FAIL"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL' \
    <<<"$BAD_VERIFY_OUTPUT" ||
    fail "VERIFY_WRONG_VERSION_RESULT"

echo "TEST_ANDROID_SDK_PROVIDER_VERIFY_WRONG_VERSION=PASS"




printf '%s\n' '--- ENSURE FAILURE MUST BE TRANSACTIONAL ---'

FAIL_ROOT="$TMP/failure-toolchains"
FAIL_FIXTURE_ROOT="$TMP/failing-cmdline-fixture"
FAIL_FIXTURE_ARCHIVE="$TMP/failing-cmdline-tools.zip"

mkdir -p "$FAIL_FIXTURE_ROOT/cmdline-tools/bin"

cat > "$FAIL_FIXTURE_ROOT/cmdline-tools/bin/sdkmanager" <<'SDKMANAGER'
#!/usr/bin/env bash

set -Eeuo pipefail

sdk_root=""

for arg in "$@"; do
    case "$arg" in
        --sdk_root=*)
            sdk_root="${arg#--sdk_root=}"
            ;;
    esac
done

[[ -n "$sdk_root" ]] || exit 64

if [[ " $* " == *" --licenses "* ]]; then
    exit 0
fi

# Simulate a package installer that mutates the target and then fails.
mkdir -p "$sdk_root/platform-tools"
printf '%s\n' 'PARTIAL_INSTALL' > "$sdk_root/platform-tools/partial"

exit 42
SDKMANAGER

chmod +x \
    "$FAIL_FIXTURE_ROOT/cmdline-tools/bin/sdkmanager"

python3 - \
    "$FAIL_FIXTURE_ROOT" \
    "$FAIL_FIXTURE_ARCHIVE" <<'PYZIP'
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
archive = Path(sys.argv[2])

with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
    for path in root.rglob("*"):
        if path.is_file():
            z.write(path, path.relative_to(root))
PYZIP

FAIL_FIXTURE_SHA1="$(
    sha1sum "$FAIL_FIXTURE_ARCHIVE" |
        awk '{print $1}'
)"

set +e
FAIL_OUTPUT="$(
    CBS_ANDROID_CMDLINE_TOOLS_URL="file://$FAIL_FIXTURE_ARCHIVE" \
    CBS_ANDROID_CMDLINE_TOOLS_SHA1="$FAIL_FIXTURE_SHA1" \
    "$PROVIDER" \
        ENSURE \
        "$TOOLCHAIN_ID" \
        "$PROFILE_VERSION" \
        "$FAIL_ROOT" \
        2>&1
)"
FAIL_RC=$?
set -e

printf 'ANDROID_SDK_TRANSACTIONAL_FAILURE_RC=%s\n' "$FAIL_RC"
printf '%s\n' "$FAIL_OUTPUT"

[[ "$FAIL_RC" -eq 82 ]] ||
    fail "TRANSACTIONAL_FAILURE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ERROR=SDK_PACKAGE_INSTALL_FAILED' \
    <<<"$FAIL_OUTPUT" ||
    fail "TRANSACTIONAL_FAILURE_ERROR"

FAIL_TARGET="$FAIL_ROOT/android-sdk/36"

if [[ -e "$FAIL_TARGET" ]]; then
    printf 'ANDROID_SDK_TRANSACTIONAL_TARGET_STATE=PRESENT\n'
    find "$FAIL_TARGET" -maxdepth 4 -print | sort
    fail "TRANSACTIONAL_PARTIAL_TARGET_PRESERVED"
fi

echo "ANDROID_SDK_TRANSACTIONAL_TARGET_STATE=ABSENT"
echo "TEST_ANDROID_SDK_PROVIDER_TRANSACTIONAL_FAILURE=PASS"

echo "TEST_ANDROID_SDK_PROVIDER_RESULT=PASS"
