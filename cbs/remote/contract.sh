#!/usr/bin/env bash

# CBS Remote Contract
#
# Constants, validation helpers, Bash 3.2 compatible lookup and case helpers
# and structured-result helpers only. This file performs no SSH connection and no mutation.

if [[ "${CBS_REMOTE_CONTRACT_LOADED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

CBS_REMOTE_CONTRACT_LOADED=1
readonly CBS_REMOTE_CONTRACT_LOADED

CBS_REMOTE_CONTRACT_VERSION=1
readonly CBS_REMOTE_CONTRACT_VERSION

CBS_REMOTE_MANIFEST_VERSION=1
readonly CBS_REMOTE_MANIFEST_VERSION

# Structured results
readonly CBS_REMOTE_RESULT_PASS="PASS"
readonly CBS_REMOTE_RESULT_FAIL="FAIL"
readonly CBS_REMOTE_RESULT_BLOCKED="BLOCKED"

# Reasons (BLOCKED: nothing was executed remotely; FAIL: something ran or
# the probe itself malfunctioned)
readonly CBS_REMOTE_REASON_USAGE="USAGE"
readonly CBS_REMOTE_REASON_MANIFEST_INVALID="MANIFEST_INVALID"
readonly CBS_REMOTE_REASON_ACTION_NOT_ALLOWED="ACTION_NOT_ALLOWED"
readonly CBS_REMOTE_REASON_LOCAL_SSH_UNAVAILABLE="LOCAL_SSH_UNAVAILABLE"
readonly CBS_REMOTE_REASON_LOCAL_REFERENCE_UNAVAILABLE="LOCAL_REFERENCE_UNAVAILABLE"
readonly CBS_REMOTE_REASON_HOST_UNREACHABLE="HOST_UNREACHABLE"
readonly CBS_REMOTE_REASON_REMOTE_GIT_UNAVAILABLE="REMOTE_GIT_UNAVAILABLE"
readonly CBS_REMOTE_REASON_REPOSITORY_MISSING="REPOSITORY_MISSING"
readonly CBS_REMOTE_REASON_REPOSITORY_NOT_GIT="REPOSITORY_NOT_GIT"
readonly CBS_REMOTE_REASON_REPOSITORY_ORIGIN_MISMATCH="REPOSITORY_ORIGIN_MISMATCH"
readonly CBS_REMOTE_REASON_BRANCH_MISMATCH="BRANCH_MISMATCH"
readonly CBS_REMOTE_REASON_COMMIT_MISMATCH="COMMIT_MISMATCH"
readonly CBS_REMOTE_REASON_WORKTREE_DIRTY="WORKTREE_DIRTY"
readonly CBS_REMOTE_REASON_WORKTREE_UNKNOWN="WORKTREE_UNKNOWN"
readonly CBS_REMOTE_REASON_ENTRYPOINT_UNAVAILABLE="ENTRYPOINT_UNAVAILABLE"
readonly CBS_REMOTE_REASON_PROBE_FAILED="PROBE_FAILED"
readonly CBS_REMOTE_REASON_REMOTE_ACTION_FAILED="REMOTE_ACTION_FAILED"
readonly CBS_REMOTE_REASON_TRANSPORT_FAILURE="TRANSPORT_FAILURE"
readonly CBS_REMOTE_REASON_LAUNCH_NOT_CONFIRMED="LAUNCH_NOT_CONFIRMED"

# Outcome of the revalidation performed by the launcher, in the same SSH
# session and immediately before exec.
#   PASS          the launcher revalidated the repository and then ran exec
#   REFUSED       the launcher refused: the entrypoint was never started
#   NOT_REPORTED  no launcher verdict was received (nothing proves either way)
readonly CBS_REMOTE_LAUNCH_PREFLIGHT_PASS="PASS"
readonly CBS_REMOTE_LAUNCH_PREFLIGHT_REFUSED="REFUSED"
readonly CBS_REMOTE_LAUNCH_PREFLIGHT_NOT_REPORTED="NOT_REPORTED"

# Repository states reuse the Workspace / Repository contract vocabulary
# (READY, MISSING, NOT_GIT, REMOTE_MISMATCH) and return codes 50-52.
# Worktree states reuse CLEAN, DIRTY, UNKNOWN.

# Commit relations between the observed remote HEAD and the expected commit
readonly CBS_REMOTE_COMMIT_EQUAL="EQUAL"
readonly CBS_REMOTE_COMMIT_AHEAD="AHEAD"
readonly CBS_REMOTE_COMMIT_BEHIND="BEHIND"
readonly CBS_REMOTE_COMMIT_DIVERGED="DIVERGED"
readonly CBS_REMOTE_COMMIT_UNKNOWN_OBJECT="UNKNOWN_OBJECT"

# Return codes.
#
# PASS                          0
# usage                         64 (same value as the other CBS components)
# repository identity           50, 51, 52 (CBS_REPOSITORY_RC_*)
# other BLOCKED reasons         100-109
# PROBE_FAILED (FAIL)           110
# LAUNCH_NOT_CONFIRMED (FAIL)   110 (same code as PROBE_FAILED)
# REMOTE_ACTION_FAILED (FAIL)   the exact return code of the remote action
# TRANSPORT_FAILURE (FAIL)      255 (ssh exit status; its origin is not proven)
readonly CBS_RC_REMOTE_USAGE=64
readonly CBS_RC_REMOTE_MANIFEST_INVALID=100
readonly CBS_RC_REMOTE_LOCAL_SSH_UNAVAILABLE=101
readonly CBS_RC_REMOTE_HOST_UNREACHABLE=102
readonly CBS_RC_REMOTE_REMOTE_GIT_UNAVAILABLE=103
readonly CBS_RC_REMOTE_BRANCH_MISMATCH=104
readonly CBS_RC_REMOTE_COMMIT_MISMATCH=105
readonly CBS_RC_REMOTE_WORKTREE_DIRTY=106
readonly CBS_RC_REMOTE_ACTION_NOT_ALLOWED=107
readonly CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE=108
readonly CBS_RC_REMOTE_LOCAL_REFERENCE_UNAVAILABLE=109
readonly CBS_RC_REMOTE_PROBE_FAILED=110
readonly CBS_RC_REMOTE_TRANSPORT_FAILURE=255

# Validation patterns (extended regular expressions)
readonly CBS_REMOTE_PATTERN_ID='^[a-z0-9][a-z0-9._-]{0,63}$'
readonly CBS_REMOTE_PATTERN_DESTINATION='^[A-Za-z0-9_][A-Za-z0-9._@-]{0,254}$'
readonly CBS_REMOTE_PATTERN_ACTION_NAME='^[a-z][a-z0-9_]{0,39}$'
readonly CBS_REMOTE_PATTERN_BRANCH='^[A-Za-z0-9][A-Za-z0-9._/-]{0,254}$'
readonly CBS_REMOTE_PATTERN_COMMIT='^([0-9a-f]{40}|[0-9a-f]{64})$'
# The origin length bound (1024) is checked separately from the character
# set: a repetition count above 255 is not accepted by the BSD regular
# expression library of macOS (RE_DUP_MAX).
readonly CBS_REMOTE_PATTERN_ORIGIN='^[A-Za-z0-9][A-Za-z0-9._~:/@+%-]*$'
readonly CBS_REMOTE_ORIGIN_MAX_LENGTH=1024
readonly CBS_REMOTE_PATTERN_PATH='^[A-Za-z0-9._/+@ -]+$'
readonly CBS_REMOTE_PATTERN_COMMAND_WORD='^[A-Za-z0-9._/+@:=%,-]+$'
readonly CBS_REMOTE_PATTERN_PATH_LIST='^/[A-Za-z0-9._/+@-]*(:/[A-Za-z0-9._/+@-]*)*$'
readonly CBS_REMOTE_PATTERN_UINT='^[0-9]{1,5}$'

readonly CBS_REMOTE_EXPECTED_COMMIT_LOCAL_HEAD="LOCAL_HEAD"
readonly CBS_REMOTE_DEFAULT_ENTRYPOINT="bin/cbs"
readonly CBS_REMOTE_DEFAULT_CONNECT_TIMEOUT=10

cbs_remote_result_is_valid() {
    case "${1:-}" in
        "$CBS_REMOTE_RESULT_PASS"|\
        "$CBS_REMOTE_RESULT_FAIL"|\
        "$CBS_REMOTE_RESULT_BLOCKED")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_remote_commit_relation_is_valid() {
    case "${1:-}" in
        "$CBS_REMOTE_COMMIT_EQUAL"|\
        "$CBS_REMOTE_COMMIT_AHEAD"|\
        "$CBS_REMOTE_COMMIT_BEHIND"|\
        "$CBS_REMOTE_COMMIT_DIVERGED"|\
        "$CBS_REMOTE_COMMIT_UNKNOWN_OBJECT")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Explicit allow-list of the CBS commands that may be bound to a remote action.
#
# Every entry is an exact word prefix. An entry is listed only when the CBS
# code path it reaches was read and found not to create, modify, install,
# start, stop or delete anything (observation and resolution only):
#
#   version                  prints the VERSION file
#   status                   context file + git rev-parse / branch observation
#   workstation check        prerequisite and isolation observation
#   workspace check          path and git observation
#   worktree check           git worktree list / status observation
#   instance check           docker ps / network ls / volume ls observation
#   stack resolve            manifest resolution
#   stack prerequisites      toolchain detection only (mutation NONE)
#   stack environment        toolchain detection only, prints export lines
#   platform resolve         manifest resolution
#   runtime android list     "emulator list" only
#
# Deliberately not listed:
#   - any ensure, start, stop or install operation, in particular
#     "stack toolchains ensure", "platform start", "platform stop",
#     "runtime android ensure|start|stop", "workspace|repository|worktree|
#     instance ensure";
#   - "platform check", "platform status", "platform qualify": CBS only
#     dispatches them to a hook script owned by the platform repository, so
#     their effect cannot be established from CBS (for the Core Platform
#     binding, the check hook chain runs docker compose up and SQL DDL and the
#     status hook runs "uv run");
#   - "remote" (no recursion).
#
# Adding an entry is an explicit change to this list, together with a test.
#
# A plain assignment followed by readonly is global wherever this file is
# sourced and is understood by Bash 3.2 (the global flag of declare is not).
CBS_REMOTE_COMMAND_ALLOW_LIST=(
    "version"
    "status"
    "workstation check"
    "workspace check"
    "worktree check"
    "instance check"
    "stack resolve"
    "stack prerequisites"
    "stack environment"
    "platform resolve"
    "runtime android list"
)
readonly CBS_REMOTE_COMMAND_ALLOW_LIST

# Arguments: up to the first three words of an action command.
# Succeeds only when they begin with exactly one allow-list entry.
cbs_remote_command_prefix_is_allowed() {
    local first="${1:-}"
    local second="${2:-}"
    local third="${3:-}"
    local entry

    [[ -n "$first" ]] || return 1

    for entry in "${CBS_REMOTE_COMMAND_ALLOW_LIST[@]}"; do
        case "$entry" in
            *" "*" "*)
                [[ -n "$second" && -n "$third" &&
                    "$entry" == "$first $second $third" ]] && return 0
                ;;
            *" "*)
                [[ -n "$second" && "$entry" == "$first $second" ]] && return 0
                ;;
            *)
                [[ "$entry" == "$first" ]] && return 0
                ;;
        esac
    done

    return 1
}

# --- Portable helpers (Bash 3.2 and later) ----------------------------------
#
# Bash 3.2 has no associative array and no case conversion expansion. A keyed
# store is therefore an indexed array of "KEY=VALUE" entries that is only read
# through the functions below. A key is compared as a plain string: it is never
# used as a variable name, an array subscript or shell code. A key never
# contains "=".

# Arguments: KEY [ENTRY...]
# Succeeds when an entry carries the key.
cbs_remote_entries_has() {
    local wanted="$1"
    local entry

    shift

    for entry in "$@"; do
        if [[ "${entry%%=*}" == "$wanted" ]]; then
            return 0
        fi
    done

    return 1
}

# Arguments: KEY DEFAULT [ENTRY...]
# Prints the value of the first entry carrying the key, or DEFAULT when the key
# is absent or its value is empty. Always succeeds.
cbs_remote_entries_get() {
    local wanted="$1"
    local default="$2"
    local entry
    local value=""

    shift 2

    for entry in "$@"; do
        if [[ "${entry%%=*}" == "$wanted" ]]; then
            value="${entry#*=}"
            break
        fi
    done

    printf '%s' "${value:-$default}"
}

# Arguments: WORD [ITEM...]
# Succeeds when WORD is exactly one of the items.
cbs_remote_word_in_list() {
    local wanted="$1"
    local item

    shift

    for item in "$@"; do
        if [[ "$item" == "$wanted" ]]; then
            return 0
        fi
    done

    return 1
}

# ASCII case conversion, independent of the locale (replaces the Bash 4 upper
# and lower case parameter expansions). Pure Bash: no external command is
# needed, so the set of tools required by this component does not change.
# Arguments: FROM_ALPHABET TO_ALPHABET TEXT
# Each character of TEXT found in FROM_ALPHABET is replaced by the character of
# TO_ALPHABET at the same position; every other character is kept.
cbs_remote_ascii_convert() {
    local from="$1"
    local to="$2"
    local input="${3-}"
    local output=""
    local character
    local head
    local index

    for ((index = 0; index < ${#input}; index++)); do
        character="${input:index:1}"

        # The test is a literal comparison: when it succeeds, the character is
        # a letter of the alphabet and cannot act as a glob pattern below.
        if [[ "$from" == *"$character"* ]]; then
            head="${from%%$character*}"
            character="${to:${#head}:1}"
        fi

        output="$output$character"
    done

    printf '%s' "$output"
}

# Argument: the text.
cbs_remote_ascii_upper() {
    cbs_remote_ascii_convert \
        "abcdefghijklmnopqrstuvwxyz" "ABCDEFGHIJKLMNOPQRSTUVWXYZ" "${1-}"
}

cbs_remote_ascii_lower() {
    cbs_remote_ascii_convert \
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" "abcdefghijklmnopqrstuvwxyz" "${1-}"
}

# Emits the structured outcome. Arguments: RESULT REASON(optional) RC
# The RESULT line is always the last stdout line produced by the component
# itself, so callers can rely on it.
cbs_remote_emit_result() {
    local result="${1:-}"
    local reason="${2:-}"

    if [[ -n "$reason" ]]; then
        printf 'CBS_REMOTE_REASON=%s\n' "$reason"
        printf 'CBS_REMOTE_ERROR=%s\n' "$reason" >&2
    fi

    printf 'CBS_REMOTE_RESULT=%s\n' "$result"
}
