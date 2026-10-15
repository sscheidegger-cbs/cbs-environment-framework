#!/usr/bin/env bash

# CBS Remote verifier.
#
# Observes the remote repository through the fixed read-only probe and decides
# whether remote execution is allowed. It never fetches, pulls, checks out,
# resets or cleans anything: a repository that is not already on the expected
# branch and commit with a clean worktree is refused, not repaired.
#
# This probe is a first, early refusal. The launcher (see remote_transport.sh)
# repeats the same observations in the SSH session that executes the action,
# immediately before exec; that second verdict is the one that gates execution.
#
# Outcome variables set on every call:
#   CBS_REMOTE_OUTCOME_RESULT  PASS | FAIL | BLOCKED
#   CBS_REMOTE_OUTCOME_REASON  empty on success
#   CBS_REMOTE_OUTCOME_RC      return code to propagate
# The function itself returns 0 only when remote execution is allowed.

REMOTE_VERIFIER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REMOTE_VERIFIER_DIR/contract.sh"
source "$REMOTE_VERIFIER_DIR/remote_manifest.sh"
source "$REMOTE_VERIFIER_DIR/remote_transport.sh"
source "$REMOTE_VERIFIER_DIR/../workspace/repository_contract.sh"

CBS_REMOTE_OUTCOME_RESULT=""
CBS_REMOTE_OUTCOME_REASON=""
CBS_REMOTE_OUTCOME_RC=0
CBS_REMOTE_EXPECTED_COMMIT_RESOLVED=""

# Observations reported by the probe (Bash 3.2 has no associative array): an
# indexed array of "KEY=VALUE" entries, read only through the accessors below.
CBS_REMOTE_PROBE_ENTRIES=()

# Arguments: KEY [DEFAULT]. Prints the observed value, or DEFAULT (empty unless
# given) when the probe did not report the key or reported it empty.
cbs_remote_probe_get() {
    cbs_remote_entries_get "$1" "${2-}" \
        ${CBS_REMOTE_PROBE_ENTRIES[@]+"${CBS_REMOTE_PROBE_ENTRIES[@]}"}
}

cbs_remote_probe_has() {
    cbs_remote_entries_has "$1" \
        ${CBS_REMOTE_PROBE_ENTRIES[@]+"${CBS_REMOTE_PROBE_ENTRIES[@]}"}
}

cbs_remote_outcome() {
    CBS_REMOTE_OUTCOME_RESULT="$1"
    CBS_REMOTE_OUTCOME_REASON="$2"
    CBS_REMOTE_OUTCOME_RC="$3"

    return "$3"
}

# Removes credentials from URL-like values before they are displayed.
cbs_remote_redact_url() {
    local value="${1-}"

    if [[ "$value" =~ ^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@(.*)$ ]]; then
        printf '%s***@%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        printf '%s' "$value"
    fi
}

cbs_remote_probe_parse() {
    local line
    local key
    local value

    CBS_REMOTE_PROBE_ENTRIES=()

    while IFS= read -r line; do
        if [[ "$line" =~ ^CBS_REMOTE_PROBE_([A-Z_]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # The first occurrence of a key wins.
            if ! cbs_remote_probe_has "$key"; then
                CBS_REMOTE_PROBE_ENTRIES+=("$key=$value")
            fi
        fi
    done <<<"$CBS_REMOTE_SSH_STDOUT"
}

# Resolves the commit that the remote repository is expected to be on.
cbs_remote_resolve_expected_commit() {
    local declared="$(cbs_remote_cfg_get CBS_REMOTE_EXPECTED_COMMIT)"
    local local_repository
    local commit

    if [[ "$declared" != "$CBS_REMOTE_EXPECTED_COMMIT_LOCAL_HEAD" ]]; then
        CBS_REMOTE_EXPECTED_COMMIT_RESOLVED="$declared"
        return 0
    fi

    local_repository="$(cbs_remote_resolved_get LOCAL_REPOSITORY)"

    printf 'CBS_REMOTE_LOCAL_REPOSITORY=%s\n' "$local_repository"

    if ! command -v git >/dev/null 2>&1; then
        return 1
    fi

    commit="$(
        git -C "$local_repository" rev-parse --verify HEAD 2>/dev/null
    )" || return 1

    [[ "$commit" =~ $CBS_REMOTE_PATTERN_COMMIT ]] || return 1

    CBS_REMOTE_EXPECTED_COMMIT_RESOLVED="$commit"
}

cbs_remote_verify() {
    local expected_origin="$(cbs_remote_cfg_get CBS_REMOTE_REPOSITORY_ORIGIN)"
    local expected_branch="$(cbs_remote_cfg_get CBS_REMOTE_EXPECTED_BRANCH)"
    local repository_state
    local observed_branch
    local observed_head
    local observed_origin
    local relation
    local reason
    local rc

    CBS_REMOTE_OUTCOME_RESULT=""
    CBS_REMOTE_OUTCOME_REASON=""
    CBS_REMOTE_OUTCOME_RC=0

    if ! cbs_remote_resolve_expected_commit; then
        cbs_remote_outcome \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_LOCAL_REFERENCE_UNAVAILABLE" \
            "$CBS_RC_REMOTE_LOCAL_REFERENCE_UNAVAILABLE" || true
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    cbs_remote_ssh_prepare

    cbs_remote_ssh_capture \
        "$(cbs_remote_probe_command "$CBS_REMOTE_EXPECTED_COMMIT_RESOLVED")" ||
        {
            cbs_remote_outcome \
                "$CBS_REMOTE_RESULT_FAIL" \
                "$CBS_REMOTE_REASON_PROBE_FAILED" \
                "$CBS_RC_REMOTE_PROBE_FAILED" || true
            return "$CBS_REMOTE_OUTCOME_RC"
        }

    printf 'CBS_REMOTE_SSH_RC=%s\n' "$CBS_REMOTE_SSH_RC"

    # ssh exits with 255 for its own failures: unreachable host, refused or
    # failed authentication, unknown or changed host key, timeout.
    if [[ "$CBS_REMOTE_SSH_RC" -eq 255 ]]; then
        echo "CBS_REMOTE_CONNECTION=UNREACHABLE"
        cbs_remote_outcome \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_HOST_UNREACHABLE" \
            "$CBS_RC_REMOTE_HOST_UNREACHABLE" || true
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    cbs_remote_probe_parse

    if [[ "$CBS_REMOTE_SSH_RC" -ne 0 ]] ||
        [[ "$(cbs_remote_probe_get COMPLETE)" != "YES" ]]
    then
        echo "CBS_REMOTE_CONNECTION=OK"
        cbs_remote_outcome \
            "$CBS_REMOTE_RESULT_FAIL" \
            "$CBS_REMOTE_REASON_PROBE_FAILED" \
            "$CBS_RC_REMOTE_PROBE_FAILED" || true
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    echo "CBS_REMOTE_CONNECTION=OK"

    if [[ "$(cbs_remote_probe_get GIT)" != "AVAILABLE" ]]; then
        echo "CBS_REMOTE_REMOTE_GIT=$(cbs_remote_probe_get GIT UNKNOWN)"
        cbs_remote_outcome \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_REMOTE_GIT_UNAVAILABLE" \
            "$CBS_RC_REMOTE_REMOTE_GIT_UNAVAILABLE" || true
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    # --- Repository identity (Workspace / Repository contract vocabulary)
    case "$(cbs_remote_probe_get REPOSITORY)" in
        MISSING)
            repository_state="$CBS_REPOSITORY_MISSING"
            ;;
        NOT_GIT)
            repository_state="$CBS_REPOSITORY_NOT_GIT"
            ;;
        READY)
            observed_origin="$(cbs_remote_probe_get ORIGIN)"

            if [[ "$observed_origin" == "$expected_origin" ]]; then
                repository_state="$CBS_REPOSITORY_READY"
            else
                repository_state="$CBS_REPOSITORY_REMOTE_MISMATCH"
            fi
            ;;
        *)
            repository_state="$CBS_REPOSITORY_UNKNOWN"
            ;;
    esac

    printf 'CBS_REMOTE_REPOSITORY_STATE=%s\n' "$repository_state"
    printf 'CBS_REMOTE_REPOSITORY_EXPECTED_ORIGIN=%s\n' \
        "$(cbs_remote_redact_url "$expected_origin")"

    if [[ "$(cbs_remote_probe_get REPOSITORY)" == "READY" ]]; then
        printf 'CBS_REMOTE_REPOSITORY_OBSERVED_ORIGIN=%s\n' \
            "$(cbs_remote_redact_url "$(cbs_remote_probe_get ORIGIN)")"
    fi

    if [[ "$repository_state" != "$CBS_REPOSITORY_READY" ]]; then
        rc=0
        cbs_repository_rc_from_state "$repository_state" || rc=$?

        case "$repository_state" in
            "$CBS_REPOSITORY_MISSING")
                reason="$CBS_REMOTE_REASON_REPOSITORY_MISSING"
                ;;
            "$CBS_REPOSITORY_NOT_GIT")
                reason="$CBS_REMOTE_REASON_REPOSITORY_NOT_GIT"
                ;;
            "$CBS_REPOSITORY_REMOTE_MISMATCH")
                reason="$CBS_REMOTE_REASON_REPOSITORY_ORIGIN_MISMATCH"
                ;;
            *)
                reason="$CBS_REMOTE_REASON_PROBE_FAILED"
                rc="$CBS_RC_REMOTE_PROBE_FAILED"
                ;;
        esac

        if [[ "$reason" == "$CBS_REMOTE_REASON_PROBE_FAILED" ]]; then
            cbs_remote_outcome \
                "$CBS_REMOTE_RESULT_FAIL" "$reason" "$rc" || true
        else
            cbs_remote_outcome \
                "$CBS_REMOTE_RESULT_BLOCKED" "$reason" "$rc" || true
        fi

        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    # --- Branch
    observed_branch="$(cbs_remote_probe_get BRANCH)"

    printf 'CBS_REMOTE_EXPECTED_BRANCH=%s\n' "$expected_branch"
    printf 'CBS_REMOTE_OBSERVED_BRANCH=%s\n' "${observed_branch:-DETACHED}"

    # --- Commit
    observed_head="$(cbs_remote_probe_get HEAD)"

    if [[ -n "$observed_head" && ! "$observed_head" =~ $CBS_REMOTE_PATTERN_COMMIT ]]; then
        cbs_remote_outcome \
            "$CBS_REMOTE_RESULT_FAIL" \
            "$CBS_REMOTE_REASON_PROBE_FAILED" \
            "$CBS_RC_REMOTE_PROBE_FAILED" || true
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    if [[ "$observed_head" == "$CBS_REMOTE_EXPECTED_COMMIT_RESOLVED" ]]; then
        relation="$CBS_REMOTE_COMMIT_EQUAL"
    else
        relation="$(cbs_remote_probe_get COMMIT_RELATION)"

        if ! cbs_remote_commit_relation_is_valid "$relation" ||
            [[ "$relation" == "$CBS_REMOTE_COMMIT_EQUAL" ]]
        then
            cbs_remote_outcome \
                "$CBS_REMOTE_RESULT_FAIL" \
                "$CBS_REMOTE_REASON_PROBE_FAILED" \
                "$CBS_RC_REMOTE_PROBE_FAILED" || true
            return "$CBS_REMOTE_OUTCOME_RC"
        fi
    fi

    printf 'CBS_REMOTE_EXPECTED_COMMIT=%s\n' "$CBS_REMOTE_EXPECTED_COMMIT_RESOLVED"
    printf 'CBS_REMOTE_OBSERVED_COMMIT=%s\n' "${observed_head:-NONE}"
    printf 'CBS_REMOTE_COMMIT_RELATION=%s\n' "$relation"
    printf 'CBS_REMOTE_WORKTREE_STATE=%s\n' "$(cbs_remote_probe_get WORKTREE "$CBS_REPOSITORY_WORKTREE_UNKNOWN")"
    printf 'CBS_REMOTE_ENTRYPOINT_STATE=%s\n' "$(cbs_remote_probe_get ENTRYPOINT UNKNOWN)"

    if [[ "$observed_branch" != "$expected_branch" ]]; then
        cbs_remote_outcome \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_BRANCH_MISMATCH" \
            "$CBS_RC_REMOTE_BRANCH_MISMATCH" || true
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    if [[ "$relation" != "$CBS_REMOTE_COMMIT_EQUAL" ]]; then
        cbs_remote_outcome \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_COMMIT_MISMATCH" \
            "$CBS_RC_REMOTE_COMMIT_MISMATCH" || true
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    # --- Worktree (any tracked or untracked change blocks)
    case "$(cbs_remote_probe_get WORKTREE)" in
        "$CBS_REPOSITORY_WORKTREE_CLEAN")
            ;;
        "$CBS_REPOSITORY_WORKTREE_DIRTY")
            cbs_remote_outcome \
                "$CBS_REMOTE_RESULT_BLOCKED" \
                "$CBS_REMOTE_REASON_WORKTREE_DIRTY" \
                "$CBS_RC_REMOTE_WORKTREE_DIRTY" || true
            return "$CBS_REMOTE_OUTCOME_RC"
            ;;
        *)
            cbs_remote_outcome \
                "$CBS_REMOTE_RESULT_BLOCKED" \
                "$CBS_REMOTE_REASON_WORKTREE_UNKNOWN" \
                "$CBS_RC_REMOTE_WORKTREE_DIRTY" || true
            return "$CBS_REMOTE_OUTCOME_RC"
            ;;
    esac

    # --- CBS entrypoint
    if [[ "$(cbs_remote_probe_get ENTRYPOINT)" != "PRESENT" ]]; then
        cbs_remote_outcome \
            "$CBS_REMOTE_RESULT_BLOCKED" \
            "$CBS_REMOTE_REASON_ENTRYPOINT_UNAVAILABLE" \
            "$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE" || true
        return "$CBS_REMOTE_OUTCOME_RC"
    fi

    cbs_remote_outcome "$CBS_REMOTE_RESULT_PASS" "" 0 || true
    return 0
}

# Translates a refusal reported by the launcher (same session, immediately
# before exec) into the outcome variables, with the reasons and return codes of
# the initial verification. A refusal always means that nothing was executed.
# A reason that the launcher is not documented to send is not trusted: it ends
# as PROBE_FAILED.
# Argument: the reason reported by the launcher.
cbs_remote_launch_refusal_outcome() {
    local launcher_reason="${1:-}"
    local reason
    local rc=0
    local state=""

    case "$launcher_reason" in
        REPOSITORY_MISSING)
            state="$CBS_REPOSITORY_MISSING"
            reason="$CBS_REMOTE_REASON_REPOSITORY_MISSING"
            ;;
        REPOSITORY_NOT_GIT)
            state="$CBS_REPOSITORY_NOT_GIT"
            reason="$CBS_REMOTE_REASON_REPOSITORY_NOT_GIT"
            ;;
        REPOSITORY_ORIGIN_MISMATCH)
            state="$CBS_REPOSITORY_REMOTE_MISMATCH"
            reason="$CBS_REMOTE_REASON_REPOSITORY_ORIGIN_MISMATCH"
            ;;
        REMOTE_GIT_UNAVAILABLE)
            reason="$CBS_REMOTE_REASON_REMOTE_GIT_UNAVAILABLE"
            rc="$CBS_RC_REMOTE_REMOTE_GIT_UNAVAILABLE"
            ;;
        BRANCH_MISMATCH)
            reason="$CBS_REMOTE_REASON_BRANCH_MISMATCH"
            rc="$CBS_RC_REMOTE_BRANCH_MISMATCH"
            ;;
        COMMIT_MISMATCH)
            reason="$CBS_REMOTE_REASON_COMMIT_MISMATCH"
            rc="$CBS_RC_REMOTE_COMMIT_MISMATCH"
            ;;
        WORKTREE_DIRTY)
            reason="$CBS_REMOTE_REASON_WORKTREE_DIRTY"
            rc="$CBS_RC_REMOTE_WORKTREE_DIRTY"
            ;;
        WORKTREE_UNKNOWN)
            reason="$CBS_REMOTE_REASON_WORKTREE_UNKNOWN"
            rc="$CBS_RC_REMOTE_WORKTREE_DIRTY"
            ;;
        ENTRYPOINT_UNAVAILABLE)
            reason="$CBS_REMOTE_REASON_ENTRYPOINT_UNAVAILABLE"
            rc="$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE"
            ;;
        *)
            cbs_remote_outcome \
                "$CBS_REMOTE_RESULT_FAIL" \
                "$CBS_REMOTE_REASON_PROBE_FAILED" \
                "$CBS_RC_REMOTE_PROBE_FAILED" || true
            return 0
            ;;
    esac

    if [[ -n "$state" ]]; then
        cbs_repository_rc_from_state "$state" || rc=$?
    fi

    cbs_remote_outcome \
        "$CBS_REMOTE_RESULT_BLOCKED" "$reason" "$rc" || true
}

# Prints the manifest identity header shared by check and run.
cbs_remote_print_header() {
    local operation="$1"
    local manifest="$2"

    printf 'CBS_REMOTE_CONTRACT_VERSION=%s\n' "$CBS_REMOTE_CONTRACT_VERSION"
    printf 'CBS_REMOTE_OPERATION=%s\n' "$operation"
    printf 'CBS_REMOTE_MANIFEST=%s\n' "$manifest"
}

cbs_remote_print_manifest_identity() {
    printf 'CBS_REMOTE_ID=%s\n' "$(cbs_remote_cfg_get CBS_REMOTE_ID)"
    printf 'CBS_REMOTE_DESTINATION=%s\n' "$(cbs_remote_cfg_get CBS_REMOTE_SSH_DESTINATION)"
    printf 'CBS_REMOTE_REPOSITORY_PATH=%s\n' "$(cbs_remote_cfg_get CBS_REMOTE_REPOSITORY_PATH)"
}
