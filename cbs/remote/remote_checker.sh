#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/remote/remote_verifier.sh"

cbs_remote_check() {
    local manifest="${1:-}"

    cbs_remote_print_header "check" "$manifest"

    if [[ "$#" -ne 1 || -z "$manifest" ]]; then
        echo "CBS_REMOTE_USAGE=cbs remote check <manifest>" >&2
        cbs_remote_emit_result \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_USAGE"
        return "$CBS_RC_REMOTE_USAGE"
    fi

    if ! cbs_remote_manifest_load "$manifest"; then
        cbs_remote_emit_result \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_MANIFEST_INVALID"
        return "$CBS_RC_REMOTE_MANIFEST_INVALID"
    fi

    cbs_remote_print_manifest_identity

    if ! cbs_remote_ssh_is_available; then
        cbs_remote_emit_result \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_LOCAL_SSH_UNAVAILABLE"
        return "$CBS_RC_REMOTE_LOCAL_SSH_UNAVAILABLE"
    fi

    if ! cbs_remote_verify; then
        cbs_remote_emit_result \
            "$CBS_REMOTE_OUTCOME_RESULT" \
            "$CBS_REMOTE_OUTCOME_REASON"
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    cbs_remote_emit_result "$CBS_REMOTE_RESULT_PASS"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_remote_check "$@"
fi
