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
    " CBS Flutter Stack - Project setup" \
    "=========================================="

printf '%s\n' '--- MANAGED TOOLCHAINS ---'

"$CBS_BIN" \
    stack toolchains ensure \
    "$CBS_STACK_MANIFEST"

printf '%s\n' '--- STACK ENVIRONMENT ---'

cbs_flutter_load_environment

printf '%s\n' '--- ANDROID RUNTIME DEFINITION ---'

"$CBS_BIN" runtime android ensure "$ANDROID_DEVICE"

printf '%s\n' '--- TOOLCHAIN VERSIONS ---'

flutter --version
dart --version
java -version

printf 'CBS_FLUTTER_SETUP_PROJECT_RESULT=PASS\n'
