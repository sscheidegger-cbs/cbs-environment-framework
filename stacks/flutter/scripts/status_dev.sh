#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

source "$SCRIPT_DIR/common.sh"

ANDROID_DEVICE="${CBS_FLUTTER_ANDROID_DEVICE:-medium_phone}"

printf '%s\n' \
    "==========================================" \
    " CBS Flutter Stack - Development status" \
    "=========================================="

cbs_flutter_load_environment

printf '%s\n' '--- STACK ---'

printf 'CBS_STACK_ENVIRONMENT_STATE=%s\n' \
    "${CBS_STACK_ENVIRONMENT_STATE:-}"

printf 'CBS_FLUTTER_ANDROID_DEVICE=%s\n' \
    "$ANDROID_DEVICE"

printf '%s\n' '--- KVM ---'

set +e
cbs_flutter_kvm_session_state
kvm_rc=$?
set -e

case "$kvm_rc" in
    0)
        echo 'CBS_FLUTTER_KVM_STATE=READY'
        ;;
    2)
        echo 'CBS_FLUTTER_KVM_STATE=AVAILABLE_REEXEC_REQUIRED'
        ;;
    *)
        echo 'CBS_FLUTTER_KVM_STATE=NOT_READY'
        ;;
esac

printf '%s\n' '--- CBS ANDROID DEVICES ---'

"$CBS_BIN" runtime android list

printf '%s\n' '--- ADB ---'

adb devices -l

printf '%s\n' '--- FLUTTER DEVICES ---'

flutter devices

printf 'CBS_FLUTTER_STATUS_DEV_RESULT=PASS\n'
