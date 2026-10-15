#!/usr/bin/env bash

# D04b-C.2e step 1 - Flutter/iOS qualification: common execution engine.
#
# Library only: it is sourced by the operation executors of this directory
# (analyze.sh today) and runs nothing by itself. It holds the technical
# mechanisms that do not depend on which operation is executed, moved here
# from analyze.sh (D04b-C.2b) without any change of behaviour:
#
#   - the request step (strict validation by contract.sh, the operation must
#     be one of the selected actions, the paths and bounds are read from the
#     validated request only);
#   - the evidence location: checked before anything runs, then created with
#     an exclusive create (mode 600, in a directory of mode 700). The names are
#     <OPERATION>.log, <OPERATION>.result and <OPERATION>.log.partial, the
#     operation being one of the mutating operations of the contract. An
#     evidence file that already exists refuses the run: nothing is ever
#     overwritten, followed or deleted, except the capture of the same run;
#   - the PREFLIGHT gate (preflight.sh, unchanged): a mutating operation starts
#     only when PREFLIGHT is a coherent PASS (cbs_flutter_qual_gate_allows);
#   - the check of the isolated checkout path;
#   - the bounded execution: a fixed supervisor and a fixed runner (two texts
#     run by a fresh bash), in separate process groups, under a timeout, with
#     the output redacted and capped at log_max_bytes, never overwritten;
#   - the classification of the outcome, the log, the structured answer and
#     its evidence file.
#
# What this file does NOT do, on purpose:
#   - it defines no command and no argument: the caller looks the tool up (with
#     the lookup of preflight.sh) and passes the complete command line, which
#     must be constant text of the operation file, never built from a value of
#     the request, of a manifest or of the checkout;
#   - it never runs Git, never sources a request or a manifest, never uses
#     eval, never removes anything except the capture of the same run, never
#     creates anything except the evidence of the same run;
#   - it never touches the source repository.
#
# The state is held in the EX_* variables. They are all reset by
# _cbs_flutter_qual_ex_reset: nothing is read from the environment.
#
# Compatible with Bash 3.2 (macOS) and later: no associative array, no empty
# array expansion, no case conversion expansion, no here-string, no GNU-only
# option. BSD tools only.

unset CDPATH

CBS_FLUTTER_QUAL_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [[ -z "$CBS_FLUTTER_QUAL_EXEC_DIR" || ! -f "$CBS_FLUTTER_QUAL_EXEC_DIR/preflight.sh" ]]; then
    echo "CBS_FLUTTER_QUAL_ERROR=PREFLIGHT_UNAVAILABLE" >&2
    return 1 2>/dev/null || exit 1
fi

# PREFLIGHT, as it is: it loads the contract, scrubs the environment of Git and
# BASH_ENV, and exposes the helpers reused below. Nothing runs when sourced.
# shellcheck source=/dev/null
source "$CBS_FLUTTER_QUAL_EXEC_DIR/preflight.sh"

CBS_FLUTTER_QUAL_EXEC_CONTRACT="$CBS_FLUTTER_QUAL_EXEC_DIR/contract.sh"

# --- Bounded runner ------------------------------------------------------------

# Runner: fixed text, run by "bash -c" (monitor mode off: every process of the
# pipeline stays in the process group of the runner). Arguments: CONTRACT OUT
# CAP_PLUS_ONE COMMAND [ARG...]. The output of the command (stdout and stderr)
# is redacted by the contract, capped at CAP_PLUS_ONE bytes (one more than the
# limit, to tell a full log from an exceeded one) and written to OUT. It prints
# one line with the two statuses of the pipeline: the command, then the
# redaction and the cap together. What the command prints never reaches the
# standard output of the runner.
#
# On a timeout the supervisor sends TERM to the whole group, KILL one second
# later. The runner traps TERM (it stays alive to report), the command keeps the
# default action and dies, while the redaction and the cap ignore TERM: they
# read up to the end of the output, flush it and end by themselves, so that what
# the command had printed is kept in the log. A command that ignores TERM is
# killed with the group: what the redaction had not flushed yet is then lost.
CBS_FLUTTER_QUAL_EXEC_RUNNER='
set +e +u +C
trap ":" TERM
contract=$1
out=$2
cap=$3
shift 3
. "$contract" || exit 252
( LC_ALL=C exec "$@" ) 2>&1 | ( trap "" TERM; set -o pipefail; LC_ALL=C cbs_flutter_qual_redact_stream | head -c "$cap" >| "$out" )
set -- "${PIPESTATUS[@]}"
printf "CBS_ANALYZE_RUN %s %s\n" "$1" "$2"
'

# Supervisor: fixed text, run by "bash -c". Arguments: RUNNER LIMIT CAP OUT DIR
# CONTRACT COMMAND [ARG...] (all data).
#   - the runner starts in DIR, in its own process group (set -m);
#   - the timer is a second group that only sleeps, then sends USR1 here: when
#     the job table still lists the runner as running, it receives TERM, then
#     KILL one second later; the timeout is recorded;
#   - at the end (or INT / TERM / HUP received here) the timer group is killed
#     and reaped, the remaining members of the runner group are killed, and only
#     then the trailer "CBS_ANALYZE_SUP <status> <timed_out>" is printed.
CBS_FLUTTER_QUAL_EXEC_SUPERVISOR='
exec 2>/dev/null
set +e +u +C
runner=$1
limit=$2
cap=$3
out=$4
dir=$5
contract=$6
shift 6
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

( cd "$dir" && exec "${BASH:-bash}" -c "$runner" cbs-analyze-runner "$contract" "$out" "$((cap + 1))" "$@" ) </dev/null &
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
printf "CBS_ANALYZE_SUP %s %s\n" "$status" "$timed_out"
'

# --- State ---------------------------------------------------------------------

# Arguments: OPERATION COMMAND_NAME. OPERATION is the operation of the contract
# that the caller executes (a constant of the caller). COMMAND_NAME is the
# closed word that names its command in the structured answer. Every variable of
# the state is set here: none comes from the environment.
_cbs_flutter_qual_ex_reset() {
    EX_OPERATION="${1:-}"
    EX_COMMAND_NAME="${2:-}"
    EX_ISOLATION_ID=""
    EX_ISOLATION_ROOT=""
    EX_EVIDENCE_ROOT=""
    EX_TIMEOUT=""
    EX_CAP=""
    EX_CHECKOUT=""
    EX_RESULT="NOT_RUN"
    EX_REASON="NOT_EXECUTED"
    EX_TOOL_RC=""
    EX_REJECTED_KEY=""
    EX_QUALIFICATION_ID=""
    EX_PREFLIGHT_RESULT=""
    EX_PREFLIGHT_REASON=""
    EX_COMMIT=""
    EX_FLUTTER_VERSION=""
    EX_DURATION=""
    EX_LOG_BYTES=""
    EX_LOG_CRC=""
    EX_LOG_TRUNCATED=""
    EX_EVIDENCE="NOT_WRITTEN"
    EX_STARTED="0"
    EX_BODY=""
    EX_QDIR=""
    EX_PARTIAL=""
    EX_LOG=""
    EX_RESULT_FILE=""
    EX_RUN_RAW=""
    EX_RUN_SUP_RC=""
    EX_RUN_TIMED_OUT=""
    EX_RUN_COMMAND_RC=""
    EX_RUN_FILTER_RC=""
    EX_PARTIAL_BYTES=""
}

# Arguments: REASON [TOOL_RC]. The result is the class of the reason: they
# never diverge.
_cbs_flutter_qual_ex_set() {
    local result

    result="$(cbs_flutter_qual_result_for_reason "$1")" || result="BLOCKED"

    EX_RESULT="$result"
    EX_REASON="$1"
    EX_TOOL_RC="${2:-}"
}

_cbs_flutter_qual_ex_pass() {
    EX_RESULT="PASS"
    EX_REASON=""
    EX_TOOL_RC="0"
}

# Arguments: TEXT KEY. Prints the value of the first "KEY=VALUE" line of TEXT.
# Fails when there is none. Nothing is evaluated.
_cbs_flutter_qual_ex_value() {
    local rest="$1"
    local key="$2"
    local line

    while [[ -n "$rest" ]]; do
        line="${rest%%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"*}"

        if [[ "$rest" == *"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"* ]]; then
            rest="${rest#*"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
        else
            rest=""
        fi

        if [[ "$line" == "$key="* ]]; then
            printf '%s' "${line#*=}"
            return 0
        fi
    done

    return 1
}

# --- Evidence location ---------------------------------------------------------

# Argument: DIRECTORY. Succeeds when it is an existing directory of this user,
# canonical (no symbolic link in any component), not writable by group or
# others: nobody else can place or swap a file there.
_cbs_flutter_qual_ex_dir_is_private() {
    local path="$1"
    local found

    [[ -d "$path" && ! -L "$path" && -O "$path" && -w "$path" && -x "$path" ]] || return 1
    cbs_flutter_qual_dir_is_canonical "$path" || return 1

    found="$(find "$path" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" || return 1
    [[ -z "$found" ]]
}

# Arguments: PATH. Succeeds when nothing exists there (a dangling symbolic link
# counts as existing).
_cbs_flutter_qual_ex_absent() {
    [[ ! -e "$1" && ! -L "$1" ]]
}

# Arguments: EVIDENCE_ROOT QUALIFICATION_ID. Checks, without writing, that the
# run may create its evidence; sets the paths. Never follows a link. The file
# names come from the operation of the contract (closed list, mutating
# operations only): an operation that is not one is refused.
_cbs_flutter_qual_ex_check_evidence() {
    local evidence_root="$1"
    local qualification_id="$2"

    cbs_flutter_qual_operation_is_mutating "$EX_OPERATION" || return 1

    _cbs_flutter_qual_ex_dir_is_private "$evidence_root" || return 1

    EX_QDIR="$evidence_root/$qualification_id"
    EX_PARTIAL="$EX_QDIR/$EX_OPERATION.log.partial"
    EX_LOG="$EX_QDIR/$EX_OPERATION.log"
    EX_RESULT_FILE="$EX_QDIR/$EX_OPERATION.result"

    if _cbs_flutter_qual_ex_absent "$EX_QDIR"; then
        return 0
    fi

    _cbs_flutter_qual_ex_dir_is_private "$EX_QDIR" || return 1

    _cbs_flutter_qual_ex_absent "$EX_PARTIAL" || return 1
    _cbs_flutter_qual_ex_absent "$EX_LOG" || return 1
    _cbs_flutter_qual_ex_absent "$EX_RESULT_FILE" || return 1
}

# Creates the qualification directory (mode 700, no "-p": the evidence root is
# the parent) and reserves the capture file. Fails if anything exists.
_cbs_flutter_qual_ex_create_evidence() {
    if _cbs_flutter_qual_ex_absent "$EX_QDIR"; then
        ( umask 077; mkdir "$EX_QDIR" ) 2>/dev/null || return 1
    fi

    _cbs_flutter_qual_ex_dir_is_private "$EX_QDIR" || return 1

    ( umask 077; set -C; : > "$EX_PARTIAL" ) 2>/dev/null || return 1
    [[ -f "$EX_PARTIAL" && ! -L "$EX_PARTIAL" ]]
}

# Arguments: FILE. Prints "<crc> <bytes>" (POSIX cksum, no padding).
_cbs_flutter_qual_ex_cksum() {
    local line
    local pattern='^([0-9]{1,10})[[:space:]]+([0-9]{1,12})$'

    line="$(cksum < "$1" 2>/dev/null)" || return 1

    [[ "$line" =~ $pattern ]] || return 1
    printf '%s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

# --- PREFLIGHT gate ------------------------------------------------------------

# Arguments: REQUEST ENTRY... Runs PREFLIGHT on the request and keeps only what
# the structured answer says. Succeeds only when the answer is a coherent PASS:
# exit status 0, operation PREFLIGHT, operation result and overall result PASS,
# no reason, last line "CBS_FLUTTER_QUAL_RESULT=PASS". Anything else is "not
# passed", whatever the text says. PREFLIGHT runs in a subshell: its state and
# its stderr (the reason, repeated in the structured answer) do not leak.
_cbs_flutter_qual_ex_gate() {
    local out
    local rc=0
    local last
    local operation
    local operation_result
    local overall
    local reason
    local value
    local version_pattern='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$'

    out="$(cbs_flutter_qual_preflight "$@" 2>/dev/null)" || rc=$?

    last="${out##*"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
    operation="$(_cbs_flutter_qual_ex_value "$out" CBS_FLUTTER_QUAL_OPERATION)" || operation=""
    operation_result="$(_cbs_flutter_qual_ex_value "$out" CBS_FLUTTER_QUAL_OPERATION_RESULT)" || operation_result=""
    overall="$(_cbs_flutter_qual_ex_value "$out" CBS_FLUTTER_QUAL_RESULT)" || overall=""
    reason="$(_cbs_flutter_qual_ex_value "$out" CBS_FLUTTER_QUAL_REASON)" || reason=""

    EX_PREFLIGHT_RESULT="NOT_RUN"
    EX_PREFLIGHT_REASON=""

    # What is reported of a refusal: its result and its reason, only when the
    # reason is a closed reason of the contract that belongs to that result.
    if [[ "$operation" == "PREFLIGHT" ]] && cbs_flutter_qual_result_is_valid "$overall"; then
        EX_PREFLIGHT_RESULT="$overall"

        if [[ -n "$reason" ]] && cbs_flutter_qual_result_reason_consistent "$overall" "$reason"; then
            EX_PREFLIGHT_REASON="$reason"
        fi
    fi

    if [[ "$rc" -ne 0 || "$operation" != "PREFLIGHT" || "$operation_result" != "PASS" ||
        "$overall" != "PASS" || -n "$reason" || "$last" != "CBS_FLUTTER_QUAL_RESULT=PASS" ]]; then
        # An answer that is not a coherent PASS is never reported as a PASS.
        if [[ "$EX_PREFLIGHT_RESULT" == "PASS" ]]; then
            EX_PREFLIGHT_RESULT="NOT_RUN"
            EX_PREFLIGHT_REASON=""
        fi

        return 1
    fi

    # The contract decides whether a mutating operation may start.
    cbs_flutter_qual_gate_allows "$EX_OPERATION" "$EX_PREFLIGHT_RESULT" || return 1

    value="$(_cbs_flutter_qual_ex_value "$out" CBS_FLUTTER_QUAL_PREFLIGHT_COMMIT_OBSERVED)" || value=""
    if cbs_flutter_qual_commit_valid "$value"; then
        EX_COMMIT="$value"
    fi

    value="$(_cbs_flutter_qual_ex_value "$out" CBS_FLUTTER_QUAL_PREFLIGHT_FLUTTER_VERSION)" || value=""
    if [[ "$value" =~ $version_pattern ]]; then
        EX_FLUTTER_VERSION="$value"
    fi

    return 0
}

# --- Execution -----------------------------------------------------------------

# Arguments: CHECKOUT LIMIT CAP COMMAND [ARG...]. Runs the command, given as a
# complete command line by the caller (an absolute tool path and constant
# arguments of the operation file), under the supervisor and records what it
# reports. The output of the supervisor is made of its own lines only: nothing
# printed by the tool travels through it.
_cbs_flutter_qual_ex_run() {
    local checkout="$1"
    local limit="$2"
    local cap="$3"
    local rest
    local line
    local started
    local run_pattern='^CBS_ANALYZE_RUN ([0-9]{1,3}) ([0-9]{1,3})$'
    local sup_pattern='^CBS_ANALYZE_SUP ([0-9]{1,3}) ([01])$'

    EX_RUN_SUP_RC=""
    EX_RUN_TIMED_OUT=""
    EX_RUN_COMMAND_RC=""
    EX_RUN_FILTER_RC=""

    shift 3

    started=$SECONDS

    EX_RUN_RAW="$("${BASH:-bash}" -c "$CBS_FLUTTER_QUAL_EXEC_SUPERVISOR" cbs-analyze-supervisor \
        "$CBS_FLUTTER_QUAL_EXEC_RUNNER" "$limit" "$cap" "$EX_PARTIAL" "$checkout" \
        "$CBS_FLUTTER_QUAL_EXEC_CONTRACT" \
        "$@" </dev/null 2>/dev/null)"

    EX_DURATION="$((SECONDS - started))"

    rest="$EX_RUN_RAW"

    while [[ -n "$rest" ]]; do
        line="${rest%%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"*}"

        if [[ "$rest" == *"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"* ]]; then
            rest="${rest#*"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
        else
            rest=""
        fi

        if [[ -z "$EX_RUN_COMMAND_RC" && "$line" =~ $run_pattern ]]; then
            EX_RUN_COMMAND_RC="${BASH_REMATCH[1]}"
            EX_RUN_FILTER_RC="${BASH_REMATCH[2]}"
        elif [[ -z "$EX_RUN_SUP_RC" && "$line" =~ $sup_pattern ]]; then
            EX_RUN_SUP_RC="${BASH_REMATCH[1]}"
            EX_RUN_TIMED_OUT="${BASH_REMATCH[2]}"
        fi
    done
}

# Argument: CAP. Decides the outcome of the run from what the supervisor
# reported and from the size of the capture (never from the text of the log).
_cbs_flutter_qual_ex_classify() {
    local cap="$1"
    local sum

    EX_LOG_TRUNCATED="NO"

    if ! sum="$(_cbs_flutter_qual_ex_cksum "$EX_PARTIAL")"; then
        _cbs_flutter_qual_ex_set "EVIDENCE_FAILURE"
        return 0
    fi

    EX_PARTIAL_BYTES="${sum#* }"

    # More than the limit: the capture stopped one byte after it, flutter was
    # cut by the closed pipe (or ran on until the timeout). The size wins over
    # the status of the tool: it is what was observed.
    if [[ "$((10#$EX_PARTIAL_BYTES))" -gt "$cap" ]]; then
        EX_LOG_TRUNCATED="YES"
        _cbs_flutter_qual_ex_set "LOG_LIMIT_EXCEEDED"
        return 0
    fi

    if [[ "$EX_RUN_TIMED_OUT" == "1" ]]; then
        _cbs_flutter_qual_ex_set "TIMEOUT"
        return 0
    fi

    # No status from the runner: the tool did not report, nothing is known of it.
    if [[ -z "$EX_RUN_COMMAND_RC" || -z "$EX_RUN_SUP_RC" ]]; then
        _cbs_flutter_qual_ex_set "COMMAND_FAILED"
        return 0
    fi

    # The redaction or the capture failed: the evidence cannot be trusted.
    if [[ "$EX_RUN_FILTER_RC" != "0" ]]; then
        _cbs_flutter_qual_ex_set "EVIDENCE_FAILURE"
        return 0
    fi

    if [[ "$((10#$EX_RUN_COMMAND_RC))" -ne 0 ]]; then
        _cbs_flutter_qual_ex_set "COMMAND_FAILED" "$((10#$EX_RUN_COMMAND_RC))"
        return 0
    fi

    _cbs_flutter_qual_ex_pass
}

# Argument: CAP. Turns the capture into the log (at most CAP bytes, exclusive
# create, mode 600) and removes the capture created by this run. Fails when the
# log cannot be written.
_cbs_flutter_qual_ex_finalize_log() {
    local cap="$1"
    local sum

    ( umask 077; set -C; head -c "$cap" "$EX_PARTIAL" > "$EX_LOG" ) 2>/dev/null || return 1
    [[ -f "$EX_LOG" && ! -L "$EX_LOG" ]] || return 1

    sum="$(_cbs_flutter_qual_ex_cksum "$EX_LOG")" || return 1
    EX_LOG_CRC="${sum%% *}"
    EX_LOG_BYTES="${sum#* }"

    # The capture of this run, at the path computed from validated parts.
    rm -f -- "$EX_PARTIAL" 2>/dev/null || return 1
    [[ ! -e "$EX_PARTIAL" ]]
}

# --- Structured output ---------------------------------------------------------

# Prints a fact only when its value has the shape of a closed word or a number.
# The name of a fact is CBS_FLUTTER_QUAL_<OPERATION>_<NAME>.
# Arguments: NAME VALUE PATTERN
_cbs_flutter_qual_ex_fact() {
    local name="$1"
    local value="$2"
    local pattern="$3"

    [[ -n "$value" && "$value" =~ $pattern ]] || return 0

    printf 'CBS_FLUTTER_QUAL_%s_%s=%s\n' "$EX_OPERATION" "$name" "$value"
}

# Renders the whole structured answer into EX_BODY (facts, operation, result).
# Returns the contract return code of the reason, or 64 on an inconsistent
# emission.
_cbs_flutter_qual_ex_render() {
    local version_pattern='^[0-9]+(\.[0-9]+){0,3}([-+][0-9A-Za-z.+-]+)?$'
    local operation_lines
    local result_lines

    # The operation is checked first: an operation that is not one of the
    # contract prints nothing.
    if ! operation_lines="$(cbs_flutter_qual_emit_operation "$EX_OPERATION" "$EX_RESULT" "$EX_REASON" "$EX_TOOL_RC" 2>/dev/null)" ||
        ! result_lines="$(cbs_flutter_qual_emit_result "$EX_RESULT" "$EX_REASON" 2>/dev/null)"; then
        EX_BODY=""
        return "$CBS_RC_FLUTTER_QUAL_USAGE"
    fi

    EX_BODY="$(
        [[ -z "$EX_REJECTED_KEY" ]] ||
            printf 'CBS_FLUTTER_QUAL_%s_REJECTED_KEY=%s\n' "$EX_OPERATION" "$EX_REJECTED_KEY"

        if [[ -n "$EX_QUALIFICATION_ID" ]] && cbs_flutter_qual_id_valid "$EX_QUALIFICATION_ID"; then
            printf 'CBS_FLUTTER_QUAL_%s_QUALIFICATION_ID=%s\n' "$EX_OPERATION" "$EX_QUALIFICATION_ID"
        fi

        _cbs_flutter_qual_ex_fact "PREFLIGHT_RESULT" "$EX_PREFLIGHT_RESULT" '^(PASS|FAIL|BLOCKED|SKIPPED|NOT_RUN)$'
        _cbs_flutter_qual_ex_fact "PREFLIGHT_REASON" "$EX_PREFLIGHT_REASON" '^[A-Z][A-Z0-9_]{0,63}$'

        if [[ -n "$EX_COMMIT" ]] && cbs_flutter_qual_commit_valid "$EX_COMMIT"; then
            printf 'CBS_FLUTTER_QUAL_%s_COMMIT_OBSERVED=%s\n' "$EX_OPERATION" "$EX_COMMIT"
        fi

        _cbs_flutter_qual_ex_fact "FLUTTER_VERSION" "$EX_FLUTTER_VERSION" "$version_pattern"

        # A command that was never started has no duration, no log.
        if [[ -n "$EX_DURATION" ]]; then
            _cbs_flutter_qual_ex_fact "COMMAND" "$EX_COMMAND_NAME" '^[a-z][a-z0-9_]{0,63}$'
            _cbs_flutter_qual_ex_fact "DURATION_SECONDS" "$EX_DURATION" '^[0-9]{1,9}$'
            _cbs_flutter_qual_ex_fact "LOG_BYTES" "$EX_LOG_BYTES" '^[0-9]{1,12}$'
            _cbs_flutter_qual_ex_fact "LOG_CRC" "$EX_LOG_CRC" '^[0-9]{1,10}$'
            _cbs_flutter_qual_ex_fact "LOG_TRUNCATED" "$EX_LOG_TRUNCATED" '^(YES|NO)$'
        fi

        printf 'CBS_FLUTTER_QUAL_%s_EVIDENCE=%s\n' "$EX_OPERATION" "$EX_EVIDENCE"
        printf '%s\n' "$operation_lines"
        printf '%s\n' "$result_lines"
    )"

    return 0
}

# Writes EX_BODY as <OPERATION>.result (exclusive create, mode 600).
_cbs_flutter_qual_ex_write_result() {
    ( umask 077; set -C; printf '%s\n' "$EX_BODY" > "$EX_RESULT_FILE" ) 2>/dev/null || return 1
    [[ -f "$EX_RESULT_FILE" && ! -L "$EX_RESULT_FILE" ]]
}

# Prints the answer and returns the contract return code of the reason. The
# RESULT line is the last line of stdout; the reason is repeated on stderr.
_cbs_flutter_qual_ex_conclude() {
    if [[ "$EX_STARTED" == "1" ]]; then
        # A PASS never survives a log that could not be written ...
        if [[ "$EX_EVIDENCE" == "FAILED" && "$EX_RESULT" == "PASS" ]]; then
            _cbs_flutter_qual_ex_set "EVIDENCE_FAILURE"
        fi

        # ... nor an answer that could not be written: the file holds exactly
        # the answer that is printed.
        _cbs_flutter_qual_ex_render || true

        if ! _cbs_flutter_qual_ex_write_result; then
            EX_EVIDENCE="FAILED"

            if [[ "$EX_RESULT" == "PASS" ]]; then
                _cbs_flutter_qual_ex_set "EVIDENCE_FAILURE"
            fi
        fi
    fi

    if ! _cbs_flutter_qual_ex_render; then
        echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
        return "$CBS_RC_FLUTTER_QUAL_USAGE"
    fi

    printf '%s\n' "$EX_BODY"

    if [[ -n "$EX_REASON" ]]; then
        printf 'CBS_FLUTTER_QUAL_ERROR=%s\n' "$EX_REASON" >&2
    fi

    return "$(cbs_flutter_qual_rc_for_reason "$EX_REASON")"
}

# --- Steps of an operation -----------------------------------------------------
#
# The operation file calls these steps in order. A step returns 0 when the
# operation may go on. When it returns 1 it has already recorded the outcome
# (result, reason, rejected key) in the state: the caller only concludes.
#
#   1. request              validated request, operation selected
#   2. evidence location    checked, nothing created yet
#   3. PREFLIGHT gate       must be a coherent PASS
#   4. checkout             plain directory inside the isolation root
#      (the caller looks the tool up here: TOOL_UNAVAILABLE)
#   5. evidence open        checked again, then created
#   6. execute              bounded run, classification, log

# Arguments: ENTRY... (the request). The request is validated with the contract
# (data only). The operation of the state must be one of its selected actions,
# and a mutating one. Sets the qualification, the isolation, the evidence and
# the bounds from the validated request only.
_cbs_flutter_qual_ex_request() {
    local reason
    local actions
    local action

    if [[ "$#" -eq 0 ]]; then
        _cbs_flutter_qual_ex_set "USAGE"
        return 1
    fi

    if ! cbs_flutter_qual_validate_request "$@"; then
        reason="$CBS_FLUTTER_QUAL_VALIDATION_REASON"
        EX_REJECTED_KEY="$CBS_FLUTTER_QUAL_VALIDATION_KEY"

        cbs_flutter_qual_reason_is_valid "$reason" || reason="INPUT_INVALID"

        _cbs_flutter_qual_ex_set "$reason"
        return 1
    fi

    actions="$(cbs_flutter_qual_entries_get actions "$@")"
    action="$(cbs_flutter_qual_action_for_operation "$EX_OPERATION")" || action=""

    # This operation must have been selected.
    if [[ -z "$action" ]] || ! cbs_flutter_qual_operation_is_mutating "$EX_OPERATION"; then
        EX_REJECTED_KEY="actions"
        _cbs_flutter_qual_ex_set "ACTION_NOT_ALLOWED"
        return 1
    fi

    case ",$actions," in
        *",$action,"*) ;;
        *)
            EX_REJECTED_KEY="actions"
            _cbs_flutter_qual_ex_set "ACTION_NOT_ALLOWED"
            return 1
            ;;
    esac

    EX_QUALIFICATION_ID="$(cbs_flutter_qual_entries_get qualification_id "$@")"
    EX_ISOLATION_ID="$(cbs_flutter_qual_entries_get isolation_id "$@")"
    EX_ISOLATION_ROOT="$(cbs_flutter_qual_entries_get isolation_root "$@")"
    EX_EVIDENCE_ROOT="$(cbs_flutter_qual_entries_get evidence_root "$@")"
    EX_TIMEOUT="$(cbs_flutter_qual_entries_get timeout_seconds "$@")"
    EX_CAP="$(cbs_flutter_qual_entries_get log_max_bytes "$@")"

    EX_TIMEOUT="$((10#$EX_TIMEOUT))"
    EX_CAP="$((10#$EX_CAP))"

    return 0
}

# Checks, without creating anything, that the evidence of this run may be
# written.
_cbs_flutter_qual_ex_evidence_location() {
    if ! _cbs_flutter_qual_ex_check_evidence "$EX_EVIDENCE_ROOT" "$EX_QUALIFICATION_ID"; then
        EX_REJECTED_KEY="evidence_root"
        _cbs_flutter_qual_ex_set "PATH_NOT_ALLOWED"
        return 1
    fi

    return 0
}

# Arguments: ENTRY... (the request). PREFLIGHT must be a coherent PASS: it is
# what verifies, read-only, the isolation, the commit, the origin and the
# toolchain. Otherwise nothing runs and nothing is written.
_cbs_flutter_qual_ex_preflight_gate() {
    if ! _cbs_flutter_qual_ex_gate "$@"; then
        _cbs_flutter_qual_ex_set "PREFLIGHT_NOT_PASSED"
        return 1
    fi

    return 0
}

# The working directory of the command: a plain directory of the isolation root
# (never a link, never the source repository). Sets EX_CHECKOUT.
_cbs_flutter_qual_ex_checkout() {
    EX_CHECKOUT="$EX_ISOLATION_ROOT/$EX_ISOLATION_ID"

    if [[ -L "$EX_CHECKOUT" ]] || ! cbs_flutter_qual_dir_is_canonical "$EX_CHECKOUT"; then
        _cbs_flutter_qual_ex_set "ISOLATION_REJECTED"
        return 1
    fi

    return 0
}

# Checks again, then creates the evidence directory and reserves the capture.
# From here the answer is written as evidence.
_cbs_flutter_qual_ex_evidence_open() {
    if ! _cbs_flutter_qual_ex_check_evidence "$EX_EVIDENCE_ROOT" "$EX_QUALIFICATION_ID" ||
        ! _cbs_flutter_qual_ex_create_evidence; then
        EX_REJECTED_KEY="evidence_root"
        _cbs_flutter_qual_ex_set "PATH_NOT_ALLOWED"
        return 1
    fi

    EX_STARTED="1"
    EX_EVIDENCE="WRITTEN"

    return 0
}

# Arguments: COMMAND [ARG...]. The complete command line, constant text of the
# operation file with the absolute path found by the caller. Runs it once in
# the checkout, under the timeout and the log bound of the request, then
# classifies the outcome and writes the log, which survives every outcome.
_cbs_flutter_qual_ex_execute() {
    _cbs_flutter_qual_ex_run "$EX_CHECKOUT" "$EX_TIMEOUT" "$EX_CAP" "$@"
    _cbs_flutter_qual_ex_classify "$EX_CAP"

    # The log survives every outcome, including a failure or a timeout.
    _cbs_flutter_qual_ex_finalize_log "$EX_CAP" || EX_EVIDENCE="FAILED"
}
