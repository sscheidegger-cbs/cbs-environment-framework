#!/usr/bin/env bash

# D04b-C.2b step 2 - Flutter/iOS qualification: PREFLIGHT.
#
#   preflight.sh KEY=VALUE...
#
# The arguments are the request defined by contract.sh (data only). PREFLIGHT
# observes and never changes anything:
#   - it validates the request with the qualified contract;
#   - it verifies, through "isolation_manager.sh verify" (read-only), that the
#     isolated checkout is owned by CBS, is the exact requested commit, is a
#     detached HEAD associated with the source repository and is clean;
#   - it detects Flutter, Dart, Xcode, the iphoneos / iphonesimulator SDKs and
#     simctl, and, when requested, the existence of the simulator.
#
# It never runs "flutter pub get" or any Flutter action other than
# "flutter --version"; never boots, creates or erases a simulator; never
# installs or modifies a toolchain; never writes a file, never removes a file,
# never touches the source repository or the isolated checkout; never uses
# eval; never sources a request or a manifest (the Flutter stack manifest of
# this repository is read line by line, two keys, never sourced); never builds
# a command from a request value.
#
# The only external commands, with fixed arguments, are:
#   flutter --version                         dart --version
#   xcodebuild -version
#   xcrun --sdk iphoneos --show-sdk-version   xcrun --sdk iphonesimulator --show-sdk-version
#   xcrun --find simctl                       xcrun simctl list devices
#   git --version                             git config --get <fixed probe key>
#   <this bash> isolation_manager.sh verify <id> <source> <root>
# Each one is looked up in the absolute entries of PATH only, runs from "/",
# without input, in its own process group, under timeout_seconds, and is killed
# (whole group) when the timeout expires.
#
# Bounded execution (_cbs_flutter_qual_pf_run). A small supervisor (a fixed
# script run by a fresh bash, never built from a request value) starts the
# command and a timer in two process groups. The timer only sleeps, then sends
# USR1 to the supervisor; the supervisor alone signals the command, and only
# while its own job table says that the command is still running. Whatever the
# outcome, the supervisor stops and reaps the timer, then removes the
# stragglers of the command group, before it reports: nothing outlives the
# call and no signal is sent later, from a timer, to a recycled PID or group.
# The timeout is reported by the supervisor itself (never guessed from a
# status or a duration).
#
# Git. The isolation manager runs raw git commands. Before any of them,
# PREFLIGHT neutralises the executable configuration (core.fsmonitor,
# core.hooksPath) through GIT_CONFIG_COUNT (git >= 2.31), and refuses a Git
# that would silently ignore it: the version must be >= 2.31 AND a sentinel
# value given through GIT_CONFIG_COUNT must be read back by "git config --get"
# (an older Git ignores GIT_CONFIG_COUNT without any error). GIT_CONFIG_PARAMETERS
# is removed from the environment: it takes precedence over GIT_CONFIG_COUNT.
#
# Per-check results (CBS_FLUTTER_QUAL_PREFLIGHT_CHECK_<NAME>) use the contract
# results. A check that was not reached is NOT_RUN, a check that was not
# requested is SKIPPED: neither one is a PASS. The overall result is PASS only
# when no check is FAIL, BLOCKED or NOT_RUN (SKIPPED checks stay visible).
#
# Reasons (contract.sh):
#   BLOCKED  USAGE, CONTRACT_VERSION_UNSUPPORTED, INPUT_INVALID, ACTION_NOT_ALLOWED,
#            ARGUMENT_REFUSED, PATH_NOT_ALLOWED, SECRET_REFUSED (request);
#            ISOLATION_REJECTED (checkout not owned / not exact / not detached /
#            not clean / not the requested commit or origin);
#            TOOL_UNAVAILABLE (tool absent from PATH, simctl not found);
#            TOOLCHAIN_INCOMPATIBLE (version, SDK or reference not acceptable;
#            Git older than 2.31 or ignoring GIT_CONFIG_COUNT);
#            SIMULATOR_UNAVAILABLE (requested simulator absent or unusable)
#   FAIL     COMMAND_FAILED (a probe ran and exited non-zero, its status is
#            reported as OPERATION_TOOL_RC), TIMEOUT
#
# Compatible with Bash 3.2 (macOS) and later: no associative array, no case
# conversion expansion, no here-string (Bash 3.2 writes them to a temporary
# file), no GNU-only option. BSD tools only.

unset CDPATH

# A "loaded" guard coming from the environment would skip the contracts: they
# are always loaded from this repository. (Readonly when already loaded by a
# caller that sources this file: the error is then irrelevant.)
unset CBS_FLUTTER_QUAL_CONTRACT_LOADED CBS_ISOLATION_CONTRACT_LOADED CBS_WORKTREE_CONTRACT_LOADED 2>/dev/null || true

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
unset GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_PREFIX
# GIT_CONFIG_PARAMETERS (what "git -c" writes) wins over GIT_CONFIG_COUNT: an
# inherited value could re-enable core.fsmonitor / core.hooksPath.
unset GIT_CONFIG_PARAMETERS
# Child bash processes (isolation manager, supervisor) must not read a startup
# file named by the caller.
unset BASH_ENV
export GIT_TERMINAL_PROMPT=0
export GIT_NO_LAZY_FETCH=1
export GIT_OPTIONAL_LOCKS=0

# Sentinel read back by "git config --get": proves that this Git applies
# GIT_CONFIG_COUNT (an older Git ignores it silently). The value changes at
# every load, so no configuration file can pre-date it.
CBS_FLUTTER_QUAL_PREFLIGHT_GIT_PROBE_KEY="cbs.preflightconfigcount"
CBS_FLUTTER_QUAL_PREFLIGHT_GIT_PROBE_VALUE="applied-$$-$RANDOM-$RANDOM"

# The isolation manager runs raw git commands: neutralise, at the highest
# config precedence (git >= 2.31), the repository settings that execute code.
export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
export GIT_CONFIG_KEY_2=core.untrackedCache GIT_CONFIG_VALUE_2=false
export GIT_CONFIG_KEY_3="$CBS_FLUTTER_QUAL_PREFLIGHT_GIT_PROBE_KEY"
export GIT_CONFIG_VALUE_3="$CBS_FLUTTER_QUAL_PREFLIGHT_GIT_PROBE_VALUE"
export LC_ALL=C

CBS_FLUTTER_QUAL_PREFLIGHT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CBS_FLUTTER_QUAL_PREFLIGHT_ROOT="$(cd "$CBS_FLUTTER_QUAL_PREFLIGHT_DIR/../../.." 2>/dev/null && pwd)"

if [[ -z "$CBS_FLUTTER_QUAL_PREFLIGHT_DIR" || ! -f "$CBS_FLUTTER_QUAL_PREFLIGHT_DIR/contract.sh" ]]; then
    echo "CBS_FLUTTER_QUAL_ERROR=CONTRACT_UNAVAILABLE" >&2
    return 1 2>/dev/null || exit 1
fi

# shellcheck source=/dev/null
source "$CBS_FLUTTER_QUAL_PREFLIGHT_DIR/contract.sh"

# Fixed locations, derived from this file only (never from the request).
CBS_FLUTTER_QUAL_PREFLIGHT_ISOLATION_MANAGER="$CBS_FLUTTER_QUAL_PREFLIGHT_ROOT/cbs/worktree/isolation_manager.sh"
CBS_FLUTTER_QUAL_PREFLIGHT_STACK_MANIFEST="$CBS_FLUTTER_QUAL_PREFLIGHT_ROOT/stacks/flutter/stack.env"

# Emission order of the checks.
CBS_FLUTTER_QUAL_PREFLIGHT_CHECKS="PARAMETERS EVIDENCE_ROOT GIT_CONFIG_GUARD OWNERSHIP COMMIT ORIGIN DETACHED_HEAD GIT_STATE STACK_REFERENCE FLUTTER DART XCODE SDK_IPHONEOS SDK_IPHONESIMULATOR SIMCTL SIMULATOR"

# Upper bound of the output kept from one probe (the request may lower it).
CBS_FLUTTER_QUAL_PREFLIGHT_OUTPUT_MAX=1048576

# A newline held in a variable: patterns written with it behave the same in
# every Bash version.
CBS_FLUTTER_QUAL_PREFLIGHT_NL="
"

# --- State ---------------------------------------------------------------------

_cbs_flutter_qual_pf_reset() {
    local name

    for name in $CBS_FLUTTER_QUAL_PREFLIGHT_CHECKS; do
        printf -v "PF_R_$name" '%s' "NOT_RUN"
        printf -v "PF_X_$name" '%s' "NOT_EXECUTED"
        printf -v "PF_T_$name" '%s' ""
    done

    PF_REJECTED_KEY=""
    PF_ISOLATION_REASON=""
    PF_QUALIFICATION_ID=""
    PF_COMMIT_OBSERVED=""
    PF_EVIDENCE_STATE=""
    PF_FLUTTER_REQUIRED=""
    PF_XCODE_MINIMUM=""
    PF_FLUTTER_VERSION=""
    PF_GIT_VERSION=""
    PF_DART_VERSION=""
    PF_XCODE_VERSION=""
    PF_IPHONEOS_SDK=""
    PF_IPHONESIMULATOR_SDK=""
    PF_SIMULATOR_STATE=""
    PF_VERSION=""
    PF_RUN_OUT=""
    PF_RUN_RC=0
    PF_RUN_TIMED_OUT=0
    PF_OUTPUT_CAP="$CBS_FLUTTER_QUAL_PREFLIGHT_OUTPUT_MAX"
}

# Arguments: CHECK
_cbs_flutter_qual_pf_pass() {
    printf -v "PF_R_$1" '%s' "PASS"
    printf -v "PF_X_$1" '%s' ""
    printf -v "PF_T_$1" '%s' ""
}

# Arguments: CHECK REASON [TOOL_RC]
# The result is the class of the reason (BLOCKED or FAIL): they never diverge.
_cbs_flutter_qual_pf_refuse() {
    local result

    result="$(cbs_flutter_qual_result_for_reason "$2")" || result="BLOCKED"

    printf -v "PF_R_$1" '%s' "$result"
    printf -v "PF_X_$1" '%s' "$2"
    printf -v "PF_T_$1" '%s' "${3:-}"
}

# Arguments: CHECK. Not requested: SKIPPED, never PASS.
_cbs_flutter_qual_pf_skip() {
    printf -v "PF_R_$1" '%s' "SKIPPED"
    printf -v "PF_X_$1" '%s' "NOT_SELECTED"
    printf -v "PF_T_$1" '%s' ""
}

# Arguments: CHECK. Prints the result of the check.
_cbs_flutter_qual_pf_result() {
    local variable="PF_R_$1"

    printf '%s' "${!variable}"
}

# --- Bounded, read-only probes -----------------------------------------------

# Prints the absolute path of an executable looked up in the absolute entries
# of PATH. An empty or relative entry (the current directory) is never used.
# Argument: tool name (fixed by this file). Fails when not found.
_cbs_flutter_qual_pf_find_tool() {
    local name="$1"
    local rest="${PATH:-}:"
    local dir

    while [[ -n "$rest" ]]; do
        dir="${rest%%:*}"
        rest="${rest#*:}"

        case "$dir" in
            /*)
                if [[ -f "$dir/$name" && -x "$dir/$name" ]]; then
                    printf '%s' "$dir/$name"
                    return 0
                fi
                ;;
        esac
    done

    return 1
}

# Supervisor: fixed text, run by "bash -c" with the arguments TIMEOUT COMMAND
# [ARG...] as data. The command runs in its own process group (set -m); the
# timer is a second group that only sleeps, then sends USR1 to this process.
#   - USR1: when the job table still lists the command as running, it receives
#     TERM, then KILL one second later; the timeout is recorded;
#   - end of the command (or INT / TERM / HUP received here): the timer group
#     is killed and reaped, the remaining members of the command group are
#     killed, and only then the trailer "CBS_PF_RUN <status> <timed_out>" is
#     printed.
# No signal is sent from the timer to the command, and a command that is no
# longer running is never signalled from a signal handler.
CBS_FLUTTER_QUAL_PREFLIGHT_SUPERVISOR='
exec 2>/dev/null
limit=$1
shift
child=""
timer=""
timed_out=0
fired=0

running() {
    local pid

    for pid in $(jobs -pr); do
        [ "$pid" = "$1" ] && return 0
    done

    return 1
}

finish() {
    trap "" USR1

    if [ -n "$timer" ]; then
        kill -KILL -- "-$timer"
        wait "$timer"
        timer=""
    fi

    if [ -n "$child" ]; then
        kill -KILL -- "-$child"
    fi
}

on_timeout() {
    fired=1

    if [ -n "$child" ] && running "$child"; then
        timed_out=1
        kill -TERM -- "-$child"
        sleep 1
        kill -KILL -- "-$child"
    fi
}

on_interrupt() {
    trap "" INT TERM HUP USR1
    finish
    exit 130
}

trap on_interrupt INT TERM HUP
trap on_timeout USR1
set -m

( cd / && LC_ALL=C exec "$@" ) </dev/null 2>&1 &
child=$!

( sleep "$limit"; kill -USR1 "$$"; exec sleep 86400 ) </dev/null >/dev/null 2>&1 &
timer=$!

status=255
while :; do
    fired=0
    wait "$child"
    status=$?
    [ "$fired" -eq 1 ] || break
done

finish
printf "\nCBS_PF_RUN %s %s\n" "$status" "$timed_out"
'

# Arguments: TIMEOUT_SECONDS COMMAND [ARG...]
# Runs COMMAND from "/", without input, stdout and stderr merged, in its own
# process group, under the supervisor above. Sets PF_RUN_OUT (bounded),
# PF_RUN_RC and PF_RUN_TIMED_OUT (reported by the supervisor).
# No file is created: the output travels through a pipe.
# Known limit: a process that leaves the process group (setsid) and keeps the
# pipe open is out of reach and would keep this call waiting.
_cbs_flutter_qual_pf_run() {
    local limit="$1"
    local raw
    local trailer
    local trailer_pattern='^CBS_PF_RUN ([0-9]{1,3}) ([01])$'

    shift

    raw="$("${BASH:-bash}" -c "$CBS_FLUTTER_QUAL_PREFLIGHT_SUPERVISOR" \
        cbs-preflight-supervisor "$limit" "$@" </dev/null 2>/dev/null)"

    # The last line is written by the supervisor, after the command and its
    # group are gone: output of the tool cannot replace it.
    trailer="${raw##*"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
    PF_RUN_OUT="${raw%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"*}"
    PF_RUN_OUT="${PF_RUN_OUT%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
    PF_RUN_OUT="${PF_RUN_OUT:0:$PF_OUTPUT_CAP}"

    PF_RUN_RC=255
    PF_RUN_TIMED_OUT=0

    if [[ "$trailer" =~ $trailer_pattern ]]; then
        PF_RUN_RC="${BASH_REMATCH[1]}"
        PF_RUN_TIMED_OUT="${BASH_REMATCH[2]}"
    fi
}

# Arguments: CHECK NONZERO_REASON TOOL [ARG...]
# Looks the tool up, runs it once and classifies the outcome on the check:
#   absent from PATH      TOOL_UNAVAILABLE
#   timeout               TIMEOUT
#   non-zero status       NONZERO_REASON (COMMAND_FAILED also keeps the status)
# Succeeds (PF_RUN_OUT is set) only when the tool ran and exited with 0.
_cbs_flutter_qual_pf_probe() {
    local check="$1"
    local nonzero_reason="$2"
    local tool="$3"
    local path

    shift 3

    if ! path="$(_cbs_flutter_qual_pf_find_tool "$tool")"; then
        _cbs_flutter_qual_pf_refuse "$check" "TOOL_UNAVAILABLE"
        return 1
    fi

    _cbs_flutter_qual_pf_run "$PF_TIMEOUT" "$path" "$@"

    if [[ "$PF_RUN_TIMED_OUT" -eq 1 ]]; then
        _cbs_flutter_qual_pf_refuse "$check" "TIMEOUT"
        return 1
    fi

    if [[ "$PF_RUN_RC" -ne 0 ]]; then
        if [[ "$nonzero_reason" == "COMMAND_FAILED" ]]; then
            _cbs_flutter_qual_pf_refuse "$check" "COMMAND_FAILED" "$PF_RUN_RC"
        else
            _cbs_flutter_qual_pf_refuse "$check" "$nonzero_reason"
        fi

        return 1
    fi

    return 0
}

# Arguments: PATTERN. The pattern has one capture group.
# Sets PF_VERSION from the first matching line of PF_RUN_OUT. No here-string.
_cbs_flutter_qual_pf_first_match() {
    local pattern="$1"
    local rest="$PF_RUN_OUT"
    local line

    PF_VERSION=""

    while [[ -n "$rest" ]]; do
        line="${rest%%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"*}"

        if [[ "$rest" == *"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"* ]]; then
            rest="${rest#*"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
        else
            rest=""
        fi

        if [[ "$line" =~ $pattern ]]; then
            PF_VERSION="${BASH_REMATCH[1]}"
            return 0
        fi
    done

    return 1
}

# --- Reference versions (trusted manifest of this repository) -----------------

# Arguments: KEY PATTERN. Prints the value of KEY in the stack manifest.
# The manifest is read as text: one exact "KEY=" line, a value matching the
# pattern, no duplicate. Nothing in it is sourced, expanded or evaluated.
_cbs_flutter_qual_pf_stack_value() {
    local key="$1"
    local pattern="$2"
    local file="$CBS_FLUTTER_QUAL_PREFLIGHT_STACK_MANIFEST"
    local line
    local value=""
    local found=0

    [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            "$key="*)
                [[ "$found" -eq 0 ]] || return 1
                found=1
                value="${line#*=}"
                ;;
        esac
    done < "$file"

    [[ "$found" -eq 1 && "$value" =~ $pattern ]] || return 1

    printf '%s' "$value"
}

# --- Checks --------------------------------------------------------------------

_cbs_flutter_qual_pf_check_evidence_root() {
    local evidence_root="$1"

    if [[ -e "$evidence_root" || -L "$evidence_root" ]]; then
        if cbs_flutter_qual_dir_is_canonical "$evidence_root"; then
            PF_EVIDENCE_STATE="DIRECTORY"
            _cbs_flutter_qual_pf_pass "EVIDENCE_ROOT"
        else
            PF_EVIDENCE_STATE="REFUSED"
            _cbs_flutter_qual_pf_refuse "EVIDENCE_ROOT" "PATH_NOT_ALLOWED"
        fi

        return 0
    fi

    # Not created here: PREFLIGHT writes nothing.
    PF_EVIDENCE_STATE="ABSENT"
    _cbs_flutter_qual_pf_pass "EVIDENCE_ROOT"
}

# The isolation manager runs git on the source repository and on the isolated
# checkout, whose configuration is not trusted. This check runs first, from "/"
# (no repository, so no repository configuration is read), and accepts the Git
# only when it really applies GIT_CONFIG_COUNT:
#   - "git --version" names a version >= 2.31 (first release that reads it);
#   - the sentinel given through GIT_CONFIG_COUNT is read back as is. A Git that
#     ignores GIT_CONFIG_COUNT (older, or not honouring it) answers nothing.
# Returns 0 when the Git is accepted.
_cbs_flutter_qual_pf_check_git() {
    local major
    local minor
    local rest

    _cbs_flutter_qual_pf_probe "GIT_CONFIG_GUARD" "COMMAND_FAILED" git --version || return 1

    if ! _cbs_flutter_qual_pf_first_match '^git version ([0-9]{1,4}\.[0-9]{1,4}(\.[0-9]{1,4})?)'; then
        _cbs_flutter_qual_pf_refuse "GIT_CONFIG_GUARD" "TOOLCHAIN_INCOMPATIBLE"
        return 1
    fi

    PF_GIT_VERSION="$PF_VERSION"
    major="${PF_GIT_VERSION%%.*}"
    rest="${PF_GIT_VERSION#*.}"
    minor="${rest%%.*}"
    major="$((10#$major))"
    minor="$((10#$minor))"

    if [[ "$major" -lt 2 || ( "$major" -eq 2 && "$minor" -lt 31 ) ]]; then
        _cbs_flutter_qual_pf_refuse "GIT_CONFIG_GUARD" "TOOLCHAIN_INCOMPATIBLE"
        return 1
    fi

    _cbs_flutter_qual_pf_probe "GIT_CONFIG_GUARD" "TOOLCHAIN_INCOMPATIBLE" git config --get "$CBS_FLUTTER_QUAL_PREFLIGHT_GIT_PROBE_KEY" || return 1

    if [[ "$PF_RUN_OUT" != "$CBS_FLUTTER_QUAL_PREFLIGHT_GIT_PROBE_VALUE" ]]; then
        _cbs_flutter_qual_pf_refuse "GIT_CONFIG_GUARD" "TOOLCHAIN_INCOMPATIBLE"
        return 1
    fi

    _cbs_flutter_qual_pf_pass "GIT_CONFIG_GUARD"
}

# Arguments: ISOLATION_REASON. Prints the check that carries the refusal.
_cbs_flutter_qual_pf_isolation_check_for() {
    case "${1:-}" in
        HEAD_MISMATCH|COMMIT_MISMATCH|COMMIT_*) printf '%s' "COMMIT" ;;
        NOT_DETACHED) printf '%s' "DETACHED_HEAD" ;;
        WORKTREE_DIRTY|WORKTREE_STATUS_UNKNOWN) printf '%s' "GIT_STATE" ;;
        ORIGIN_*) printf '%s' "ORIGIN" ;;
        *) printf '%s' "OWNERSHIP" ;;
    esac
}

# Arguments: ID SOURCE ROOT COMMIT EXPECTED_ORIGIN
# Verifies the isolated checkout with the CBS isolation manager (read-only).
# Returns 0 when every isolation check passed.
_cbs_flutter_qual_pf_check_isolation() {
    local id="$1"
    local source_repository="$2"
    local root="$3"
    local commit="$4"
    local expected_origin="$5"
    local manager="$CBS_FLUTTER_QUAL_PREFLIGHT_ISOLATION_MANAGER"
    local rest
    local line
    local key
    local value
    local iso_result=""
    local iso_reason=""
    local iso_rc=""
    local iso_version=""
    local iso_expected=""
    local iso_observed=""
    local iso_origin=""
    local manager_rc
    local check

    if [[ ! -f "$manager" ]]; then
        PF_ISOLATION_REASON="MANAGER_UNAVAILABLE"
        _cbs_flutter_qual_pf_refuse "OWNERSHIP" "ISOLATION_REJECTED"
        return 1
    fi

    _cbs_flutter_qual_pf_run "$PF_TIMEOUT" "${BASH:-bash}" "$manager" verify \
        "$id" "$source_repository" "$root"
    manager_rc="$PF_RUN_RC"

    if [[ "$PF_RUN_TIMED_OUT" -eq 1 ]]; then
        _cbs_flutter_qual_pf_refuse "OWNERSHIP" "TIMEOUT"
        return 1
    fi

    # Strict parser: known keys only, first occurrence wins, never evaluated.
    rest="$PF_RUN_OUT"

    while [[ -n "$rest" ]]; do
        line="${rest%%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"*}"

        if [[ "$rest" == *"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"* ]]; then
            rest="${rest#*"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
        else
            rest=""
        fi

        case "$line" in
            CBS_FLUTTER_ISOLATION_*=*) ;;
            *) continue ;;
        esac

        key="${line%%=*}"
        value="${line#*=}"

        case "$key" in
            CBS_FLUTTER_ISOLATION_VERSION) [[ -n "$iso_version" ]] || iso_version="$value" ;;
            CBS_FLUTTER_ISOLATION_RESULT) [[ -n "$iso_result" ]] || iso_result="$value" ;;
            CBS_FLUTTER_ISOLATION_REASON) [[ -n "$iso_reason" ]] || iso_reason="$value" ;;
            CBS_FLUTTER_ISOLATION_RC) [[ -n "$iso_rc" ]] || iso_rc="$value" ;;
            CBS_FLUTTER_ISOLATION_COMMIT_EXPECTED) [[ -n "$iso_expected" ]] || iso_expected="$value" ;;
            CBS_FLUTTER_ISOLATION_COMMIT_OBSERVED) [[ -n "$iso_observed" ]] || iso_observed="$value" ;;
            CBS_FLUTTER_ISOLATION_ORIGIN) [[ -n "$iso_origin" ]] || iso_origin="$value" ;;
        esac
    done

    if [[ "$iso_result" != "PASS" ]]; then
        # The reason comes from the isolation manager; it is printed only when
        # it has the form of a closed identifier.
        if [[ "$iso_reason" =~ ^[A-Z][A-Z0-9_]{0,63}$ ]]; then
            PF_ISOLATION_REASON="$iso_reason"
        else
            PF_ISOLATION_REASON="OUTPUT_INVALID"
        fi

        check="$(_cbs_flutter_qual_pf_isolation_check_for "$PF_ISOLATION_REASON")"
        _cbs_flutter_qual_pf_refuse "$check" "ISOLATION_REJECTED"
        return 1
    fi

    # A PASS is accepted only when the whole structured answer agrees.
    if [[ "$manager_rc" -ne 0 || "$iso_rc" != "0" || "$iso_reason" != "NONE" || "$iso_version" != "$CBS_ISOLATION_CONTRACT_VERSION" ]]; then
        PF_ISOLATION_REASON="OUTPUT_INVALID"
        _cbs_flutter_qual_pf_refuse "OWNERSHIP" "ISOLATION_REJECTED"
        return 1
    fi

    # Verified by the manager: CBS proof, association, detached, clean.
    _cbs_flutter_qual_pf_pass "OWNERSHIP"
    _cbs_flutter_qual_pf_pass "DETACHED_HEAD"
    _cbs_flutter_qual_pf_pass "GIT_STATE"

    if cbs_flutter_qual_commit_valid "$iso_observed"; then
        PF_COMMIT_OBSERVED="$iso_observed"
    fi

    # The checkout must be exactly the commit that was asked for.
    if [[ "$iso_expected" != "$commit" || "$iso_observed" != "$commit" ]]; then
        PF_ISOLATION_REASON="COMMIT_MISMATCH"
        _cbs_flutter_qual_pf_refuse "COMMIT" "ISOLATION_REJECTED"
        return 1
    fi

    _cbs_flutter_qual_pf_pass "COMMIT"

    # ... and be bound to the expected origin (the proof records it redacted;
    # the contract refuses an expected origin that carries credentials).
    if [[ "$iso_origin" != "$expected_origin" ]]; then
        PF_ISOLATION_REASON="ORIGIN_MISMATCH"
        _cbs_flutter_qual_pf_refuse "ORIGIN" "ISOLATION_REJECTED"
        return 1
    fi

    _cbs_flutter_qual_pf_pass "ORIGIN"

    return 0
}

_cbs_flutter_qual_pf_check_stack_reference() {
    PF_FLUTTER_REQUIRED="$(_cbs_flutter_qual_pf_stack_value \
        "CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION" \
        '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$')" || PF_FLUTTER_REQUIRED=""
    PF_XCODE_MINIMUM="$(_cbs_flutter_qual_pf_stack_value \
        "CBS_STACK_MANAGED_TOOLCHAIN_XCODE_VERSION" \
        '^[1-9][0-9]{0,2}$')" || PF_XCODE_MINIMUM=""

    if [[ -z "$PF_FLUTTER_REQUIRED" || -z "$PF_XCODE_MINIMUM" ]]; then
        PF_FLUTTER_REQUIRED=""
        PF_XCODE_MINIMUM=""
        _cbs_flutter_qual_pf_refuse "STACK_REFERENCE" "TOOLCHAIN_INCOMPATIBLE"
        return 1
    fi

    _cbs_flutter_qual_pf_pass "STACK_REFERENCE"
}

_cbs_flutter_qual_pf_check_flutter() {
    local version_pattern='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$'

    _cbs_flutter_qual_pf_probe "FLUTTER" "COMMAND_FAILED" flutter --version || return 0

    if ! _cbs_flutter_qual_pf_first_match '^Flutter[[:space:]]+([0-9][0-9A-Za-z.+-]*)' ||
        [[ ! "$PF_VERSION" =~ $version_pattern ]]; then
        _cbs_flutter_qual_pf_refuse "FLUTTER" "TOOLCHAIN_INCOMPATIBLE"
        return 0
    fi

    PF_FLUTTER_VERSION="$PF_VERSION"

    if [[ "$PF_FLUTTER_VERSION" != "$PF_FLUTTER_REQUIRED" ]]; then
        _cbs_flutter_qual_pf_refuse "FLUTTER" "TOOLCHAIN_INCOMPATIBLE"
        return 0
    fi

    _cbs_flutter_qual_pf_pass "FLUTTER"
}

_cbs_flutter_qual_pf_check_dart() {
    local version_pattern='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$'

    _cbs_flutter_qual_pf_probe "DART" "COMMAND_FAILED" dart --version || return 0

    if ! _cbs_flutter_qual_pf_first_match 'Dart SDK version:[[:space:]]+([0-9][0-9A-Za-z.+-]*)' &&
        ! _cbs_flutter_qual_pf_first_match '^Dart[[:space:]]+([0-9][0-9A-Za-z.+-]*)'; then
        _cbs_flutter_qual_pf_refuse "DART" "TOOLCHAIN_INCOMPATIBLE"
        return 0
    fi

    if [[ ! "$PF_VERSION" =~ $version_pattern ]]; then
        _cbs_flutter_qual_pf_refuse "DART" "TOOLCHAIN_INCOMPATIBLE"
        return 0
    fi

    PF_DART_VERSION="$PF_VERSION"
    _cbs_flutter_qual_pf_pass "DART"
}

_cbs_flutter_qual_pf_check_xcode() {
    local version_pattern='^[0-9]+(\.[0-9]+){0,2}$'
    local major

    _cbs_flutter_qual_pf_probe "XCODE" "COMMAND_FAILED" xcodebuild -version || return 0

    if ! _cbs_flutter_qual_pf_first_match '^Xcode[[:space:]]+([0-9][0-9.]*)' ||
        [[ ! "$PF_VERSION" =~ $version_pattern ]]; then
        _cbs_flutter_qual_pf_refuse "XCODE" "TOOLCHAIN_INCOMPATIBLE"
        return 0
    fi

    PF_XCODE_VERSION="$PF_VERSION"
    major="${PF_XCODE_VERSION%%.*}"

    # Same rule as the Xcode provider: the major version is at least the
    # version required by the stack.
    if [[ "$((10#$major))" -lt "$((10#$PF_XCODE_MINIMUM))" ]]; then
        _cbs_flutter_qual_pf_refuse "XCODE" "TOOLCHAIN_INCOMPATIBLE"
        return 0
    fi

    _cbs_flutter_qual_pf_pass "XCODE"
}

# Arguments: CHECK SDK_NAME. Sets PF_VERSION on success.
_cbs_flutter_qual_pf_check_sdk() {
    local check="$1"
    local sdk="$2"
    local version_pattern='^[0-9]+(\.[0-9]+){1,2}$'
    local text

    # A missing SDK is the answer to the question, not a failure to ask it.
    _cbs_flutter_qual_pf_probe "$check" "TOOLCHAIN_INCOMPATIBLE" xcrun --sdk "$sdk" --show-sdk-version || return 0

    text="$PF_RUN_OUT"
    text="${text%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"

    if [[ ! "$text" =~ $version_pattern ]]; then
        _cbs_flutter_qual_pf_refuse "$check" "TOOLCHAIN_INCOMPATIBLE"
        return 0
    fi

    PF_VERSION="$text"
    _cbs_flutter_qual_pf_pass "$check"
}

_cbs_flutter_qual_pf_check_simctl() {
    _cbs_flutter_qual_pf_probe "SIMCTL" "TOOL_UNAVAILABLE" xcrun --find simctl || return 0

    if [[ -z "$PF_RUN_OUT" ]]; then
        _cbs_flutter_qual_pf_refuse "SIMCTL" "TOOL_UNAVAILABLE"
        return 0
    fi

    _cbs_flutter_qual_pf_pass "SIMCTL"
}

# Argument: UDID. Looks the simulator up in "xcrun simctl list devices"
# (read-only: nothing is created, booted or erased). The device must be listed
# under an iOS runtime and must not be marked unavailable. Its state is
# observed, never changed: BOOTED, SHUTDOWN or TRANSITIONAL.
_cbs_flutter_qual_pf_check_simulator() {
    local udid
    local text
    local rest
    local line
    local section=""
    local state=""
    local found=0
    local usable=0

    udid="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"

    _cbs_flutter_qual_pf_probe "SIMULATOR" "COMMAND_FAILED" xcrun simctl list devices || return 0

    text="$(printf '%s\n' "$PF_RUN_OUT" | tr '[:lower:]' '[:upper:]')"
    rest="$text"

    while [[ -n "$rest" ]]; do
        line="${rest%%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"*}"

        if [[ "$rest" == *"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"* ]]; then
            rest="${rest#*"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
        else
            rest=""
        fi

        case "$line" in
            "-- "*)
                section="$line"
                continue
                ;;
        esac

        case "$line" in
            *"($udid)"*)
                found=1
                state="${line#*"($udid)"}"
                state="${state# }"

                case "$state" in
                    "("*) state="${state#(}"; state="${state%%)*}" ;;
                    *) state="" ;;
                esac

                case "$section" in
                    "-- IOS "*)
                        case "$line" in
                            *"(UNAVAILABLE"*) usable=0 ;;
                            *) usable=1 ;;
                        esac
                        ;;
                esac

                break
                ;;
        esac
    done

    if [[ "$found" -ne 1 || "$usable" -ne 1 ]]; then
        _cbs_flutter_qual_pf_refuse "SIMULATOR" "SIMULATOR_UNAVAILABLE"
        return 0
    fi

    case "$state" in
        BOOTED) PF_SIMULATOR_STATE="BOOTED" ;;
        SHUTDOWN) PF_SIMULATOR_STATE="SHUTDOWN" ;;
        *) PF_SIMULATOR_STATE="TRANSITIONAL" ;;
    esac

    _cbs_flutter_qual_pf_pass "SIMULATOR"
}

# --- Structured output -------------------------------------------------------

# Prints a fact only when its value has the shape of a version or of a closed
# word: a value from a tool is never printed as free text.
# Arguments: NAME VALUE PATTERN
_cbs_flutter_qual_pf_fact() {
    local name="$1"
    local value="$2"
    local pattern="$3"

    [[ -n "$value" && "$value" =~ $pattern ]] || return 0

    printf 'CBS_FLUTTER_QUAL_PREFLIGHT_%s=%s\n' "$name" "$value"
}

# Prints the checks, the facts and the final structured result. Returns the
# contract return code of the overall reason (0 for PASS).
_cbs_flutter_qual_pf_conclude() {
    local name
    local result
    local reason
    local results=""
    local overall
    local overall_reason=""
    local overall_tool_rc=""
    local variable
    local version_pattern='^[0-9]+(\.[0-9]+){0,3}([-+][0-9A-Za-z.+-]+)?$'

    for name in $CBS_FLUTTER_QUAL_PREFLIGHT_CHECKS; do
        variable="PF_R_$name"
        result="${!variable}"
        variable="PF_X_$name"
        reason="${!variable}"

        printf 'CBS_FLUTTER_QUAL_PREFLIGHT_CHECK_%s=%s\n' "$name" "$result"

        if [[ "$result" != "PASS" && -n "$reason" ]]; then
            printf 'CBS_FLUTTER_QUAL_PREFLIGHT_CHECK_%s_REASON=%s\n' "$name" "$reason"
        fi

        results="$results $result"
    done

    # No result of the list is ever converted: FAIL, then BLOCKED, then NOT_RUN
    # win over PASS; SKIPPED alone is not a PASS.
    # shellcheck disable=SC2086
    overall="$(cbs_flutter_qual_aggregate $results)" || overall="BLOCKED"

    if [[ "$overall" != "PASS" ]]; then
        for name in $CBS_FLUTTER_QUAL_PREFLIGHT_CHECKS; do
            variable="PF_R_$name"
            [[ "${!variable}" == "$overall" ]] || continue

            variable="PF_X_$name"
            overall_reason="${!variable}"
            variable="PF_T_$name"
            overall_tool_rc="${!variable}"
            break
        done

        if [[ -z "$overall_reason" ]] ||
            ! cbs_flutter_qual_result_reason_consistent "$overall" "$overall_reason"; then
            overall_reason="NOT_EXECUTED"
            overall="NOT_RUN"
        fi
    fi

    [[ -z "$PF_REJECTED_KEY" ]] ||
        printf 'CBS_FLUTTER_QUAL_PREFLIGHT_REJECTED_KEY=%s\n' "$PF_REJECTED_KEY"

    if [[ -n "$PF_QUALIFICATION_ID" ]] && cbs_flutter_qual_id_valid "$PF_QUALIFICATION_ID"; then
        printf 'CBS_FLUTTER_QUAL_PREFLIGHT_QUALIFICATION_ID=%s\n' "$PF_QUALIFICATION_ID"
    fi

    if [[ -n "$PF_ISOLATION_REASON" ]]; then
        _cbs_flutter_qual_pf_fact "ISOLATION_REASON" "$PF_ISOLATION_REASON" '^[A-Z][A-Z0-9_]{0,63}$'
    fi

    if [[ -n "$PF_COMMIT_OBSERVED" ]] && cbs_flutter_qual_commit_valid "$PF_COMMIT_OBSERVED"; then
        printf 'CBS_FLUTTER_QUAL_PREFLIGHT_COMMIT_OBSERVED=%s\n' "$PF_COMMIT_OBSERVED"
    fi

    _cbs_flutter_qual_pf_fact "EVIDENCE_ROOT_STATE" "$PF_EVIDENCE_STATE" '^(ABSENT|DIRECTORY|REFUSED)$'
    _cbs_flutter_qual_pf_fact "GIT_VERSION" "$PF_GIT_VERSION" "$version_pattern"
    _cbs_flutter_qual_pf_fact "FLUTTER_REQUIRED_VERSION" "$PF_FLUTTER_REQUIRED" "$version_pattern"
    _cbs_flutter_qual_pf_fact "XCODE_MINIMUM_MAJOR" "$PF_XCODE_MINIMUM" '^[0-9]{1,3}$'
    _cbs_flutter_qual_pf_fact "FLUTTER_VERSION" "$PF_FLUTTER_VERSION" "$version_pattern"
    _cbs_flutter_qual_pf_fact "DART_VERSION" "$PF_DART_VERSION" "$version_pattern"
    _cbs_flutter_qual_pf_fact "XCODE_VERSION" "$PF_XCODE_VERSION" "$version_pattern"
    _cbs_flutter_qual_pf_fact "IPHONEOS_SDK_VERSION" "$PF_IPHONEOS_SDK" "$version_pattern"
    _cbs_flutter_qual_pf_fact "IPHONESIMULATOR_SDK_VERSION" "$PF_IPHONESIMULATOR_SDK" "$version_pattern"

    # Available is not operational: the simulator is never booted, so its
    # readiness is not observed.
    if [[ "$(_cbs_flutter_qual_pf_result SIMULATOR)" == "PASS" ]]; then
        _cbs_flutter_qual_pf_fact "SIMULATOR_STATE" "$PF_SIMULATOR_STATE" '^(BOOTED|SHUTDOWN|TRANSITIONAL)$'
        printf 'CBS_FLUTTER_QUAL_PREFLIGHT_SIMULATOR_OPERATIONAL=NOT_OBSERVED\n'
    fi

    if [[ "$overall" == "FAIL" && "$overall_reason" == "COMMAND_FAILED" && -n "$overall_tool_rc" ]]; then
        cbs_flutter_qual_emit_operation "PREFLIGHT" "$overall" "$overall_reason" "$overall_tool_rc" ||
            return $?
    else
        cbs_flutter_qual_emit_operation "PREFLIGHT" "$overall" "$overall_reason" ||
            return $?
    fi

    cbs_flutter_qual_emit_result "$overall" "$overall_reason" || return $?

    cbs_flutter_qual_rc_for_reason "$overall_reason" >/dev/null
    return "$(cbs_flutter_qual_rc_for_reason "$overall_reason")"
}

# --- Entry ---------------------------------------------------------------------

# Arguments: KEY=VALUE... (the request).
cbs_flutter_qual_preflight() {
    local reason
    local actions
    local source_repository
    local isolation_id
    local isolation_root
    local evidence_root
    local expected_origin
    local commit
    local simulator_udid=""

    _cbs_flutter_qual_pf_reset
    PF_TIMEOUT=1

    if [[ "$#" -eq 0 ]]; then
        _cbs_flutter_qual_pf_refuse "PARAMETERS" "USAGE"
        _cbs_flutter_qual_pf_conclude
        return $?
    fi

    # ---- 1. request

    if ! cbs_flutter_qual_validate_request "$@"; then
        reason="$CBS_FLUTTER_QUAL_VALIDATION_REASON"
        PF_REJECTED_KEY="$CBS_FLUTTER_QUAL_VALIDATION_KEY"

        cbs_flutter_qual_reason_is_valid "$reason" || reason="INPUT_INVALID"

        _cbs_flutter_qual_pf_refuse "PARAMETERS" "$reason"
        _cbs_flutter_qual_pf_conclude
        return $?
    fi

    actions="$(cbs_flutter_qual_entries_get actions "$@")"

    # This operation is the PREFLIGHT: it must have been selected.
    case ",$actions," in
        *,preflight,*) ;;
        *)
            PF_REJECTED_KEY="actions"
            _cbs_flutter_qual_pf_refuse "PARAMETERS" "ACTION_NOT_ALLOWED"
            _cbs_flutter_qual_pf_conclude
            return $?
            ;;
    esac

    PF_QUALIFICATION_ID="$(cbs_flutter_qual_entries_get qualification_id "$@")"
    isolation_id="$(cbs_flutter_qual_entries_get isolation_id "$@")"
    source_repository="$(cbs_flutter_qual_entries_get source_repository "$@")"
    expected_origin="$(cbs_flutter_qual_entries_get expected_origin "$@")"
    commit="$(cbs_flutter_qual_entries_get commit "$@")"
    isolation_root="$(cbs_flutter_qual_entries_get isolation_root "$@")"
    evidence_root="$(cbs_flutter_qual_entries_get evidence_root "$@")"
    PF_TIMEOUT="$(cbs_flutter_qual_entries_get timeout_seconds "$@")"
    PF_OUTPUT_CAP="$(cbs_flutter_qual_entries_get log_max_bytes "$@")"
    simulator_udid="$(cbs_flutter_qual_entries_get simulator_udid "$@" || true)"

    PF_TIMEOUT="$((10#$PF_TIMEOUT))"
    PF_OUTPUT_CAP="$((10#$PF_OUTPUT_CAP))"

    if [[ "$PF_OUTPUT_CAP" -gt "$CBS_FLUTTER_QUAL_PREFLIGHT_OUTPUT_MAX" ]]; then
        PF_OUTPUT_CAP="$CBS_FLUTTER_QUAL_PREFLIGHT_OUTPUT_MAX"
    fi

    _cbs_flutter_qual_pf_pass "PARAMETERS"

    # ---- 2. evidence root (never created here)

    _cbs_flutter_qual_pf_check_evidence_root "$evidence_root"

    if [[ "$(_cbs_flutter_qual_pf_result EVIDENCE_ROOT)" != "PASS" ]]; then
        _cbs_flutter_qual_pf_conclude
        return $?
    fi

    # ---- 3. Git: no git command touches a repository with a Git that would
    # ignore the neutralisation of the executable configuration

    if ! _cbs_flutter_qual_pf_check_git; then
        _cbs_flutter_qual_pf_conclude
        return $?
    fi

    # ---- 4. isolated checkout: nothing else runs when it is not accepted

    if ! _cbs_flutter_qual_pf_check_isolation "$isolation_id" "$source_repository" \
        "$isolation_root" "$commit" "$expected_origin"; then
        _cbs_flutter_qual_pf_conclude
        return $?
    fi

    # ---- 5. toolchain (detection only)

    if ! _cbs_flutter_qual_pf_check_stack_reference; then
        _cbs_flutter_qual_pf_conclude
        return $?
    fi

    _cbs_flutter_qual_pf_check_flutter
    _cbs_flutter_qual_pf_check_dart
    _cbs_flutter_qual_pf_check_xcode

    _cbs_flutter_qual_pf_check_sdk "SDK_IPHONEOS" "iphoneos"
    [[ "$(_cbs_flutter_qual_pf_result SDK_IPHONEOS)" != "PASS" ]] || PF_IPHONEOS_SDK="$PF_VERSION"

    _cbs_flutter_qual_pf_check_sdk "SDK_IPHONESIMULATOR" "iphonesimulator"
    [[ "$(_cbs_flutter_qual_pf_result SDK_IPHONESIMULATOR)" != "PASS" ]] || PF_IPHONESIMULATOR_SDK="$PF_VERSION"

    _cbs_flutter_qual_pf_check_simctl

    # ---- 6. simulator (existence only)

    if [[ -z "$simulator_udid" ]]; then
        _cbs_flutter_qual_pf_skip "SIMULATOR"
    elif [[ "$(_cbs_flutter_qual_pf_result SIMCTL)" == "PASS" ]]; then
        _cbs_flutter_qual_pf_check_simulator "$simulator_udid"
    fi

    _cbs_flutter_qual_pf_conclude
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -u
    CBS_FLUTTER_QUAL_PREFLIGHT_RC=0
    cbs_flutter_qual_preflight "$@" || CBS_FLUTTER_QUAL_PREFLIGHT_RC=$?
    exit "$CBS_FLUTTER_QUAL_PREFLIGHT_RC"
fi
