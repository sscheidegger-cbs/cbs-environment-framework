#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

source "$SCRIPT_DIR/common.sh"

printf '%s\n' \
    "==========================================" \
    " CBS Flutter Stack - Development check" \
    "=========================================="

cbs_flutter_load_environment

command -v flutter >/dev/null
command -v dart >/dev/null
command -v adb >/dev/null
command -v emulator >/dev/null
command -v java >/dev/null

set +e
cbs_flutter_kvm_session_state
kvm_rc=$?
set -e

case "$kvm_rc" in
    0)
        cbs_flutter_ok "KVM session ready"
        ;;
    2)
        cbs_flutter_ok \
            "KVM available; start_dev will activate it automatically"
        ;;
    *)
        cbs_flutter_error "KVM unavailable"
        exit 1
        ;;
esac

printf 'CBS_FLUTTER_CHECK_DEV_RESULT=PASS\n'
