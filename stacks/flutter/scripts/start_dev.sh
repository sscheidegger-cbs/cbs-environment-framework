#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

source "$SCRIPT_DIR/common.sh"

ANDROID_DEVICE="${CBS_FLUTTER_ANDROID_DEVICE:-medium_phone}"

cbs_flutter_load_environment

set +e
cbs_flutter_kvm_session_state
kvm_rc=$?
set -e

if [[ "$kvm_rc" -eq 2 ]]; then
    cbs_flutter_info "Activating kvm group for Flutter development runtime"

    command_string="$(
        printf '%q ' "$0" "$@"
    )"

    exec sg kvm -c \
        "exec bash -lc $(printf '%q' "$command_string")"
fi

if [[ "$kvm_rc" -ne 0 ]]; then
    exit "$kvm_rc"
fi

cbs_flutter_check_kvm_access

printf '%s\n' '--- CBS FLUTTER ANDROID RUNTIME ---'

"$CBS_BIN" runtime android ensure "$ANDROID_DEVICE"

ANDROID_SERIAL=""

set +e
ANDROID_SERIAL="$(
    cbs_flutter_android_serial_for_avd "$ANDROID_DEVICE"
)"
serial_rc=$?
set -e

if [[ "$serial_rc" -ne 0 || -z "$ANDROID_SERIAL" ]]; then
    "$CBS_BIN" runtime android start "$ANDROID_DEVICE"

    ANDROID_SERIAL="$(
        cbs_flutter_android_serial_for_avd "$ANDROID_DEVICE"
    )"
else
    cbs_flutter_info \
        "Android runtime already available: $ANDROID_SERIAL"
fi

if [[ -z "$ANDROID_SERIAL" ]]; then
    cbs_flutter_error \
        "Unable to resolve Android serial for AVD: $ANDROID_DEVICE"
    exit 1
fi

cbs_flutter_wait_android_ready "$ANDROID_SERIAL" 180

export CBS_FLUTTER_ANDROID_DEVICE="$ANDROID_DEVICE"
export CBS_FLUTTER_ANDROID_SERIAL="$ANDROID_SERIAL"

printf 'CBS_FLUTTER_ANDROID_DEVICE=%s\n' \
    "$CBS_FLUTTER_ANDROID_DEVICE"

printf 'CBS_FLUTTER_ANDROID_SERIAL=%s\n' \
    "$CBS_FLUTTER_ANDROID_SERIAL"

printf 'CBS_FLUTTER_START_DEV_RESULT=PASS\n'

if [[ "${1:-}" == "--" ]]; then
    shift
fi

if [[ "$#" -gt 0 ]]; then
    exec "$@"
fi
