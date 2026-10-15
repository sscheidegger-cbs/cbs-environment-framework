#!/usr/bin/env bash

# D04b-C.2b step 1 - Flutter/iOS qualification contract.
#
# Constants and pure validators only. This file:
#   - never runs Flutter, Dart, Xcode, simctl, Git or SSH;
#   - never creates, modifies or deletes anything;
#   - never sources or evaluates a manifest, and never evaluates a value;
#   - treats every input as data.
#
# The only filesystem access is read-only (cbs_flutter_qual_dir_is_canonical).
# The only file sourced is the Git isolation contract of this repository, at a
# fixed path derived from this file's own location.
#
# Compatible with Bash 3.2 (macOS) and later. No associative array, no case
# conversion expansion, no GNU-only option. Regular expressions are stored in
# variables and stay below the 255 repetition limit of the BSD library.

if [[ "${CBS_FLUTTER_QUAL_CONTRACT_LOADED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

# Reuse of the qualified isolation validators (identifier, commit, redaction).
if [[ "${CBS_ISOLATION_CONTRACT_LOADED:-0}" != "1" ]]; then
    _cbs_flutter_qual_isolation_contract="$(
        cd "$(dirname "${BASH_SOURCE[0]}")/../../worktree" 2>/dev/null &&
            pwd
    )/isolation_contract.sh"

    if [[ ! -f "$_cbs_flutter_qual_isolation_contract" ]]; then
        echo "CBS_FLUTTER_QUAL_ERROR=ISOLATION_CONTRACT_UNAVAILABLE" >&2
        unset _cbs_flutter_qual_isolation_contract
        return 1 2>/dev/null || exit 1
    fi

    # shellcheck source=/dev/null
    source "$_cbs_flutter_qual_isolation_contract"
    unset _cbs_flutter_qual_isolation_contract
fi

CBS_FLUTTER_QUAL_CONTRACT_LOADED=1
readonly CBS_FLUTTER_QUAL_CONTRACT_LOADED

CBS_FLUTTER_QUAL_CONTRACT_VERSION=1
readonly CBS_FLUTTER_QUAL_CONTRACT_VERSION

# --- Target, operations and actions ------------------------------------------

readonly CBS_FLUTTER_QUAL_TARGET_IOS_SIMULATOR="ios-simulator"

readonly CBS_FLUTTER_QUAL_OP_PREFLIGHT="PREFLIGHT"
readonly CBS_FLUTTER_QUAL_OP_ANALYZE="ANALYZE"
readonly CBS_FLUTTER_QUAL_OP_TEST="TEST"
readonly CBS_FLUTTER_QUAL_OP_BUILD_IOS="BUILD_IOS"
readonly CBS_FLUTTER_QUAL_OP_REPORT="REPORT"

# Canonical order. Space-separated, never used unquoted in a glob context.
readonly CBS_FLUTTER_QUAL_OPERATIONS="PREFLIGHT ANALYZE TEST BUILD_IOS REPORT"
readonly CBS_FLUTTER_QUAL_ACTIONS="preflight analyze test build_ios report"

# --- Results -------------------------------------------------------------------
#
#   PASS      executed, and the observed outcome is a success
#   FAIL      executed, and the observed outcome is a failure
#   BLOCKED   refused before execution: a precondition or a rule was not met
#   SKIPPED   explicitly not selected by the request
#   NOT_RUN   selected but never executed, hence never observed
#
# NOT_RUN and SKIPPED are never a success and never convert into PASS.

readonly CBS_FLUTTER_QUAL_RESULT_PASS="PASS"
readonly CBS_FLUTTER_QUAL_RESULT_FAIL="FAIL"
readonly CBS_FLUTTER_QUAL_RESULT_BLOCKED="BLOCKED"
readonly CBS_FLUTTER_QUAL_RESULT_SKIPPED="SKIPPED"
readonly CBS_FLUTTER_QUAL_RESULT_NOT_RUN="NOT_RUN"

# --- Reasons and return codes --------------------------------------------------
#
# Return codes are distinct from every code already used by CBS components
# (50-53, 60-72, 80-82, 90-94, 100-110, 255); 64 is the shared "usage" code.
# 120..137 are reserved for this contract.
#
#   BLOCKED  nothing was executed (usage, input, policy, environment)
#   FAIL     something ran or was attempted, and went wrong
#   NOT_RUN  selected, not executed (an earlier gate did not pass)
#   SKIPPED  not selected
#
# reason                      rc  result
readonly CBS_FLUTTER_QUAL_REASON_USAGE="USAGE"                                   # 64   BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_CONTRACT_VERSION_UNSUPPORTED="CONTRACT_VERSION_UNSUPPORTED" # 120 BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_INPUT_INVALID="INPUT_INVALID"                   # 121  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_ACTION_NOT_ALLOWED="ACTION_NOT_ALLOWED"         # 122  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_ARGUMENT_REFUSED="ARGUMENT_REFUSED"             # 123  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_PATH_NOT_ALLOWED="PATH_NOT_ALLOWED"             # 124  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_SECRET_REFUSED="SECRET_REFUSED"                 # 125  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_ISOLATION_REJECTED="ISOLATION_REJECTED"         # 126  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_TOOL_UNAVAILABLE="TOOL_UNAVAILABLE"             # 127  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_TOOLCHAIN_INCOMPATIBLE="TOOLCHAIN_INCOMPATIBLE" # 128  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_SIMULATOR_UNAVAILABLE="SIMULATOR_UNAVAILABLE"   # 129  BLOCKED
readonly CBS_FLUTTER_QUAL_REASON_COMMAND_FAILED="COMMAND_FAILED"                 # 130  FAIL
readonly CBS_FLUTTER_QUAL_REASON_TIMEOUT="TIMEOUT"                               # 131  FAIL
readonly CBS_FLUTTER_QUAL_REASON_NETWORK_FAILURE="NETWORK_FAILURE"               # 132  FAIL
readonly CBS_FLUTTER_QUAL_REASON_LOG_LIMIT_EXCEEDED="LOG_LIMIT_EXCEEDED"         # 133  FAIL
readonly CBS_FLUTTER_QUAL_REASON_EVIDENCE_FAILURE="EVIDENCE_FAILURE"             # 134  FAIL
readonly CBS_FLUTTER_QUAL_REASON_NOT_EXECUTED="NOT_EXECUTED"                     # 135  NOT_RUN
readonly CBS_FLUTTER_QUAL_REASON_PREFLIGHT_NOT_PASSED="PREFLIGHT_NOT_PASSED"     # 136  NOT_RUN
readonly CBS_FLUTTER_QUAL_REASON_NOT_SELECTED="NOT_SELECTED"                     # 137  SKIPPED

readonly CBS_RC_FLUTTER_QUAL_OK=0
readonly CBS_RC_FLUTTER_QUAL_USAGE=64
readonly CBS_RC_FLUTTER_QUAL_CONTRACT_VERSION_UNSUPPORTED=120
readonly CBS_RC_FLUTTER_QUAL_INPUT_INVALID=121
readonly CBS_RC_FLUTTER_QUAL_ACTION_NOT_ALLOWED=122
readonly CBS_RC_FLUTTER_QUAL_ARGUMENT_REFUSED=123
readonly CBS_RC_FLUTTER_QUAL_PATH_NOT_ALLOWED=124
readonly CBS_RC_FLUTTER_QUAL_SECRET_REFUSED=125
readonly CBS_RC_FLUTTER_QUAL_ISOLATION_REJECTED=126
readonly CBS_RC_FLUTTER_QUAL_TOOL_UNAVAILABLE=127
readonly CBS_RC_FLUTTER_QUAL_TOOLCHAIN_INCOMPATIBLE=128
readonly CBS_RC_FLUTTER_QUAL_SIMULATOR_UNAVAILABLE=129
readonly CBS_RC_FLUTTER_QUAL_COMMAND_FAILED=130
readonly CBS_RC_FLUTTER_QUAL_TIMEOUT=131
readonly CBS_RC_FLUTTER_QUAL_NETWORK_FAILURE=132
readonly CBS_RC_FLUTTER_QUAL_LOG_LIMIT_EXCEEDED=133
readonly CBS_RC_FLUTTER_QUAL_EVIDENCE_FAILURE=134
readonly CBS_RC_FLUTTER_QUAL_NOT_EXECUTED=135
readonly CBS_RC_FLUTTER_QUAL_PREFLIGHT_NOT_PASSED=136
readonly CBS_RC_FLUTTER_QUAL_NOT_SELECTED=137

# --- Validation patterns and bounds (extended regular expressions) -----------

readonly CBS_FLUTTER_QUAL_PATTERN_KEY='^[a-z][a-z0-9_]{0,39}$'
readonly CBS_FLUTTER_QUAL_PATTERN_PATH='^/[A-Za-z0-9._+@/-]+$'
readonly CBS_FLUTTER_QUAL_PATH_MAX_LENGTH=1024
readonly CBS_FLUTTER_QUAL_PATTERN_ORIGIN='^[A-Za-z0-9][A-Za-z0-9._~:/@+%-]*$'
readonly CBS_FLUTTER_QUAL_ORIGIN_MAX_LENGTH=1024
readonly CBS_FLUTTER_QUAL_PATTERN_UINT='^[1-9][0-9]{0,8}$'
readonly CBS_FLUTTER_QUAL_PATTERN_TOOL_RC='^[0-9]{1,3}$'
readonly CBS_FLUTTER_QUAL_PATTERN_SIMULATOR_UDID='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
readonly CBS_FLUTTER_QUAL_PATTERN_TEST_TARGET='^(test|integration_test)/[A-Za-z0-9_/.-]+_test\.dart$'

# Upper and lower safety bounds. They are bounds, not defaults: the request
# must carry an explicit value. The final values are an open design decision.
readonly CBS_FLUTTER_QUAL_TIMEOUT_MIN=1
readonly CBS_FLUTTER_QUAL_TIMEOUT_MAX=3600
readonly CBS_FLUTTER_QUAL_LOG_MAX_BYTES_MIN=1024
readonly CBS_FLUTTER_QUAL_LOG_MAX_BYTES_MAX=104857600
readonly CBS_FLUTTER_QUAL_TEST_TARGETS_MAX=16
readonly CBS_FLUTTER_QUAL_TEST_TARGET_MAX_LENGTH=255
readonly CBS_FLUTTER_QUAL_REQUEST_ENTRIES_MAX=32

# Values accepted by the enumerated parameters.
readonly CBS_FLUTTER_QUAL_TEST_SCOPE_UNIT_WIDGET="unit_widget"
readonly CBS_FLUTTER_QUAL_TEST_SCOPE_INTEGRATION="integration"
readonly CBS_FLUTTER_QUAL_SIMULATOR_POLICY_EXISTING_ONLY="existing_only"
readonly CBS_FLUTTER_QUAL_RETENTION_KEEP="keep"
readonly CBS_FLUTTER_QUAL_CLEANUP_NONE="none"
readonly CBS_FLUTTER_QUAL_CLEANUP_EXPLICIT="explicit"

# Keys that must be present in every request (no implicit default).
readonly CBS_FLUTTER_QUAL_REQUIRED_KEYS="contract_version qualification_id isolation_id source_repository expected_origin commit isolation_root evidence_root target actions timeout_seconds log_max_bytes evidence_retention cleanup_policy"

# Keys that may be present. Any other key is refused.
readonly CBS_FLUTTER_QUAL_OPTIONAL_KEYS="test_scope test_targets simulator_udid simulator_policy"

# Last validation outcome (set by the cbs_flutter_qual_validate_* functions).
# The key is only recorded when it has a safe format; a value is never recorded.
CBS_FLUTTER_QUAL_VALIDATION_REASON=""
CBS_FLUTTER_QUAL_VALIDATION_KEY=""

# --- Results, operations, actions ---------------------------------------------

cbs_flutter_qual_result_is_valid() {
    case "${1:-}" in
        PASS|FAIL|BLOCKED|SKIPPED|NOT_RUN)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_flutter_qual_operation_is_valid() {
    case "${1:-}" in
        PREFLIGHT|ANALYZE|TEST|BUILD_IOS|REPORT)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Action names are lowercase only: "PREFLIGHT" is not an action.
cbs_flutter_qual_action_is_valid() {
    case "${1:-}" in
        preflight|analyze|test|build_ios|report)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Argument: action. Prints the operation, fails on an unknown action.
cbs_flutter_qual_operation_for_action() {
    case "${1:-}" in
        preflight) printf '%s\n' "PREFLIGHT" ;;
        analyze) printf '%s\n' "ANALYZE" ;;
        test) printf '%s\n' "TEST" ;;
        build_ios) printf '%s\n' "BUILD_IOS" ;;
        report) printf '%s\n' "REPORT" ;;
        *) return 1 ;;
    esac
}

# Argument: operation. Prints the action, fails on an unknown operation.
cbs_flutter_qual_action_for_operation() {
    case "${1:-}" in
        PREFLIGHT) printf '%s\n' "preflight" ;;
        ANALYZE) printf '%s\n' "analyze" ;;
        TEST) printf '%s\n' "test" ;;
        BUILD_IOS) printf '%s\n' "build_ios" ;;
        REPORT) printf '%s\n' "report" ;;
        *) return 1 ;;
    esac
}

# Position of an action in the canonical order (1..5). Fails if unknown.
cbs_flutter_qual_action_rank() {
    case "${1:-}" in
        preflight) printf '%s\n' 1 ;;
        analyze) printf '%s\n' 2 ;;
        test) printf '%s\n' 3 ;;
        build_ios) printf '%s\n' 4 ;;
        report) printf '%s\n' 5 ;;
        *) return 1 ;;
    esac
}

# Mutating operations may write into the isolated checkout (.dart_tool/,
# build/, ios/Flutter/, caches). PREFLIGHT only observes; REPORT only writes
# its own evidence and must always remain possible, to document a refusal.
cbs_flutter_qual_operation_is_mutating() {
    case "${1:-}" in
        ANALYZE|TEST|BUILD_IOS)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Arguments: OPERATION PREFLIGHT_RESULT
# A mutating operation is allowed only after a PREFLIGHT that is exactly PASS.
cbs_flutter_qual_gate_allows() {
    local operation="${1:-}"
    local preflight_result="${2:-}"

    cbs_flutter_qual_operation_is_valid "$operation" || return 1
    cbs_flutter_qual_result_is_valid "$preflight_result" || return 1

    if cbs_flutter_qual_operation_is_mutating "$operation"; then
        [[ "$preflight_result" == "$CBS_FLUTTER_QUAL_RESULT_PASS" ]]
        return $?
    fi

    return 0
}

# Arguments: RESULT...
# Overall result: FAIL, then BLOCKED, then NOT_RUN take precedence over PASS.
# SKIPPED alone never makes a PASS: when nothing passed, the outcome is
# NOT_RUN (nothing was observed). Fails on an invalid or missing result.
cbs_flutter_qual_aggregate() {
    local result
    local seen_fail=0
    local seen_blocked=0
    local seen_not_run=0
    local seen_pass=0

    [[ "$#" -gt 0 ]] || return 1

    for result in "$@"; do
        cbs_flutter_qual_result_is_valid "$result" || return 1

        case "$result" in
            FAIL) seen_fail=1 ;;
            BLOCKED) seen_blocked=1 ;;
            NOT_RUN) seen_not_run=1 ;;
            PASS) seen_pass=1 ;;
        esac
    done

    if [[ "$seen_fail" -eq 1 ]]; then
        printf '%s\n' "$CBS_FLUTTER_QUAL_RESULT_FAIL"
    elif [[ "$seen_blocked" -eq 1 ]]; then
        printf '%s\n' "$CBS_FLUTTER_QUAL_RESULT_BLOCKED"
    elif [[ "$seen_not_run" -eq 1 || "$seen_pass" -eq 0 ]]; then
        printf '%s\n' "$CBS_FLUTTER_QUAL_RESULT_NOT_RUN"
    else
        printf '%s\n' "$CBS_FLUTTER_QUAL_RESULT_PASS"
    fi
}

# --- Reasons and return codes --------------------------------------------------

# Argument: reason. Prints "<rc> <result>", fails on an unknown reason.
_cbs_flutter_qual_reason_row() {
    case "${1:-}" in
        USAGE) printf '%s\n' "64 BLOCKED" ;;
        CONTRACT_VERSION_UNSUPPORTED) printf '%s\n' "120 BLOCKED" ;;
        INPUT_INVALID) printf '%s\n' "121 BLOCKED" ;;
        ACTION_NOT_ALLOWED) printf '%s\n' "122 BLOCKED" ;;
        ARGUMENT_REFUSED) printf '%s\n' "123 BLOCKED" ;;
        PATH_NOT_ALLOWED) printf '%s\n' "124 BLOCKED" ;;
        SECRET_REFUSED) printf '%s\n' "125 BLOCKED" ;;
        ISOLATION_REJECTED) printf '%s\n' "126 BLOCKED" ;;
        TOOL_UNAVAILABLE) printf '%s\n' "127 BLOCKED" ;;
        TOOLCHAIN_INCOMPATIBLE) printf '%s\n' "128 BLOCKED" ;;
        SIMULATOR_UNAVAILABLE) printf '%s\n' "129 BLOCKED" ;;
        COMMAND_FAILED) printf '%s\n' "130 FAIL" ;;
        TIMEOUT) printf '%s\n' "131 FAIL" ;;
        NETWORK_FAILURE) printf '%s\n' "132 FAIL" ;;
        LOG_LIMIT_EXCEEDED) printf '%s\n' "133 FAIL" ;;
        EVIDENCE_FAILURE) printf '%s\n' "134 FAIL" ;;
        NOT_EXECUTED) printf '%s\n' "135 NOT_RUN" ;;
        PREFLIGHT_NOT_PASSED) printf '%s\n' "136 NOT_RUN" ;;
        NOT_SELECTED) printf '%s\n' "137 SKIPPED" ;;
        *) return 1 ;;
    esac
}

cbs_flutter_qual_reason_is_valid() {
    _cbs_flutter_qual_reason_row "${1:-}" >/dev/null
}

# Argument: reason (empty = success). Prints the return code.
cbs_flutter_qual_rc_for_reason() {
    local row

    if [[ -z "${1:-}" ]]; then
        printf '%s\n' "0"
        return 0
    fi

    row="$(_cbs_flutter_qual_reason_row "$1")" || return 1
    printf '%s\n' "${row%% *}"
}

# Argument: reason. Prints the result class of the reason.
cbs_flutter_qual_result_for_reason() {
    local row

    row="$(_cbs_flutter_qual_reason_row "${1:-}")" || return 1
    printf '%s\n' "${row#* }"
}

# Arguments: RESULT [REASON]
# PASS carries no reason; every other result carries a reason of its own class.
cbs_flutter_qual_result_reason_consistent() {
    local result="${1:-}"
    local reason="${2:-}"
    local class

    cbs_flutter_qual_result_is_valid "$result" || return 1

    if [[ "$result" == "$CBS_FLUTTER_QUAL_RESULT_PASS" ]]; then
        [[ -z "$reason" ]]
        return $?
    fi

    [[ -n "$reason" ]] || return 1
    class="$(cbs_flutter_qual_result_for_reason "$reason")" || return 1
    [[ "$class" == "$result" ]]
}

# --- Identifiers and formats ---------------------------------------------------

# Qualification and isolation identifiers follow the isolation contract.
cbs_flutter_qual_id_valid() {
    cbs_isolation_id_valid "${1:-}"
}

# Full lowercase object name (40 or 64 hex).
cbs_flutter_qual_commit_valid() {
    cbs_isolation_commit_format_valid "${1:-}"
}

# Text accepted as data: non-empty, no control character (newline included).
cbs_flutter_qual_text_valid() {
    cbs_isolation_valid_text "${1:-}"
}

# Parameter key format: lowercase, digits and underscore.
cbs_flutter_qual_key_valid() {
    local key="${1:-}"

    [[ "$key" =~ $CBS_FLUTTER_QUAL_PATTERN_KEY ]]
}

# Unsigned decimal, no leading zero, within MIN..MAX (inclusive).
# Arguments: VALUE MIN MAX
cbs_flutter_qual_uint_in_range() {
    local value="${1:-}"
    local min="$2"
    local max="$3"

    [[ "$value" =~ $CBS_FLUTTER_QUAL_PATTERN_UINT ]] || return 1
    [[ "$((10#$value))" -ge "$min" && "$((10#$value))" -le "$max" ]]
}

# --- Paths (lexical, then optional read-only canonical check) -----------------

# An authorized path is absolute and lexical-only safe: restricted character
# set (no space, no "~", no "$", no glob or shell metacharacter), no empty
# component, no "." or ".." component, no trailing slash, at least two
# components, and no component naming a repository or credential store.
cbs_flutter_qual_path_valid() {
    local path="${1:-}"
    local rest
    local component
    local depth=0

    [[ -n "$path" ]] || return 1
    [[ "${#path}" -le "$CBS_FLUTTER_QUAL_PATH_MAX_LENGTH" ]] || return 1
    [[ "$path" =~ $CBS_FLUTTER_QUAL_PATTERN_PATH ]] || return 1

    case "$path" in
        */|*//*)
            return 1
            ;;
    esac

    rest="${path#/}"

    while [[ -n "$rest" ]]; do
        component="${rest%%/*}"

        if [[ "$rest" == */* ]]; then
            rest="${rest#*/}"
        else
            rest=""
        fi

        case "$component" in
            .|..)
                return 1
                ;;
            .[Gg][Ii][Tt]|\
            .[Ll][Oo][Cc][Aa][Ll]|\
            .[Ss][Ss][Hh]|\
            .[Gg][Nn][Uu][Pp][Gg]|\
            .[Aa][Ww][Ss]|\
            .[Kk][Uu][Bb][Ee]|\
            .[Dd][Oo][Cc][Kk][Ee][Rr]|\
            .[Nn][Ee][Tt][Rr][Cc]|\
            .[Ee][Nn][Vv])
                return 1
                ;;
        esac

        depth=$((depth + 1))
    done

    [[ "$depth" -ge 2 ]]
}

# Arguments: ROOT PATH. Succeeds when PATH is strictly inside ROOT (lexical).
cbs_flutter_qual_path_is_within() {
    local root="${1:-}"
    local path="${2:-}"

    cbs_flutter_qual_path_valid "$root" || return 1
    cbs_flutter_qual_path_valid "$path" || return 1

    [[ "$path" == "$root"/* ]]
}

# Arguments: A B. Succeeds when both are valid and neither equals nor contains
# the other (lexical).
cbs_flutter_qual_paths_disjoint() {
    local first="${1:-}"
    local second="${2:-}"

    cbs_flutter_qual_path_valid "$first" || return 1
    cbs_flutter_qual_path_valid "$second" || return 1

    [[ "$first" != "$second" ]] || return 1
    [[ "$second" != "$first"/* ]] || return 1
    [[ "$first" != "$second"/* ]] || return 1
}

# Read-only. Succeeds when PATH is a valid existing directory that is its own
# physical path: no symbolic link in any component. On macOS, /tmp and /var are
# symbolic links: callers must canonicalize (cd -P; pwd -P) before asking.
cbs_flutter_qual_dir_is_canonical() {
    local path="${1:-}"
    local resolved

    cbs_flutter_qual_path_valid "$path" || return 1
    [[ -d "$path" ]] || return 1

    resolved="$(cd -P -- "$path" 2>/dev/null && pwd -P)" || return 1

    [[ "$resolved" == "$path" ]]
}

# --- Secrets -------------------------------------------------------------------
#
# Keywords (as BRE, ASCII case-insensitive through bracket expressions: BSD sed
# has no "I" flag and no "\|"). Space-separated, split by hand: never expanded
# unquoted, so a bracket expression can never be globbed.
readonly CBS_FLUTTER_QUAL_SECRET_WORDS='[Tt][Oo][Kk][Ee][Nn] [Ss][Ee][Cc][Rr][Ee][Tt] [Pp][Aa][Ss][Ss][Ww] [Pp][Aa][Ss][Ss][Pp][Hh][Rr][Aa][Ss][Ee] [Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll] [Aa][Pp][Ii][Kk][Ee][Yy] [Aa][Pp][Ii][_-][Kk][Ee][Yy] [Pp][Rr][Ii][Vv][Aa][Tt][Ee][_-][Kk][Ee][Yy] [Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]'

# Succeeds when the name of a parameter or variable looks sensitive.
cbs_flutter_qual_key_is_sensitive() {
    local key="${1:-}"

    case "$key" in
        *[Tt][Oo][Kk][Ee][Nn]*|\
        *[Ss][Ee][Cc][Rr][Ee][Tt]*|\
        *[Pp][Aa][Ss][Ss][Ww]*|\
        *[Pp][Aa][Ss][Ss][Pp]*|\
        *[Cc][Rr][Ee][Dd][Ee][Nn]*|\
        *[Aa][Pp][Ii][_-]*[Kk][Ee][Yy]*|\
        *[Aa][Pp][Ii][Kk][Ee][Yy]*|\
        *[Pp][Rr][Ii][Vv][Aa][Tt][Ee]*[Kk][Ee][Yy]*|\
        *[Aa][Uu][Tt][Hh]*|\
        *[Dd][Aa][Rr][Tt][_-]*[Dd][Ee][Ff][Ii][Nn][Ee]*)
            return 0
            ;;
    esac

    return 1
}

# stdin -> stdout. Replaces secrets with [REDACTED]. Portable sed subset only:
# basic regular expressions, no GNU escape, no "-i", "-r" or "-z", only the
# "g" flag. Idempotent. Best effort on a line basis: the contract guarantees
# the listed patterns, not the absence of any secret in free text.
#
#   - private key blocks (every line between BEGIN and END);
#   - credentials in URLs (scheme://user:secret@host);
#   - Bearer tokens;
#   - --dart-define / --dart-define-from-file values;
#   - well-known token formats (GitHub, AWS access key, Slack, GitLab);
#   - KEY=VALUE or KEY: VALUE when KEY contains a sensitive word.
cbs_flutter_qual_redact_stream() {
    local -a sed_args
    local rest
    local word
    local key_chars='[A-Za-z0-9_.-]*'
    local quote="[\"']"

    sed_args=(
        -e '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/s/.*/[REDACTED PRIVATE KEY]/'
        -e 's#\([Bb]earer\)[[:space:]]\{1,\}[^[:space:]]\{1,\}#\1 [REDACTED]#g'
        -e 's#--dart-define-from-file=[^[:space:]]\{1,\}#--dart-define-from-file=[REDACTED]#g'
        -e 's#--dart-define=\([^=[:space:]]\{1,\}\)=[^[:space:]]\{1,\}#--dart-define=\1=[REDACTED]#g'
        -e 's#--dart-define[[:space:]]\{1,\}\([^=[:space:]]\{1,\}\)=[^[:space:]]\{1,\}#--dart-define \1=[REDACTED]#g'
        -e 's#://[^/@[:space:]]*@#://[REDACTED]@#g'
        -e 's#gh[pousr]_[A-Za-z0-9]\{20,\}#[REDACTED]#g'
        -e 's#AKIA[0-9A-Z]\{16\}#[REDACTED]#g'
        -e 's#xox[abprs]-[A-Za-z0-9-]\{10,\}#[REDACTED]#g'
        -e 's#glpat-[A-Za-z0-9_-]\{10,\}#[REDACTED]#g'
    )

    rest="$CBS_FLUTTER_QUAL_SECRET_WORDS"

    while [[ -n "$rest" ]]; do
        word="${rest%% *}"

        if [[ "$rest" == *" "* ]]; then
            rest="${rest#* }"
        else
            rest=""
        fi

        sed_args=(
            "${sed_args[@]}"
            -e 's#\('"$key_chars$word$key_chars$quote"'\{0,1\}[=:][[:space:]]*\)[^[:space:]]\{1,\}#\1[REDACTED]#g'
        )
    done

    sed "${sed_args[@]}"
}

# Argument: text. Prints the redacted text (with a trailing newline).
cbs_flutter_qual_redact() {
    printf '%s\n' "${1-}" | cbs_flutter_qual_redact_stream
}

# Argument: text. Succeeds when redaction would change the text.
cbs_flutter_qual_text_contains_secret() {
    local text="${1-}"
    local redacted

    redacted="$(printf '%s\n' "$text" | cbs_flutter_qual_redact_stream)" ||
        return 0

    [[ "$redacted" != "$text" ]]
}

# --- Parameter and request validation -----------------------------------------
#
# Every validator returns 0 or the specific return code of the refusal, and
# records the reason in CBS_FLUTTER_QUAL_VALIDATION_REASON. Nothing is printed:
# in particular a refused value is never echoed.

# Arguments: REASON [KEY]
_cbs_flutter_qual_reject() {
    CBS_FLUTTER_QUAL_VALIDATION_REASON="$1"
    CBS_FLUTTER_QUAL_VALIDATION_KEY=""

    if [[ -n "${2:-}" ]] && cbs_flutter_qual_key_valid "$2"; then
        CBS_FLUTTER_QUAL_VALIDATION_KEY="$2"
    fi

    return "$(cbs_flutter_qual_rc_for_reason "$1")"
}

_cbs_flutter_qual_accept() {
    CBS_FLUTTER_QUAL_VALIDATION_REASON=""
    CBS_FLUTTER_QUAL_VALIDATION_KEY=""
    return 0
}

# Succeeds when the word is one of the keys of the list (space-separated).
_cbs_flutter_qual_key_in_list() {
    local wanted="$1"
    local list="$2"
    local rest="$list"
    local word

    while [[ -n "$rest" ]]; do
        word="${rest%% *}"

        if [[ "$rest" == *" "* ]]; then
            rest="${rest#* }"
        else
            rest=""
        fi

        [[ "$word" == "$wanted" ]] && return 0
    done

    return 1
}

cbs_flutter_qual_key_is_allowed() {
    _cbs_flutter_qual_key_in_list "${1:-}" "$CBS_FLUTTER_QUAL_REQUIRED_KEYS" && return 0
    _cbs_flutter_qual_key_in_list "${1:-}" "$CBS_FLUTTER_QUAL_OPTIONAL_KEYS"
}

# Arguments: KEY ENTRY... Prints the value of the first matching entry.
# Fails when the key is absent. Keys are compared as plain strings.
cbs_flutter_qual_entries_get() {
    local wanted="$1"
    local entry

    shift

    for entry in "$@"; do
        if [[ "${entry%%=*}" == "$wanted" && "$entry" == *=* ]]; then
            printf '%s' "${entry#*=}"
            return 0
        fi
    done

    return 1
}

# Arguments: KEY ENTRY... Succeeds when an entry carries the key.
cbs_flutter_qual_entries_has() {
    local wanted="$1"
    local entry

    shift

    for entry in "$@"; do
        if [[ "${entry%%=*}" == "$wanted" && "$entry" == *=* ]]; then
            return 0
        fi
    done

    return 1
}

# Argument: comma-separated action list. Rules:
#   - every item is an allowed action, lowercase (otherwise ACTION_NOT_ALLOWED);
#   - no empty item, no duplicate, canonical order (otherwise INPUT_INVALID);
#   - a mutating action requires "preflight" to be selected, first.
cbs_flutter_qual_validate_actions() {
    local list="${1-}"
    local rest
    local item
    local rank
    local last_rank=0
    local first_rank=0
    local seen_mutating=0
    local seen_preflight=0

    cbs_flutter_qual_text_valid "$list" ||
        { _cbs_flutter_qual_reject "INPUT_INVALID" "actions"; return $?; }

    rest="$list,"

    while [[ -n "$rest" ]]; do
        item="${rest%%,*}"
        rest="${rest#*,}"

        [[ -n "$item" ]] ||
            { _cbs_flutter_qual_reject "INPUT_INVALID" "actions"; return $?; }

        rank="$(cbs_flutter_qual_action_rank "$item")" ||
            { _cbs_flutter_qual_reject "ACTION_NOT_ALLOWED" "actions"; return $?; }

        [[ "$rank" -gt "$last_rank" ]] ||
            { _cbs_flutter_qual_reject "INPUT_INVALID" "actions"; return $?; }

        [[ "$first_rank" -ne 0 ]] || first_rank="$rank"
        last_rank="$rank"

        case "$item" in
            preflight) seen_preflight=1 ;;
            analyze|test|build_ios) seen_mutating=1 ;;
        esac
    done

    if [[ "$seen_mutating" -eq 1 ]]; then
        if [[ "$seen_preflight" -ne 1 || "$first_rank" -ne 1 ]]; then
            _cbs_flutter_qual_reject "INPUT_INVALID" "actions"
            return $?
        fi
    fi

    _cbs_flutter_qual_accept
}

# Argument: ACTION. A single allowed action name.
cbs_flutter_qual_validate_action() {
    cbs_flutter_qual_action_is_valid "${1:-}" ||
        { _cbs_flutter_qual_reject "ACTION_NOT_ALLOWED" "actions"; return $?; }

    _cbs_flutter_qual_accept
}

# Arguments: ACTION [ARG...]
# An action takes no argument: its arguments are fixed by the contract, never
# supplied by the caller. Any extra word is refused, whatever it contains.
cbs_flutter_qual_validate_action_call() {
    cbs_flutter_qual_validate_action "${1:-}" || return $?

    if [[ "$#" -gt 1 ]]; then
        _cbs_flutter_qual_reject "ARGUMENT_REFUSED" ""
        return $?
    fi

    _cbs_flutter_qual_accept
}

# Argument: comma-separated relative test files.
cbs_flutter_qual_validate_test_targets() {
    local list="${1-}"
    local rest
    local item
    local seen=","
    local count=0

    cbs_flutter_qual_text_valid "$list" ||
        { _cbs_flutter_qual_reject "INPUT_INVALID" "test_targets"; return $?; }

    rest="$list,"

    while [[ -n "$rest" ]]; do
        item="${rest%%,*}"
        rest="${rest#*,}"

        [[ -n "$item" ]] ||
            { _cbs_flutter_qual_reject "INPUT_INVALID" "test_targets"; return $?; }

        [[ "${#item}" -le "$CBS_FLUTTER_QUAL_TEST_TARGET_MAX_LENGTH" ]] ||
            { _cbs_flutter_qual_reject "PATH_NOT_ALLOWED" "test_targets"; return $?; }

        [[ "$item" =~ $CBS_FLUTTER_QUAL_PATTERN_TEST_TARGET ]] ||
            { _cbs_flutter_qual_reject "PATH_NOT_ALLOWED" "test_targets"; return $?; }

        case "$item" in
            */../*|*/./*|*//*|*/..|*/.)
                _cbs_flutter_qual_reject "PATH_NOT_ALLOWED" "test_targets"
                return $?
                ;;
        esac

        case "$seen" in
            *",$item,"*)
                _cbs_flutter_qual_reject "INPUT_INVALID" "test_targets"
                return $?
                ;;
        esac

        seen="$seen$item,"
        count=$((count + 1))

        [[ "$count" -le "$CBS_FLUTTER_QUAL_TEST_TARGETS_MAX" ]] ||
            { _cbs_flutter_qual_reject "INPUT_INVALID" "test_targets"; return $?; }
    done

    _cbs_flutter_qual_accept
}

# Arguments: KEY VALUE. Validates one parameter in isolation.
cbs_flutter_qual_validate_param() {
    local key="${1:-}"
    local value="${2-}"

    cbs_flutter_qual_key_valid "$key" ||
        { _cbs_flutter_qual_reject "ARGUMENT_REFUSED" ""; return $?; }

    if ! cbs_flutter_qual_key_is_allowed "$key"; then
        if cbs_flutter_qual_key_is_sensitive "$key"; then
            _cbs_flutter_qual_reject "SECRET_REFUSED" "$key"
        else
            _cbs_flutter_qual_reject "ARGUMENT_REFUSED" "$key"
        fi
        return $?
    fi

    cbs_flutter_qual_text_valid "$value" ||
        { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }

    # A secret is refused whatever the key, before any other interpretation.
    if cbs_flutter_qual_text_contains_secret "$value"; then
        _cbs_flutter_qual_reject "SECRET_REFUSED" "$key"
        return $?
    fi

    case "$key" in
        contract_version)
            [[ "$value" =~ $CBS_FLUTTER_QUAL_PATTERN_UINT ]] ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            [[ "$value" == "$CBS_FLUTTER_QUAL_CONTRACT_VERSION" ]] ||
                { _cbs_flutter_qual_reject "CONTRACT_VERSION_UNSUPPORTED" "$key"; return $?; }
            ;;
        qualification_id|isolation_id)
            cbs_flutter_qual_id_valid "$value" ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            ;;
        source_repository|isolation_root|evidence_root)
            cbs_flutter_qual_path_valid "$value" ||
                { _cbs_flutter_qual_reject "PATH_NOT_ALLOWED" "$key"; return $?; }
            ;;
        expected_origin)
            [[ "${#value}" -le "$CBS_FLUTTER_QUAL_ORIGIN_MAX_LENGTH" ]] ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            [[ "$value" =~ $CBS_FLUTTER_QUAL_PATTERN_ORIGIN ]] ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            # scheme://user@host and scheme://user:secret@host carry credentials.
            case "$value" in
                *://*@*)
                    _cbs_flutter_qual_reject "SECRET_REFUSED" "$key"
                    return $?
                    ;;
            esac
            ;;
        commit)
            cbs_flutter_qual_commit_valid "$value" ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            ;;
        target)
            [[ "$value" == "$CBS_FLUTTER_QUAL_TARGET_IOS_SIMULATOR" ]] ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            ;;
        actions)
            cbs_flutter_qual_validate_actions "$value"
            return $?
            ;;
        timeout_seconds)
            cbs_flutter_qual_uint_in_range "$value" \
                "$CBS_FLUTTER_QUAL_TIMEOUT_MIN" "$CBS_FLUTTER_QUAL_TIMEOUT_MAX" ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            ;;
        log_max_bytes)
            cbs_flutter_qual_uint_in_range "$value" \
                "$CBS_FLUTTER_QUAL_LOG_MAX_BYTES_MIN" "$CBS_FLUTTER_QUAL_LOG_MAX_BYTES_MAX" ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            ;;
        evidence_retention)
            [[ "$value" == "$CBS_FLUTTER_QUAL_RETENTION_KEEP" ]] ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            ;;
        cleanup_policy)
            case "$value" in
                "$CBS_FLUTTER_QUAL_CLEANUP_NONE"|"$CBS_FLUTTER_QUAL_CLEANUP_EXPLICIT")
                    ;;
                *)
                    _cbs_flutter_qual_reject "INPUT_INVALID" "$key"
                    return $?
                    ;;
            esac
            ;;
        test_scope)
            case "$value" in
                "$CBS_FLUTTER_QUAL_TEST_SCOPE_UNIT_WIDGET"|"$CBS_FLUTTER_QUAL_TEST_SCOPE_INTEGRATION")
                    ;;
                *)
                    _cbs_flutter_qual_reject "INPUT_INVALID" "$key"
                    return $?
                    ;;
            esac
            ;;
        test_targets)
            cbs_flutter_qual_validate_test_targets "$value"
            return $?
            ;;
        simulator_udid)
            [[ "$value" =~ $CBS_FLUTTER_QUAL_PATTERN_SIMULATOR_UDID ]] ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            ;;
        simulator_policy)
            # No implicit creation or boot of a simulator: only an existing
            # simulator may be used.
            [[ "$value" == "$CBS_FLUTTER_QUAL_SIMULATOR_POLICY_EXISTING_ONLY" ]] ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "$key"; return $?; }
            ;;
    esac

    _cbs_flutter_qual_accept
}

# Arguments: ENTRY... where every ENTRY is KEY=VALUE.
#
# The request is data: it is never sourced, evaluated or expanded. A word that
# is not a KEY=VALUE entry with a well-formed key (an option such as --flag, a
# command, a path, a dart-define) is an arbitrary argument and is refused.
# Checks, in order, per entry: form, key allow-list, duplicates, value. Then
# the whole request: required keys, cross-field rules, disjoint paths.
cbs_flutter_qual_validate_request() {
    local entry
    local key
    local value
    local index
    local other
    local actions=""
    local test_scope=""
    local test_targets=""
    local target
    local rest
    local prefix
    local required

    _cbs_flutter_qual_accept

    [[ "$#" -le "$CBS_FLUTTER_QUAL_REQUEST_ENTRIES_MAX" ]] ||
        { _cbs_flutter_qual_reject "INPUT_INVALID" ""; return $?; }

    # 1. Form and per-parameter validation.
    for entry in "$@"; do
        if [[ "$entry" != *=* ]]; then
            _cbs_flutter_qual_reject "ARGUMENT_REFUSED" ""
            return $?
        fi

        key="${entry%%=*}"
        value="${entry#*=}"

        cbs_flutter_qual_validate_param "$key" "$value" || return $?
    done

    # 2. Duplicates (a later entry must never override an earlier one).
    index=0
    for entry in "$@"; do
        index=$((index + 1))
        key="${entry%%=*}"
        other=0

        for value in "$@"; do
            other=$((other + 1))
            [[ "$other" -gt "$index" ]] || continue

            if [[ "${value%%=*}" == "$key" ]]; then
                _cbs_flutter_qual_reject "INPUT_INVALID" "$key"
                return $?
            fi
        done
    done

    # 3. Required keys: no implicit default.
    rest="$CBS_FLUTTER_QUAL_REQUIRED_KEYS"
    while [[ -n "$rest" ]]; do
        required="${rest%% *}"

        if [[ "$rest" == *" "* ]]; then
            rest="${rest#* }"
        else
            rest=""
        fi

        cbs_flutter_qual_entries_has "$required" "$@" ||
            { _cbs_flutter_qual_reject "INPUT_INVALID" "$required"; return $?; }
    done

    # 4. Cross-field rules.
    actions="$(cbs_flutter_qual_entries_get actions "$@")"
    test_scope="$(cbs_flutter_qual_entries_get test_scope "$@" || true)"
    test_targets="$(cbs_flutter_qual_entries_get test_targets "$@" || true)"

    case ",$actions," in
        *,test,*)
            [[ -n "$test_scope" ]] ||
                { _cbs_flutter_qual_reject "INPUT_INVALID" "test_scope"; return $?; }
            ;;
        *)
            if [[ -n "$test_scope" ]]; then
                _cbs_flutter_qual_reject "INPUT_INVALID" "test_scope"
                return $?
            fi

            if [[ -n "$test_targets" ]]; then
                _cbs_flutter_qual_reject "INPUT_INVALID" "test_targets"
                return $?
            fi
            ;;
    esac

    # integration tests need a device: an explicit simulator is mandatory.
    if [[ "$test_scope" == "$CBS_FLUTTER_QUAL_TEST_SCOPE_INTEGRATION" ]]; then
        cbs_flutter_qual_entries_has simulator_udid "$@" ||
            { _cbs_flutter_qual_reject "INPUT_INVALID" "simulator_udid"; return $?; }
    fi

    # Every selected test file lives in the directory of the declared scope.
    if [[ -n "$test_targets" ]]; then
        if [[ "$test_scope" == "$CBS_FLUTTER_QUAL_TEST_SCOPE_INTEGRATION" ]]; then
            prefix="integration_test/"
        else
            prefix="test/"
        fi

        rest="$test_targets"
        while [[ -n "$rest" ]]; do
            target="${rest%%,*}"

            if [[ "$rest" == *,* ]]; then
                rest="${rest#*,}"
            else
                rest=""
            fi

            case "$target" in
                "$prefix"*)
                    ;;
                *)
                    _cbs_flutter_qual_reject "INPUT_INVALID" "test_targets"
                    return $?
                    ;;
            esac
        done
    fi

    # 5. The three roots never overlap: the source repository is never a place
    # to run or to write, and the evidence must outlive the isolated checkout.
    local source_repository isolation_root evidence_root

    source_repository="$(cbs_flutter_qual_entries_get source_repository "$@")"
    isolation_root="$(cbs_flutter_qual_entries_get isolation_root "$@")"
    evidence_root="$(cbs_flutter_qual_entries_get evidence_root "$@")"

    cbs_flutter_qual_paths_disjoint "$source_repository" "$isolation_root" ||
        { _cbs_flutter_qual_reject "PATH_NOT_ALLOWED" "isolation_root"; return $?; }
    cbs_flutter_qual_paths_disjoint "$source_repository" "$evidence_root" ||
        { _cbs_flutter_qual_reject "PATH_NOT_ALLOWED" "evidence_root"; return $?; }
    cbs_flutter_qual_paths_disjoint "$isolation_root" "$evidence_root" ||
        { _cbs_flutter_qual_reject "PATH_NOT_ALLOWED" "evidence_root"; return $?; }

    _cbs_flutter_qual_accept
}

# --- Structured output ---------------------------------------------------------
#
# Only values taken from closed sets are ever printed: an operation, a result,
# a reason, a numeric code. A caller-supplied free text is never emitted.

# Arguments: OPERATION RESULT [REASON] [TOOL_RC]
# TOOL_RC is the exact exit status of the executed tool. It is accepted only
# for PASS (must be 0) and FAIL (the tool did run).
cbs_flutter_qual_emit_operation() {
    local operation="${1:-}"
    local result="${2:-}"
    local reason="${3:-}"
    local tool_rc="${4:-}"
    local rc

    if ! cbs_flutter_qual_operation_is_valid "$operation" ||
        ! cbs_flutter_qual_result_reason_consistent "$result" "$reason"; then
        echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
        return "$CBS_RC_FLUTTER_QUAL_USAGE"
    fi

    if [[ -n "$tool_rc" ]]; then
        if [[ ! "$tool_rc" =~ $CBS_FLUTTER_QUAL_PATTERN_TOOL_RC ||
            "$((10#$tool_rc))" -gt 255 ]]; then
            echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
            return "$CBS_RC_FLUTTER_QUAL_USAGE"
        fi

        case "$result" in
            PASS)
                if [[ "$((10#$tool_rc))" -ne 0 ]]; then
                    echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
                    return "$CBS_RC_FLUTTER_QUAL_USAGE"
                fi
                ;;
            FAIL)
                ;;
            *)
                echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
                return "$CBS_RC_FLUTTER_QUAL_USAGE"
                ;;
        esac
    fi

    rc="$(cbs_flutter_qual_rc_for_reason "$reason")"

    printf 'CBS_FLUTTER_QUAL_OPERATION=%s\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_OPERATION_RESULT=%s\n' "$result"

    if [[ -n "$reason" ]]; then
        printf 'CBS_FLUTTER_QUAL_OPERATION_REASON=%s\n' "$reason"
    fi

    printf 'CBS_FLUTTER_QUAL_OPERATION_RC=%s\n' "$rc"

    if [[ -n "$tool_rc" ]]; then
        printf 'CBS_FLUTTER_QUAL_OPERATION_TOOL_RC=%s\n' "$((10#$tool_rc))"
    fi

    return 0
}

# Arguments: RESULT [REASON]
# Overall outcome. SKIPPED is an operation-level result only. The RESULT line
# is always the last stdout line, so callers can rely on it.
cbs_flutter_qual_emit_result() {
    local result="${1:-}"
    local reason="${2:-}"

    if [[ "$result" == "$CBS_FLUTTER_QUAL_RESULT_SKIPPED" ]] ||
        ! cbs_flutter_qual_result_reason_consistent "$result" "$reason"; then
        echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
        return "$CBS_RC_FLUTTER_QUAL_USAGE"
    fi

    if [[ -n "$reason" ]]; then
        printf 'CBS_FLUTTER_QUAL_REASON=%s\n' "$reason"
        printf 'CBS_FLUTTER_QUAL_ERROR=%s\n' "$reason" >&2
    fi

    printf 'CBS_FLUTTER_QUAL_CONTRACT_VERSION=%s\n' "$CBS_FLUTTER_QUAL_CONTRACT_VERSION"
    printf 'CBS_FLUTTER_QUAL_RESULT=%s\n' "$result"

    return 0
}
