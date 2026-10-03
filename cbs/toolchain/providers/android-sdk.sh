#!/usr/bin/env bash

set -Eeuo pipefail

operation="${1:-}"
toolchain_id="${2:-}"
requested_version="${3:-}"
toolchain_root="${4:-}"

fail_usage() {
    echo "CBS_TOOLCHAIN_PROVIDER_ERROR=USAGE" >&2
    exit 64
}

fail_provider() {
    local error="${1:-PROVIDER_FAILURE}"
    echo "CBS_TOOLCHAIN_PROVIDER_ERROR=$error" >&2
    exit 82
}

[[ -n "$operation" ]] || fail_usage
[[ -n "$toolchain_id" ]] || fail_usage
[[ -n "$requested_version" ]] || fail_usage
[[ -n "$toolchain_root" ]] || fail_usage

[[ "$toolchain_id" == "android-sdk" ]] ||
    fail_provider "UNSUPPORTED_TOOLCHAIN"

[[ "$requested_version" == "36" ]] ||
    fail_provider "UNSUPPORTED_PROFILE"

resolved_path="$toolchain_root/$toolchain_id/$requested_version"

readonly CBS_ANDROID_CMDLINE_TOOLS_PACKAGE="cmdline-tools;23.0"
readonly CBS_ANDROID_PLATFORM_PACKAGE="platforms;android-36"
readonly CBS_ANDROID_BUILD_TOOLS_PACKAGE="build-tools;36.0.0"
readonly CBS_ANDROID_PLATFORM_TOOLS_PACKAGE="platform-tools"
readonly CBS_ANDROID_NDK_PACKAGE="ndk;28.2.13676358"

readonly CBS_ANDROID_CMDLINE_TOOLS_URL_DEFAULT="https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip"
readonly CBS_ANDROID_CMDLINE_TOOLS_SHA1_DEFAULT="e025545c62a8e64c7559119566a569fb1dec5f60"

cbs_android_sdk_detect() {
    local sdkmanager="$resolved_path/cmdline-tools/23.0/bin/sdkmanager"
    local adb="$resolved_path/platform-tools/adb"
    local aapt2="$resolved_path/build-tools/36.0.0/aapt2"
    local platform_jar="$resolved_path/platforms/android-36/android.jar"
    local ndk_dir="$resolved_path/ndk/28.2.13676358"

    if [[ ! -e "$resolved_path" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        return 0
    fi

    if [[ \
        ! -x "$sdkmanager" || \
        ! -x "$adb" || \
        ! -x "$aapt2" || \
        ! -f "$platform_jar" || \
        ! -d "$ndk_dir" \
    ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=INVALID"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        return 0
    fi

    echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE"
    echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
}

cbs_android_sdk_property_value() {
    local file="${1:-}"
    local key="${2:-}"

    [[ -f "$file" ]] || return 1

    awk -F= -v key="$key" '
        {
            property_key = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", property_key)
        }

        property_key == key {
            sub(/^[^=]*=/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
    ' "$file"
}

cbs_android_sdk_verify() {
    local sdkmanager="$resolved_path/cmdline-tools/23.0/bin/sdkmanager"
    local adb="$resolved_path/platform-tools/adb"
    local aapt2="$resolved_path/build-tools/36.0.0/aapt2"
    local platform_jar="$resolved_path/platforms/android-36/android.jar"
    local ndk_dir="$resolved_path/ndk/28.2.13676358"

    local cmdline_properties="$resolved_path/cmdline-tools/23.0/source.properties"
    local platform_tools_properties="$resolved_path/platform-tools/source.properties"
    local build_tools_properties="$resolved_path/build-tools/36.0.0/source.properties"
    local platform_properties="$resolved_path/platforms/android-36/source.properties"
    local ndk_properties="$resolved_path/ndk/28.2.13676358/source.properties"

    if [[ \
        ! -x "$sdkmanager" || \
        ! -x "$adb" || \
        ! -x "$aapt2" || \
        ! -f "$platform_jar" || \
        ! -d "$ndk_dir" || \
        ! -f "$cmdline_properties" || \
        ! -f "$platform_tools_properties" || \
        ! -f "$build_tools_properties" || \
        ! -f "$platform_properties" || \
        ! -f "$ndk_properties" \
    ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    fi

    local cmdline_version
    local platform_tools_version
    local build_tools_version
    local platform_api_level
    local ndk_version

    cmdline_version="$(
        cbs_android_sdk_property_value \
            "$cmdline_properties" \
            "Pkg.Revision"
    )"

    platform_tools_version="$(
        cbs_android_sdk_property_value \
            "$platform_tools_properties" \
            "Pkg.Revision"
    )"

    build_tools_version="$(
        cbs_android_sdk_property_value \
            "$build_tools_properties" \
            "Pkg.Revision"
    )"

    platform_api_level="$(
        cbs_android_sdk_property_value \
            "$platform_properties" \
            "AndroidVersion.ApiLevel"
    )"

    ndk_version="$(
        cbs_android_sdk_property_value \
            "$ndk_properties" \
            "Pkg.Revision"
    )"

    if [[ \
        "$cmdline_version" != "23.0" || \
        "$platform_tools_version" != "37.0.1" || \
        "$build_tools_version" != "36.0.0" || \
        "$platform_api_level" != "36" || \
        "$ndk_version" != "28.2.13676358" \
    ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    fi

    echo "CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=36"
    echo "CBS_ANDROID_SDK_PROFILE_OBSERVED=36"
    echo "CBS_ANDROID_SDK_CMDLINE_TOOLS_OBSERVED=$cmdline_version"
    echo "CBS_ANDROID_SDK_PLATFORM_TOOLS_OBSERVED=$platform_tools_version"
    echo "CBS_ANDROID_SDK_PLATFORM_OBSERVED=android-$platform_api_level"
    echo "CBS_ANDROID_SDK_BUILD_TOOLS_OBSERVED=$build_tools_version"
    echo "CBS_ANDROID_SDK_NDK_OBSERVED=$ndk_version"
    echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS"
}

cbs_android_sdk_ensure() {
    command -v unzip >/dev/null 2>&1 ||
        fail_provider "UNZIP_MISSING"

    command -v sha1sum >/dev/null 2>&1 ||
        fail_provider "SHA1SUM_MISSING"

    [[ ! -e "$resolved_path" ]] ||
        fail_provider "TARGET_ALREADY_EXISTS"

    local archive_url="${CBS_ANDROID_CMDLINE_TOOLS_URL:-$CBS_ANDROID_CMDLINE_TOOLS_URL_DEFAULT}"
    local expected_sha1="${CBS_ANDROID_CMDLINE_TOOLS_SHA1:-$CBS_ANDROID_CMDLINE_TOOLS_SHA1_DEFAULT}"

    local target_parent
    local work_dir
    local archive_file
    local extraction_dir
    local staging_path

    target_parent="$(dirname "$resolved_path")"
    mkdir -p "$target_parent"

    work_dir="$(mktemp -d)"
    archive_file="$work_dir/cmdline-tools.zip"
    extraction_dir="$work_dir/extracted"

    staging_path="$(
        mktemp -d \
            "$target_parent/.${toolchain_id}-${requested_version}.staging.XXXXXX"
    )"

    printf -v cleanup_work_dir '%q' "$work_dir"
    printf -v cleanup_staging_path '%q' "$staging_path"

    trap \
        "rm -rf -- $cleanup_work_dir $cleanup_staging_path" \
        EXIT

    mkdir -p "$extraction_dir"

    case "$archive_url" in
        file://*)
            cp "${archive_url#file://}" "$archive_file"
            ;;
        *)
            command -v curl >/dev/null 2>&1 ||
                fail_provider "CURL_MISSING"

            if ! curl \
                --fail \
                --silent \
                --show-error \
                --location \
                "$archive_url" \
                -o "$archive_file"
            then
                fail_provider "DOWNLOAD_FAILED"
            fi
            ;;
    esac

    local observed_sha1
    observed_sha1="$(
        sha1sum "$archive_file" |
            awk '{print $1}'
    )"

    [[ "$observed_sha1" == "$expected_sha1" ]] ||
        fail_provider "CHECKSUM_MISMATCH"

    unzip -q "$archive_file" -d "$extraction_dir" ||
        fail_provider "EXTRACTION_FAILED"

    [[ -x "$extraction_dir/cmdline-tools/bin/sdkmanager" ]] ||
        fail_provider "SDKMANAGER_MISSING_FROM_ARCHIVE"

    mkdir -p "$staging_path/cmdline-tools"

    mv \
        "$extraction_dir/cmdline-tools" \
        "$staging_path/cmdline-tools/23.0"

    local sdkmanager="$staging_path/cmdline-tools/23.0/bin/sdkmanager"
    local license_rc=0

    set +o pipefail
    yes | "$sdkmanager" \
        --sdk_root="$staging_path" \
        --licenses >/dev/null 2>&1
    license_rc="${PIPESTATUS[1]}"
    set -o pipefail

    if [[ "$license_rc" -ne 0 ]]; then
        fail_provider "LICENSE_ACCEPTANCE_FAILED"
    fi

    if ! "$sdkmanager" \
        --sdk_root="$staging_path" \
        "$CBS_ANDROID_PLATFORM_TOOLS_PACKAGE" \
        "$CBS_ANDROID_PLATFORM_PACKAGE" \
        "$CBS_ANDROID_BUILD_TOOLS_PACKAGE" \
        "$CBS_ANDROID_NDK_PACKAGE"
    then
        fail_provider "SDK_PACKAGE_INSTALL_FAILED"
    fi

    local canonical_resolved_path="$resolved_path"
    local detect_output
    local verify_output
    local verify_rc

    resolved_path="$staging_path"

    detect_output="$(cbs_android_sdk_detect)"

    if ! grep -Fq \
        'CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE' \
        <<<"$detect_output"
    then
        resolved_path="$canonical_resolved_path"
        fail_provider "POST_INSTALL_DETECT_FAILED"
    fi

    set +e
    verify_output="$(cbs_android_sdk_verify 2>&1)"
    verify_rc=$?
    set -e

    resolved_path="$canonical_resolved_path"

    if [[ "$verify_rc" -ne 0 ]]; then
        fail_provider "POST_INSTALL_VERIFY_FAILED"
    fi

    grep -Fq \
        'CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS' \
        <<<"$verify_output" ||
        fail_provider "POST_INSTALL_VERIFY_FAILED"

    [[ ! -e "$resolved_path" ]] ||
        fail_provider "TARGET_ALREADY_EXISTS"

    mv "$staging_path" "$resolved_path"

    staging_path=""

    echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
    echo "CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=PASS"
}
case "$operation" in
    DETECT)
        cbs_android_sdk_detect
        ;;

    ENSURE)
        cbs_android_sdk_ensure
        ;;

    VERIFY)
        cbs_android_sdk_verify
        ;;

    *)
        echo "CBS_TOOLCHAIN_PROVIDER_ERROR=UNSUPPORTED_OPERATION" >&2
        exit 82
        ;;
esac
