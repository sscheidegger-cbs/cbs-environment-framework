#!/usr/bin/env bash

set -Eeuo pipefail

action="${1:-}"
device="${2:-medium_phone}"

SDK_ROOT="${CBS_ANDROID_SDK_ROOT:-$HOME/.cbs/toolchains/android-sdk/36}"
ANDROID="$SDK_ROOT/cmdline-tools/23.0/bin/android"
ADB="$SDK_ROOT/platform-tools/adb"

fail() {
    echo "CBS_ANDROID_RUNTIME_ERROR=$1" >&2
    exit 82
}

[[ -x "$ANDROID" ]] ||
    fail "ANDROID_CLI_MISSING"

android_device_exists() {
    "$ANDROID" \
        --sdk="$SDK_ROOT" \
        emulator list |
    grep -Fxq "$device"
}

case "$action" in
    ensure)
        if android_device_exists; then
            echo "CBS_ANDROID_RUNTIME_DEVICE=$device"
            echo "CBS_ANDROID_RUNTIME_ACTION=REUSE"
            echo "CBS_ANDROID_RUNTIME_ENSURE_RESULT=PASS"
            exit 0
        fi

        "$ANDROID" \
            --sdk="$SDK_ROOT" \
            emulator create "$device"

        android_device_exists ||
            fail "DEVICE_CREATION_FAILED"

        echo "CBS_ANDROID_RUNTIME_DEVICE=$device"
        echo "CBS_ANDROID_RUNTIME_ACTION=CREATE"
        echo "CBS_ANDROID_RUNTIME_ENSURE_RESULT=PASS"
        ;;

    start)
        android_device_exists ||
            fail "DEVICE_MISSING"

        "$ANDROID" \
            --sdk="$SDK_ROOT" \
            emulator start "$device"

        echo "CBS_ANDROID_RUNTIME_DEVICE=$device"

        if [[ -x "$ADB" ]]; then
            "$ADB" devices -l
        fi

        echo "CBS_ANDROID_RUNTIME_START_RESULT=PASS"
        ;;

    list)
        "$ANDROID" \
            --sdk="$SDK_ROOT" \
            emulator list
        ;;

    stop)
        android_device_exists ||
            fail "DEVICE_MISSING"

        "$ANDROID" \
            --sdk="$SDK_ROOT" \
            emulator stop "$device"

        echo "CBS_ANDROID_RUNTIME_STOP_RESULT=PASS"
        ;;

    *)
        echo "CBS_ANDROID_RUNTIME_ERROR=USAGE" >&2
        echo "Usage: android_emulator_manager.sh {ensure|start|list|stop} [device]" >&2
        exit 64
        ;;
esac
