#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/toolchain/contract.sh"
source "$ROOT/cbs/toolchain/provider_contract.sh"

cbs_toolchain_manifest_validate() {
    local manifest="${1:-}"

    [[ -n "$manifest" ]] ||
        return "$CBS_RC_TOOLCHAIN_USAGE"

    [[ -f "$manifest" ]] ||
        return "$CBS_RC_TOOLCHAIN_INVALID"

    local toolchain_id
    local toolchain_version
    local toolchain_provider

    toolchain_id="$(
        (
            set -a
            source "$manifest"
            printf '%s\n' "${CBS_TOOLCHAIN_ID:-}"
        )
    )"

    toolchain_version="$(
        (
            set -a
            source "$manifest"
            printf '%s\n' "${CBS_TOOLCHAIN_VERSION:-}"
        )
    )"

    toolchain_provider="$(
        (
            set -a
            source "$manifest"
            printf '%s\n' "${CBS_TOOLCHAIN_PROVIDER:-}"
        )
    )"

    [[ -n "$toolchain_id" ]] ||
        return "$CBS_RC_TOOLCHAIN_INVALID"

    [[ -n "$toolchain_version" ]] ||
        return "$CBS_RC_TOOLCHAIN_INVALID"

    [[ -n "$toolchain_provider" ]] ||
        return "$CBS_RC_TOOLCHAIN_INVALID"

    return 0
}

cbs_toolchain_provider_path() {
    local provider="${1:-}"
    local provider_dir="${CBS_TOOLCHAIN_PROVIDER_DIR:-$ROOT/cbs/toolchain/providers}"

    printf '%s/%s.sh\n' "$provider_dir" "$provider"
}

cbs_toolchain_load_manifest() {
    local manifest="${1:-}"

    if [[ -z "$manifest" ]]; then
        echo "CBS_TOOLCHAIN_ERROR=MANIFEST_REQUIRED" >&2
        return "$CBS_RC_TOOLCHAIN_USAGE"
    fi

    if ! cbs_toolchain_manifest_validate "$manifest"; then
        echo "CBS_TOOLCHAIN_MANIFEST=$manifest"
        echo "CBS_TOOLCHAIN_ERROR=MANIFEST_INVALID" >&2
        return "$CBS_RC_TOOLCHAIN_INVALID"
    fi

    set -a
    source "$manifest"
    set +a
}

cbs_toolchain_require_provider() {
    local provider_path="${1:-}"

    if [[ ! -x "$provider_path" ]]; then
        echo "CBS_TOOLCHAIN_ID=$CBS_TOOLCHAIN_ID"
        echo "CBS_TOOLCHAIN_VERSION=$CBS_TOOLCHAIN_VERSION"
        echo "CBS_TOOLCHAIN_PROVIDER=$CBS_TOOLCHAIN_PROVIDER"
        echo "CBS_TOOLCHAIN_ERROR=UNKNOWN_PROVIDER" >&2
        return "$CBS_RC_TOOLCHAIN_UNKNOWN_PROVIDER"
    fi
}

cbs_toolchain_detect() {
    local provider_path="${1:-}"
    local toolchain_root="${2:-}"

    local detect_output
    local detect_rc

    set +e
    detect_output="$(
        "$provider_path" \
            "$CBS_TOOLCHAIN_PROVIDER_OPERATION_DETECT" \
            "$CBS_TOOLCHAIN_ID" \
            "$CBS_TOOLCHAIN_VERSION" \
            "$toolchain_root" \
            2>&1
    )"
    detect_rc=$?
    set -e

    if [[ "$detect_rc" -ne 0 ]]; then
        echo "$detect_output"
        echo "CBS_TOOLCHAIN_ERROR=PROVIDER_FAILURE" >&2
        return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
    fi

    local installation_state=""
    local resolved_path=""

    while IFS= read -r line
    do
        case "$line" in
            CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=*)
                installation_state="${line#CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=}"
                ;;
            CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=*)
                resolved_path="${line#CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=}"
                ;;
        esac
    done <<<"$detect_output"

    if ! cbs_toolchain_installation_state_is_valid "$installation_state"; then
        echo "CBS_TOOLCHAIN_ERROR=INVALID_PROVIDER_STATE" >&2
        return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
    fi

    printf 'CBS_TOOLCHAIN_DETECTED_INSTALLATION_STATE=%s\n' "$installation_state"
    printf 'CBS_TOOLCHAIN_DETECTED_RESOLVED_PATH=%s\n' "$resolved_path"
}

cbs_toolchain_decision_from_state() {
    local installation_state="${1:-}"

    case "$installation_state" in
        "$CBS_TOOLCHAIN_INSTALLATION_MISSING")
            printf '%s\n' "$CBS_TOOLCHAIN_DECISION_INSTALL"
            ;;
        "$CBS_TOOLCHAIN_INSTALLATION_PRESENT_COMPATIBLE")
            printf '%s\n' "$CBS_TOOLCHAIN_DECISION_REUSE"
            ;;
        "$CBS_TOOLCHAIN_INSTALLATION_PRESENT_INCOMPATIBLE")
            printf '%s\n' "$CBS_TOOLCHAIN_DECISION_RECONCILE"
            ;;
        "$CBS_TOOLCHAIN_INSTALLATION_INVALID"|\
        "$CBS_TOOLCHAIN_INSTALLATION_UNKNOWN")
            printf '%s\n' "$CBS_TOOLCHAIN_DECISION_BLOCK"
            ;;
        *)
            return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
            ;;
    esac
}

cbs_toolchain_verify() {
    local provider_path="${1:-}"
    local toolchain_root="${2:-}"

    local verify_output
    local verify_rc

    set +e
    verify_output="$(
        "$provider_path" \
            "$CBS_TOOLCHAIN_PROVIDER_OPERATION_VERIFY" \
            "$CBS_TOOLCHAIN_ID" \
            "$CBS_TOOLCHAIN_VERSION" \
            "$toolchain_root" \
            2>&1
    )"
    verify_rc=$?
    set -e

    if [[ "$verify_rc" -ne 0 ]]; then
        echo "$verify_output"
        echo "CBS_TOOLCHAIN_ERROR=VERIFY_FAILED" >&2
        return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
    fi

    local version_observed=""
    local verify_result=""

    while IFS= read -r line
    do
        case "$line" in
            CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=*)
                version_observed="${line#CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=}"
                ;;
            CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=*)
                verify_result="${line#CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=}"
                ;;
        esac
    done <<<"$verify_output"

    [[ "$verify_result" == "PASS" ]] || {
        echo "CBS_TOOLCHAIN_ERROR=VERIFY_FAILED" >&2
        return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
    }

    echo "CBS_TOOLCHAIN_VERSION_OBSERVED=$version_observed"
    echo "CBS_TOOLCHAIN_VERIFICATION_RESULT=PASS"
}

cbs_toolchain_resolve() {
    local manifest="${1:-}"

    cbs_toolchain_load_manifest "$manifest" || return $?

    local provider_path
    provider_path="$(cbs_toolchain_provider_path "$CBS_TOOLCHAIN_PROVIDER")"

    cbs_toolchain_require_provider "$provider_path" || return $?

    local toolchain_root="${CBS_TOOLCHAIN_ROOT:-$HOME/.cbs/toolchains}"

    local detect_output
    detect_output="$(cbs_toolchain_detect "$provider_path" "$toolchain_root")" ||
        return $?

    local installation_state=""
    local resolved_path=""

    while IFS= read -r line
    do
        case "$line" in
            CBS_TOOLCHAIN_DETECTED_INSTALLATION_STATE=*)
                installation_state="${line#CBS_TOOLCHAIN_DETECTED_INSTALLATION_STATE=}"
                ;;
            CBS_TOOLCHAIN_DETECTED_RESOLVED_PATH=*)
                resolved_path="${line#CBS_TOOLCHAIN_DETECTED_RESOLVED_PATH=}"
                ;;
        esac
    done <<<"$detect_output"

    local decision
    decision="$(cbs_toolchain_decision_from_state "$installation_state")" ||
        return $?

    echo "CBS_TOOLCHAIN_MANIFEST=$manifest"
    echo "CBS_TOOLCHAIN_ID=$CBS_TOOLCHAIN_ID"
    echo "CBS_TOOLCHAIN_VERSION=$CBS_TOOLCHAIN_VERSION"
    echo "CBS_TOOLCHAIN_PROVIDER=$CBS_TOOLCHAIN_PROVIDER"
    echo "CBS_TOOLCHAIN_INSTALLATION_STATE=$installation_state"
    echo "CBS_TOOLCHAIN_RESOLVED_PATH=$resolved_path"
    echo "CBS_TOOLCHAIN_DECISION=$decision"
    echo "CBS_TOOLCHAIN_MUTATION=NONE"
    echo "CBS_TOOLCHAIN_RESOLUTION_RESULT=PASS"
}

cbs_toolchain_ensure() {
    local manifest="${1:-}"

    cbs_toolchain_load_manifest "$manifest" || return $?

    local provider_path
    provider_path="$(cbs_toolchain_provider_path "$CBS_TOOLCHAIN_PROVIDER")"

    cbs_toolchain_require_provider "$provider_path" || return $?

    local toolchain_root="${CBS_TOOLCHAIN_ROOT:-$HOME/.cbs/toolchains}"

    local detect_output
    detect_output="$(cbs_toolchain_detect "$provider_path" "$toolchain_root")" ||
        return $?

    local installation_state=""
    local resolved_path=""

    while IFS= read -r line
    do
        case "$line" in
            CBS_TOOLCHAIN_DETECTED_INSTALLATION_STATE=*)
                installation_state="${line#CBS_TOOLCHAIN_DETECTED_INSTALLATION_STATE=}"
                ;;
            CBS_TOOLCHAIN_DETECTED_RESOLVED_PATH=*)
                resolved_path="${line#CBS_TOOLCHAIN_DETECTED_RESOLVED_PATH=}"
                ;;
        esac
    done <<<"$detect_output"

    local decision
    decision="$(cbs_toolchain_decision_from_state "$installation_state")" ||
        return $?

    local action=""
    local mutation="NONE"

    case "$decision" in
        "$CBS_TOOLCHAIN_DECISION_REUSE")
            action="REUSE"
            ;;

        "$CBS_TOOLCHAIN_DECISION_INSTALL")
            action="INSTALL"

            local ensure_output
            local ensure_rc

            set +e
            ensure_output="$(
                "$provider_path" \
                    "$CBS_TOOLCHAIN_PROVIDER_OPERATION_ENSURE" \
                    "$CBS_TOOLCHAIN_ID" \
                    "$CBS_TOOLCHAIN_VERSION" \
                    "$toolchain_root" \
                    2>&1
            )"
            ensure_rc=$?
            set -e

            if [[ "$ensure_rc" -ne 0 ]]; then
                echo "$ensure_output"
                echo "CBS_TOOLCHAIN_ERROR=PROVIDER_FAILURE" >&2
                return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
            fi

            grep -Fq \
                'CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=PASS' \
                <<<"$ensure_output" || {
                    echo "CBS_TOOLCHAIN_ERROR=ENSURE_FAILED" >&2
                    return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
                }

            mutation="PERFORMED"
            ;;

        "$CBS_TOOLCHAIN_DECISION_RECONCILE")
            action="RECONCILE"
            echo "CBS_TOOLCHAIN_ERROR=RECONCILE_NOT_IMPLEMENTED" >&2
            return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
            ;;

        "$CBS_TOOLCHAIN_DECISION_BLOCK")
            action="BLOCK"
            echo "CBS_TOOLCHAIN_ERROR=BLOCKED" >&2
            return "$CBS_RC_TOOLCHAIN_PROVIDER_FAILURE"
            ;;
    esac

    local verify_output
    verify_output="$(cbs_toolchain_verify "$provider_path" "$toolchain_root")" ||
        return $?

    echo "CBS_TOOLCHAIN_MANIFEST=$manifest"
    echo "CBS_TOOLCHAIN_ID=$CBS_TOOLCHAIN_ID"
    echo "CBS_TOOLCHAIN_VERSION=$CBS_TOOLCHAIN_VERSION"
    echo "CBS_TOOLCHAIN_PROVIDER=$CBS_TOOLCHAIN_PROVIDER"
    echo "CBS_TOOLCHAIN_RESOLVED_PATH=$resolved_path"
    echo "CBS_TOOLCHAIN_ACTION=$action"
    echo "CBS_TOOLCHAIN_MUTATION=$mutation"
    echo "$verify_output"
    echo "CBS_TOOLCHAIN_ENSURE_RESULT=PASS"
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        resolve)
            cbs_toolchain_resolve "${1:-}"
            ;;
        ensure)
            cbs_toolchain_ensure "${1:-}"
            ;;
        "")
            echo "CBS_TOOLCHAIN_ERROR=COMMAND_REQUIRED" >&2
            return "$CBS_RC_TOOLCHAIN_USAGE"
            ;;
        *)
            echo "CBS_TOOLCHAIN_ERROR=UNKNOWN_COMMAND" >&2
            echo "CBS_TOOLCHAIN_COMMAND=$command" >&2
            return "$CBS_RC_TOOLCHAIN_USAGE"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
