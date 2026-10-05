#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

source "$ROOT/cbs/stack/contract.sh"
source "$ROOT/cbs/stack/stack_resolver.sh"
source "$ROOT/cbs/toolchain/toolchain_manager.sh"

cbs_stack_environment_shell_export() {
    local name="${1:-}"
    local value="${2:-}"
    local escaped=""

    printf -v escaped '%q' "$value"
    printf 'export %s=%s\n' "$name" "$escaped"
}

cbs_stack_environment_manifest_value() {
    local resource_id="${1:-}"
    local field="${2:-}"
    local variable="CBS_STACK_MANAGED_TOOLCHAIN_${resource_id}_${field}"

    printf '%s\n' "${!variable:-}"
}

cbs_stack_environment_resolve_toolchain() {
    local resource_id="${1:-}"
    local version="${2:-}"
    local provider="${3:-}"
    local toolchain_id="${4:-}"

    local toolchain_manifest=""
    toolchain_manifest="$(mktemp)"

    cat > "$toolchain_manifest" <<MANIFEST
CBS_TOOLCHAIN_ID=$toolchain_id
CBS_TOOLCHAIN_VERSION=$version
CBS_TOOLCHAIN_PROVIDER=$provider
MANIFEST

    local resolve_output=""
    local resolve_rc=0

    set +e
    resolve_output="$(
        cbs_toolchain_resolve "$toolchain_manifest" 2>&1
    )"
    resolve_rc=$?
    set -e

    rm -f "$toolchain_manifest"

    if [[ "$resolve_rc" -ne 0 ]]; then
        printf 'CBS_STACK_ENVIRONMENT_ERROR=TOOLCHAIN_RESOLUTION_FAILED\n' >&2
        printf 'CBS_STACK_MANAGED_TOOLCHAIN_ID=%s\n' "$resource_id" >&2
        printf '%s\n' "$resolve_output" >&2
        return "$resolve_rc"
    fi

    local installation_state=""
    local resolved_path=""
    local decision=""

    while IFS= read -r line
    do
        case "$line" in
            CBS_TOOLCHAIN_INSTALLATION_STATE=*)
                installation_state="${line#CBS_TOOLCHAIN_INSTALLATION_STATE=}"
                ;;
            CBS_TOOLCHAIN_RESOLVED_PATH=*)
                resolved_path="${line#CBS_TOOLCHAIN_RESOLVED_PATH=}"
                ;;
            CBS_TOOLCHAIN_DECISION=*)
                decision="${line#CBS_TOOLCHAIN_DECISION=}"
                ;;
        esac
    done <<<"$resolve_output"

    if [[ -z "$installation_state" ||
          -z "$resolved_path" ||
          -z "$decision" ]]; then
        printf 'CBS_STACK_ENVIRONMENT_ERROR=TOOLCHAIN_RESOLUTION_INCOMPLETE\n' >&2
        printf 'CBS_STACK_MANAGED_TOOLCHAIN_ID=%s\n' "$resource_id" >&2
        return "$CBS_RC_STACK_INVALID"
    fi

    printf '%s|%s|%s\n' \
        "$installation_state" \
        "$resolved_path" \
        "$decision"
}

cbs_stack_environment_java_home() {
    if [[ -n "${JAVA_HOME:-}" &&
          -x "${JAVA_HOME}/bin/java" ]]; then
        printf '%s\n' "$JAVA_HOME"
        return 0
    fi

    if [[ "$(uname -s)" == "Darwin" &&
          -x /usr/libexec/java_home ]]; then
        /usr/libexec/java_home 2>/dev/null || true
        return 0
    fi

    local java_path=""
    java_path="$(command -v java 2>/dev/null || true)"

    [[ -n "$java_path" ]] || return 0

    if command -v readlink >/dev/null 2>&1; then
        java_path="$(
            readlink -f "$java_path" 2>/dev/null ||
            printf '%s' "$java_path"
        )"
    fi

    if [[ "$java_path" == */bin/java ]]; then
        dirname "$(dirname "$java_path")"
    fi
}

cbs_stack_environment() {
    local manifest="${1:-}"

    if [[ -z "$manifest" ]]; then
        printf 'CBS_STACK_ENVIRONMENT_ERROR=MANIFEST_REQUIRED\n' >&2
        return "$CBS_RC_STACK_USAGE"
    fi

    if ! cbs_stack_manifest_validate "$manifest"; then
        printf 'CBS_STACK_ENVIRONMENT_ERROR=MANIFEST_INVALID\n' >&2
        printf 'CBS_STACK_MANIFEST=%s\n' "$manifest" >&2
        return "$CBS_RC_STACK_INVALID"
    fi

    set -a
    source "$manifest"
    set +a

    local environment_path="$PATH"

    local resource_id=""
    local requirement=""
    local version=""
    local provider=""
    local toolchain_id=""
    local resolution=""
    local installation_state=""
    local resolved_path=""
    local decision=""

    local flutter_root=""
    local android_sdk_root=""
    local xcode_root=""
    local not_applicable_count=0

    for resource_id in ${CBS_STACK_MANAGED_TOOLCHAIN_IDS:-}
    do
        requirement="$(
            cbs_stack_environment_manifest_value \
                "$resource_id" \
                "REQUIREMENT"
        )"

        version="$(
            cbs_stack_environment_manifest_value \
                "$resource_id" \
                "VERSION"
        )"

        provider="$(
            cbs_stack_environment_manifest_value \
                "$resource_id" \
                "PROVIDER"
        )"

        toolchain_id="$(
            cbs_stack_environment_manifest_value \
                "$resource_id" \
                "ID"
        )"

        [[ "$requirement" == "DISABLED" ]] && continue

        if [[ -z "$toolchain_id" ]]; then
            toolchain_id="$(
                printf '%s' "$resource_id" |
                    tr '[:upper:]' '[:lower:]'
            )"
        fi

        if [[ -z "$requirement" ||
              -z "$version" ||
              -z "$provider" ]]; then
            printf 'CBS_STACK_ENVIRONMENT_ERROR=TOOLCHAIN_DECLARATION_INVALID\n' >&2
            printf 'CBS_STACK_MANAGED_TOOLCHAIN_ID=%s\n' "$resource_id" >&2
            return "$CBS_RC_STACK_INVALID"
        fi

        resolution="$(
            cbs_stack_environment_resolve_toolchain \
                "$resource_id" \
                "$version" \
                "$provider" \
                "$toolchain_id"
        )" || return $?

        IFS='|' read -r \
            installation_state \
            resolved_path \
            decision \
            <<<"$resolution"

        if [[ "$installation_state" == "NOT_APPLICABLE" ]]; then
            not_applicable_count=$((not_applicable_count + 1))
            continue
        fi

        if [[ "$requirement" == "REQUIRED" &&
              "$installation_state" != "PRESENT_COMPATIBLE" ]]; then
            printf 'CBS_STACK_ENVIRONMENT_ERROR=REQUIRED_TOOLCHAIN_NOT_READY\n' >&2
            printf 'CBS_STACK_MANAGED_TOOLCHAIN_ID=%s\n' "$resource_id" >&2
            printf 'CBS_STACK_MANAGED_TOOLCHAIN_STATE=%s\n' "$installation_state" >&2
            printf 'CBS_STACK_MANAGED_TOOLCHAIN_DECISION=%s\n' "$decision" >&2
            printf 'CBS_STACK_ENVIRONMENT_HINT=cbs stack toolchains ensure %s\n' \
                "$manifest" >&2
            return "$CBS_RC_STACK_INVALID"
        fi

        case "$resource_id" in
            FLUTTER)
                flutter_root="$resolved_path"
                environment_path="$flutter_root/bin:$environment_path"
                ;;

            ANDROID_SDK)
                android_sdk_root="$resolved_path"
                environment_path="$android_sdk_root/platform-tools:$android_sdk_root/emulator:$environment_path"
                ;;

            XCODE)
                xcode_root="$resolved_path"
                ;;
        esac
    done

    cbs_stack_environment_shell_export \
        "CBS_STACK_ENVIRONMENT_ID" \
        "$CBS_STACK_ID"

    cbs_stack_environment_shell_export \
        "CBS_STACK_ENVIRONMENT_VERSION" \
        "$CBS_STACK_VERSION"

    cbs_stack_environment_shell_export \
        "CBS_STACK_ENVIRONMENT_MANIFEST" \
        "$manifest"

    if [[ -n "$flutter_root" ]]; then
        cbs_stack_environment_shell_export \
            "CBS_FLUTTER_ROOT" \
            "$flutter_root"

        cbs_stack_environment_shell_export \
            "FLUTTER_ROOT" \
            "$flutter_root"
    fi

    if [[ -n "$android_sdk_root" ]]; then
        cbs_stack_environment_shell_export \
            "CBS_ANDROID_SDK_ROOT" \
            "$android_sdk_root"

        cbs_stack_environment_shell_export \
            "ANDROID_SDK_ROOT" \
            "$android_sdk_root"

        cbs_stack_environment_shell_export \
            "ANDROID_HOME" \
            "$android_sdk_root"
    fi

    if [[ -n "$xcode_root" ]]; then
        cbs_stack_environment_shell_export \
            "CBS_XCODE_DEVELOPER_DIR" \
            "$xcode_root"

        cbs_stack_environment_shell_export \
            "DEVELOPER_DIR" \
            "$xcode_root"
    fi

    local java_home=""
    java_home="$(cbs_stack_environment_java_home)"

    if [[ -n "$java_home" ]]; then
        cbs_stack_environment_shell_export \
            "JAVA_HOME" \
            "$java_home"
    fi

    cbs_stack_environment_shell_export \
        "PATH" \
        "$environment_path"

    cbs_stack_environment_shell_export \
        "CBS_STACK_ENVIRONMENT_NOT_APPLICABLE_COUNT" \
        "$not_applicable_count"

    cbs_stack_environment_shell_export \
        "CBS_STACK_ENVIRONMENT_STATE" \
        "READY"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_stack_environment "${1:-}"
fi
