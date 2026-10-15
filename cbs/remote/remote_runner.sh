#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/remote/remote_verifier.sh"

cbs_remote_run() {
    local manifest="${1:-}"
    local action="${2:-}"
    local action_display
    local command
    local rc=0
    local -a words=()

    cbs_remote_print_header "run" "$manifest"

    if [[ "$#" -ne 2 || -z "$manifest" || -z "$action" ]]; then
        echo "CBS_REMOTE_USAGE=cbs remote run <manifest> <action>" >&2
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

    # Only names matching the action-name contract are ever echoed back.
    if [[ "$action" =~ $CBS_REMOTE_PATTERN_ACTION_NAME ]]; then
        action_display="$action"
    else
        action_display="INVALID"
    fi

    printf 'CBS_REMOTE_ACTION=%s\n' "$action_display"

    # The allow-list is enforced before any network access.
    if [[ "$action_display" == "INVALID" ]] ||
        ! cbs_remote_manifest_action_is_allowed "$action"
    then
        cbs_remote_emit_result \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_ACTION_NOT_ALLOWED"
        return "$CBS_RC_REMOTE_ACTION_NOT_ALLOWED"
    fi

    command="${CBS_REMOTE_RESOLVED[ACTION_$action]}"

    printf 'CBS_REMOTE_ACTION_COMMAND=cbs %s\n' "$command"

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

    IFS=' ' read -r -a words <<<"$command"

    # The launcher revalidates the repository in the session that executes the
    # action, immediately before exec. The action is announced
    # (CBS_REMOTE_ACTION_EXECUTION=START) only once the launcher reported a
    # passing verdict.
    if ! cbs_remote_ssh_stream_launch \
        "$(cbs_remote_launch_command \
            "$CBS_REMOTE_EXPECTED_COMMIT_RESOLVED" "${words[@]}")"
    then
        cbs_remote_emit_result \
            "$CBS_REMOTE_RESULT_FAIL" \
            "$CBS_REMOTE_REASON_PROBE_FAILED"
        return "$CBS_RC_REMOTE_PROBE_FAILED"
    fi

    rc="$CBS_REMOTE_SSH_RC"

    case "$CBS_REMOTE_LAUNCH_PREFLIGHT" in
        "$CBS_REMOTE_LAUNCH_PREFLIGHT_REFUSED")
            # The entrypoint was not started; nothing was repaired.
            cbs_remote_launch_refusal_outcome "$CBS_REMOTE_LAUNCH_REASON"
            cbs_remote_emit_result \
                "$CBS_REMOTE_OUTCOME_RESULT" \
                "$CBS_REMOTE_OUTCOME_REASON"
            return "$CBS_REMOTE_OUTCOME_RC"
            ;;
        "$CBS_REMOTE_LAUNCH_PREFLIGHT_PASS")
            ;;
        *)
            cbs_remote_launch_state_print
            printf 'CBS_REMOTE_ACTION_RC=%s\n' "$rc"

            if [[ "$rc" -eq "$CBS_RC_REMOTE_TRANSPORT_FAILURE" ]]; then
                # No verdict was received: there is no proof that the action
                # started, nor that it did not.
                echo "CBS_REMOTE_DIAGNOSTIC=SSH_STATUS_255_NO_LAUNCHER_VERDICT"
                cbs_remote_emit_result \
                    "$CBS_REMOTE_RESULT_FAIL" \
                    "$CBS_REMOTE_REASON_TRANSPORT_FAILURE"
                return "$rc"
            fi

            cbs_remote_emit_result \
                "$CBS_REMOTE_RESULT_FAIL" \
                "$CBS_REMOTE_REASON_LAUNCH_NOT_CONFIRMED"
            return "$CBS_RC_REMOTE_PROBE_FAILED"
            ;;
    esac

    printf 'CBS_REMOTE_ACTION_RC=%s\n' "$rc"

    if [[ "$rc" -eq 0 ]]; then
        cbs_remote_emit_result "$CBS_REMOTE_RESULT_PASS"
        return 0
    fi

    # The remote return code is preserved. 255 is also the ssh status for its
    # own failures, but an action may return 255 too: when the action did
    # start, the origin of a 255 cannot be determined, and no more than that
    # is claimed.
    if [[ "$rc" -eq "$CBS_RC_REMOTE_TRANSPORT_FAILURE" ]]; then
        echo "CBS_REMOTE_DIAGNOSTIC=SSH_STATUS_255_ORIGIN_UNDETERMINED"
        cbs_remote_emit_result \
            "$CBS_REMOTE_RESULT_FAIL" \
            "$CBS_REMOTE_REASON_TRANSPORT_FAILURE"
    else
        cbs_remote_emit_result \
            "$CBS_REMOTE_RESULT_FAIL" \
            "$CBS_REMOTE_REASON_REMOTE_ACTION_FAILED"
    fi

    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_remote_run "$@"
fi
