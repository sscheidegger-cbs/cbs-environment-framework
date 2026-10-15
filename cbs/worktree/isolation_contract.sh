#!/usr/bin/env bash

# D04b-C.1 - Git isolation contract (detached worktree at an explicit commit).
#
# This file only declares constants and pure validators.
# It does not alter the B17b-D worktree contract (cbs/worktree/contract.sh).

if [[ "${CBS_ISOLATION_CONTRACT_LOADED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

CBS_ISOLATION_CONTRACT_LOADED=1
readonly CBS_ISOLATION_CONTRACT_LOADED

CBS_ISOLATION_CONTRACT_VERSION=1
readonly CBS_ISOLATION_CONTRACT_VERSION

# Structured results. NOT_RUN means "not observed / not executed".
# SKIPPED is deliberately not a runtime result: it only exists in test runners.
readonly CBS_ISOLATION_RESULT_PASS="PASS"
readonly CBS_ISOLATION_RESULT_FAIL="FAIL"
readonly CBS_ISOLATION_RESULT_BLOCKED="BLOCKED"
readonly CBS_ISOLATION_NOT_RUN="NOT_RUN"

# Return codes. 60..64 are inherited from the worktree contract and reused:
#   61 CBS_RC_WORKTREE_PATH_CONFLICT       (root, path, symlink, collision)
#   62 CBS_RC_WORKTREE_INVALID_REPOSITORY  (source repository)
#   64 CBS_RC_WORKTREE_USAGE
readonly CBS_RC_ISOLATION_COMMIT_INVALID=65
readonly CBS_RC_ISOLATION_ORIGIN_MISMATCH=66
readonly CBS_RC_ISOLATION_OWNERSHIP=67
readonly CBS_RC_ISOLATION_STATE_CONFLICT=68
readonly CBS_RC_ISOLATION_FAILED=69

# Explicit authorization of an isolation root: the operator must have created
# this marker file (regular file, not a symlink) inside the dedicated root.
readonly CBS_ISOLATION_ROOT_MARKER=".cbs-isolation-root"
readonly CBS_ISOLATION_ROOT_MARKER_CONTENT="CBS_ISOLATION_ROOT_V1"

# Ownership proofs live inside the authorized root, outside any worktree.
# The directory must belong to the current user and be accessible by nobody
# else (mode 700); proof files must belong to the current user, have a single
# link and not be writable by group or others.
readonly CBS_ISOLATION_PROOF_DIR=".cbs-isolation"

# Mutual exclusion of create and cleanup inside one authorized root: a
# directory created atomically with mkdir (portable: Linux and macOS Bash 3.2,
# no flock). A held lock is never stolen: a stale lock is removed by the
# operator.
readonly CBS_ISOLATION_LOCK_DIR=".cbs-isolation.lock"

cbs_isolation_result_is_valid() {
    case "${1:-}" in
        "$CBS_ISOLATION_RESULT_PASS"|"$CBS_ISOLATION_RESULT_FAIL"|"$CBS_ISOLATION_RESULT_BLOCKED"|"$CBS_ISOLATION_NOT_RUN")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Text accepted as data: non-empty, no control character (newline included).
cbs_isolation_valid_text() {
    local value="${1:-}"

    [[ -n "$value" ]] || return 1

    case "$value" in
        *[[:cntrl:]]*)
            return 1
            ;;
    esac

    return 0
}

# Qualification identifier: 1..64 chars, starts with an alphanumeric,
# then [A-Za-z0-9._-]. No slash, no leading dot, no ".lock" suffix.
cbs_isolation_id_valid() {
    local id="${1:-}"
    local pattern='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

    [[ "$id" =~ $pattern ]] || return 1

    case "$id" in
        *.lock)
            return 1
            ;;
    esac

    return 0
}

# Full object name: 40 hex (SHA-1) or 64 hex (SHA-256), lowercase only.
cbs_isolation_commit_format_valid() {
    local commit="${1:-}"
    local sha1_pattern='^[0-9a-f]{40}$'
    local sha256_pattern='^[0-9a-f]{64}$'

    if [[ "$commit" =~ $sha1_pattern ]]; then
        return 0
    fi

    if [[ "$commit" =~ $sha256_pattern ]]; then
        return 0
    fi

    return 1
}

# Remove credentials from URLs (scheme://user:secret@host/...).
cbs_isolation_redact() {
    printf '%s\n' "${1:-}" | sed -e 's#://[^/@]*@#://[REDACTED]@#'
}
