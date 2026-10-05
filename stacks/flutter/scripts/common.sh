#!/usr/bin/env bash

set -Eeuo pipefail

CBS_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../../.." &&
    pwd
)"

CBS_BIN="$CBS_ROOT/bin/cbs"
CBS_STACK_MANIFEST="$CBS_ROOT/stacks/flutter/stack.env"

cbs_flutter_info() {
    printf '[INFO] %s\n' "$*"
}

cbs_flutter_ok() {
    printf '[OK] %s\n' "$*"
}

cbs_flutter_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

cbs_flutter_require_file() {
    local path="${1:-}"

    if [[ ! -f "$path" ]]; then
        cbs_flutter_error "Required file missing: $path"
        return 1
    fi
}

cbs_flutter_require_executable() {
    local path="${1:-}"

    if [[ ! -x "$path" ]]; then
        cbs_flutter_error "Required executable missing: $path"
        return 1
    fi
}

cbs_flutter_load_environment() {
    cbs_flutter_require_executable "$CBS_BIN"
    cbs_flutter_require_file "$CBS_STACK_MANIFEST"

    local environment_output=""
    local environment_rc=0

    set +e
    environment_output="$(
        "$CBS_BIN" \
            stack environment \
            "$CBS_STACK_MANIFEST"
    )"
    environment_rc=$?
    set -e

    if [[ "$environment_rc" -ne 0 ]]; then
        cbs_flutter_error "Unable to resolve Flutter Stack environment"
        return "$environment_rc"
    fi

    eval "$environment_output"

    if [[ "${CBS_STACK_ENVIRONMENT_STATE:-}" != "READY" ]]; then
        cbs_flutter_error "Flutter Stack environment is not READY"
        return 1
    fi

    command -v flutter >/dev/null 2>&1 || {
        cbs_flutter_error "Flutter unavailable after CBS resolution"
        return 1
    }

    command -v dart >/dev/null 2>&1 || {
        cbs_flutter_error "Dart unavailable after CBS resolution"
        return 1
    }

    command -v adb >/dev/null 2>&1 || {
        cbs_flutter_error "ADB unavailable after CBS resolution"
        return 1
    }

    command -v emulator >/dev/null 2>&1 || {
        cbs_flutter_error "Android emulator unavailable after CBS resolution"
        return 1
    }

    cbs_flutter_ok "Flutter Stack environment loaded"
}

cbs_flutter_check_kvm_access() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        return 0
    fi

    if [[ ! -e /dev/kvm ]]; then
        cbs_flutter_error "/dev/kvm missing"
        return 1
    fi

    if ! id -nG | tr ' ' '\n' | grep -Fxq kvm; then
        cbs_flutter_error "Current session is not in kvm group"
        return 1
    fi

    if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        cbs_flutter_error "Insufficient access to /dev/kvm"
        return 1
    fi

    cbs_flutter_ok "KVM access available"
}

cbs_flutter_kvm_session_state() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        return 0
    fi

    if [[ ! -e /dev/kvm ]]; then
        cbs_flutter_error "/dev/kvm missing"
        return 1
    fi

    if id -nG | tr ' ' '\n' | grep -Fxq kvm \
       && [[ -r /dev/kvm ]] \
       && [[ -w /dev/kvm ]]; then
        return 0
    fi

    if getent group kvm |
       awk -F: -v user="${USER:-}" '
           {
               n = split($4, members, ",")
               for (i = 1; i <= n; i++) {
                   if (members[i] == user) {
                       found = 1
                   }
               }
           }
           END {
               exit found ? 0 : 1
           }
       '
    then
        return 2
    fi

    cbs_flutter_error "User is not a member of kvm group"
    return 1
}

cbs_flutter_wait_android_ready() {
    local serial="${1:-}"
    local timeout_seconds="${2:-180}"
    local waited=0
    local boot_completed=""

    if [[ -z "$serial" ]]; then
        cbs_flutter_error "Android serial required"
        return 1
    fi

    adb -s "$serial" wait-for-device

    while (( waited < timeout_seconds )); do
        boot_completed="$(
            adb -s "$serial"                 shell getprop sys.boot_completed                 2>/dev/null |
                tr -d '\r'
        )"

        if [[ "$boot_completed" == "1" ]]; then
            cbs_flutter_ok "Android runtime ready: $serial"
            return 0
        fi

        sleep 2
        waited=$((waited + 2))
    done

    cbs_flutter_error "Timeout waiting for Android boot: $serial"
    return 1
}

cbs_flutter_android_serial_for_avd() {
    local avd_name="${1:-}"
    local serial=""
    local observed_name=""

    while IFS= read -r serial
    do
        [[ -n "$serial" ]] || continue

        observed_name="$(
            adb -s "$serial" emu avd name 2>/dev/null |
                head -n 1 |
                tr -d '\r'
        )"

        if [[ "$observed_name" == "$avd_name" ]]; then
            printf '%s\n' "$serial"
            return 0
        fi
    done < <(
        adb devices |
            awk '$2 == "device" && $1 ~ /^emulator-/ {print $1}'
    )

    return 1
}
