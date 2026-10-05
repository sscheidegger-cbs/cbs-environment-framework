#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

source "$SCRIPT_DIR/common.sh"

ANDROID_DEVICE="${CBS_FLUTTER_ANDROID_DEVICE:-medium_phone}"

cbs_flutter_load_environment

"$CBS_BIN" runtime android stop "$ANDROID_DEVICE"

printf 'CBS_FLUTTER_STOP_DEV_RESULT=PASS\n'
