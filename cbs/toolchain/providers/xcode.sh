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

[[ "$toolchain_id" == "xcode" ]] ||
    fail_provider "UNSUPPORTED_TOOLCHAIN"

[[ "$requested_version" == "15" ]] ||
    fail_provider "UNSUPPORTED_PROFILE"

resolved_path="$toolchain_root/$toolchain_id/$requested_version"

cbs_xcode_host_is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

cbs_xcode_detect() {
    if ! cbs_xcode_host_is_macos; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=NOT_APPLICABLE"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        echo "CBS_TOOLCHAIN_PROVIDER_REASON=HOST_PLATFORM_UNSUPPORTED"
        return 0
    fi

    if ! command -v xcode-select >/dev/null 2>&1 ||
       ! command -v xcodebuild >/dev/null 2>&1; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        return 0
    fi

    local developer_dir
    developer_dir="$(xcode-select -p 2>/dev/null || true)"

    if [[ -z "$developer_dir" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        return 0
    fi

    local version_output
    local xcode_version
    local xcode_major

    version_output="$(xcodebuild -version 2>/dev/null || true)"
    xcode_version="$(
        awk '
            /^Xcode[[:space:]]+[0-9]/ {
                print $2
                exit
            }
        ' <<<"$version_output"
    )"

    if [[ -z "$xcode_version" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=INVALID"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$developer_dir"
        return 0
    fi

    xcode_major="${xcode_version%%.*}"

    if [[ ! "$xcode_major" =~ ^[0-9]+$ ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=INVALID"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$developer_dir"
        return 0
    fi

    if (( xcode_major < requested_version )); then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_INCOMPATIBLE"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$developer_dir"
        echo "CBS_XCODE_VERSION_OBSERVED=$xcode_version"
        return 0
    fi

    echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE"
    echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$developer_dir"
    echo "CBS_XCODE_VERSION_OBSERVED=$xcode_version"
}

cbs_xcode_ensure() {
    if ! cbs_xcode_host_is_macos; then
        fail_provider "HOST_PLATFORM_UNSUPPORTED"
    fi

    fail_provider "EXTERNAL_INSTALLATION_REQUIRED"
}

cbs_xcode_verify() {
    if ! cbs_xcode_host_is_macos; then
        fail_provider "HOST_PLATFORM_UNSUPPORTED"
    fi

    command -v xcodebuild >/dev/null 2>&1 || {
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    }

    command -v xcrun >/dev/null 2>&1 || {
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    }

    local version_output
    local xcode_version
    local build_version
    local xcode_major

    version_output="$(xcodebuild -version 2>/dev/null || true)"

    xcode_version="$(
        awk '
            /^Xcode[[:space:]]+[0-9]/ {
                print $2
                exit
            }
        ' <<<"$version_output"
    )"

    build_version="$(
        awk '
            /^Build version[[:space:]]+/ {
                print $3
                exit
            }
        ' <<<"$version_output"
    )"

    if [[ -z "$xcode_version" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    fi

    xcode_major="${xcode_version%%.*}"

    if [[ ! "$xcode_major" =~ ^[0-9]+$ ]] ||
       (( xcode_major < requested_version )); then
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    fi

    local iphoneos_sdk_version
    local iphonesimulator_sdk_version

    iphoneos_sdk_version="$(
        xcrun \
            --sdk iphoneos \
            --show-sdk-version \
            2>/dev/null || true
    )"

    iphonesimulator_sdk_version="$(
        xcrun \
            --sdk iphonesimulator \
            --show-sdk-version \
            2>/dev/null || true
    )"

    if [[ -z "$iphoneos_sdk_version" ]] ||
       [[ -z "$iphonesimulator_sdk_version" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    fi

    if ! xcrun --find simctl >/dev/null 2>&1; then
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    fi

    if ! xcrun --find clang >/dev/null 2>&1; then
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        return 82
    fi

    echo "CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=$xcode_version"
    echo "CBS_XCODE_BUILD_VERSION_OBSERVED=$build_version"
    echo "CBS_XCODE_IPHONEOS_SDK_VERSION_OBSERVED=$iphoneos_sdk_version"
    echo "CBS_XCODE_IPHONESIMULATOR_SDK_VERSION_OBSERVED=$iphonesimulator_sdk_version"
    echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS"
}

case "$operation" in
    DETECT)
        cbs_xcode_detect
        ;;

    ENSURE)
        cbs_xcode_ensure
        ;;

    VERIFY)
        cbs_xcode_verify
        ;;

    *)
        fail_provider "UNSUPPORTED_OPERATION"
        ;;
esac
