#!/usr/bin/env bash

# D04b-C.2b step 3 - Flutter/iOS qualification: ANALYZE.
#
#   analyze.sh KEY=VALUE...
#
# The arguments are the request defined by contract.sh (data only). ANALYZE
# runs one fixed command, "flutter analyze", in the isolated checkout, and
# nothing else:
#   - the request is validated with the qualified contract, and "analyze" must
#     be one of its selected actions;
#   - the evidence location is checked before anything runs;
#   - PREFLIGHT (preflight.sh, unchanged) is run on the same request, right
#     before: it verifies, read-only, that the checkout is owned by CBS, is the
#     exact commit and origin, a detached and clean HEAD, and that the
#     toolchain is acceptable. ANALYZE starts only when its result is exactly
#     PASS (cbs_flutter_qual_gate_allows); otherwise it is NOT_RUN with
#     PREFLIGHT_NOT_PASSED and nothing is executed or written;
#   - flutter is looked up in the absolute entries of PATH, then run once from
#     the isolated checkout, without input, in its own process group, under
#     timeout_seconds, with output redacted and bounded by log_max_bytes.
#
# The command line is the constant CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT: no value
# of the request, of a manifest or of the checkout is ever part of a command,
# is evaluated, sourced or expanded. There is no "--no-pub" or any other option:
# the options of "flutter analyze" are an open decision of the contract.
#
# What this file writes, and only this, under evidence_root (which must already
# exist: it is never created here):
#   <evidence_root>/<qualification_id>/ANALYZE.log      redacted, bounded output
#   <evidence_root>/<qualification_id>/ANALYZE.result   the structured answer
# Files are created with an exclusive create (never overwritten), mode 600, in a
# directory of mode 700. Nothing existing is ever modified or deleted, except
# the temporary capture ANALYZE.log.partial created by the same run. An
# evidence file that already exists refuses the run (PATH_NOT_ALLOWED): a new
# qualification_id is needed.
#
# What flutter itself may write is out of this file's control: the checkout
# (.dart_tool/, build/, pubspec.lock, ios/Flutter/) and the caches of the user
# (pub cache, Flutter SDK cache). The source repository is never a working
# directory, never written, never read by this file.
#
# Results (contract.sh):
#   PASS     flutter exited with 0 (tool status 0)
#   FAIL     COMMAND_FAILED (flutter exited non-zero, its exact status is
#            OPERATION_TOOL_RC), TIMEOUT, LOG_LIMIT_EXCEEDED, EVIDENCE_FAILURE
#   BLOCKED  request or evidence location refused, TOOL_UNAVAILABLE (flutter
#            vanished after PREFLIGHT), ISOLATION_REJECTED (checkout path)
#   NOT_RUN  PREFLIGHT_NOT_PASSED
# NETWORK_FAILURE is never emitted: it would need the real messages of the tool,
# which are not frozen.
#
# Bounded execution. A fixed supervisor (run by a fresh bash, like the one of
# preflight.sh) starts a fixed runner and a timer in two process groups. The
# timer only sleeps, then sends USR1 to the supervisor; the supervisor alone
# signals the runner group, and only while it is running. The runner runs
# flutter, merges its output, redacts it, caps it (head -c) and writes it to the
# capture file. Nothing outlives the call.
#
# Compatible with Bash 3.2 (macOS) and later: no associative array, no empty
# array expansion, no case conversion expansion, no here-string, no GNU-only
# option. BSD tools only.

unset CDPATH

CBS_FLUTTER_QUAL_ANALYZE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [[ -z "$CBS_FLUTTER_QUAL_ANALYZE_DIR" || ! -f "$CBS_FLUTTER_QUAL_ANALYZE_DIR/preflight.sh" ]]; then
    echo "CBS_FLUTTER_QUAL_ERROR=PREFLIGHT_UNAVAILABLE" >&2
    return 1 2>/dev/null || exit 1
fi

# PREFLIGHT, as it is: it loads the contract, scrubs the environment of Git and
# BASH_ENV, and exposes the helpers reused below. Nothing runs when sourced.
# shellcheck source=/dev/null
source "$CBS_FLUTTER_QUAL_ANALYZE_DIR/preflight.sh"

CBS_FLUTTER_QUAL_ANALYZE_CONTRACT="$CBS_FLUTTER_QUAL_ANALYZE_DIR/contract.sh"

# The one and only argument given to flutter. Never built from anything.
readonly CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT="analyze"

readonly CBS_FLUTTER_QUAL_ANALYZE_LOG_NAME="ANALYZE.log"
readonly CBS_FLUTTER_QUAL_ANALYZE_RESULT_NAME="ANALYZE.result"
readonly CBS_FLUTTER_QUAL_ANALYZE_PARTIAL_NAME="ANALYZE.log.partial"

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
CBS_FLUTTER_QUAL_ANALYZE_RUNNER='
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
CBS_FLUTTER_QUAL_ANALYZE_SUPERVISOR='
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

_cbs_flutter_qual_an_reset() {
    AN_RESULT="NOT_RUN"
    AN_REASON="NOT_EXECUTED"
    AN_TOOL_RC=""
    AN_REJECTED_KEY=""
    AN_QUALIFICATION_ID=""
    AN_PREFLIGHT_RESULT=""
    AN_PREFLIGHT_REASON=""
    AN_COMMIT=""
    AN_FLUTTER_VERSION=""
    AN_DURATION=""
    AN_LOG_BYTES=""
    AN_LOG_CRC=""
    AN_LOG_TRUNCATED=""
    AN_EVIDENCE="NOT_WRITTEN"
    AN_STARTED="0"
    AN_BODY=""
    AN_QDIR=""
    AN_PARTIAL=""
    AN_LOG=""
    AN_RESULT_FILE=""
    AN_RUN_RAW=""
    AN_RUN_SUP_RC=""
    AN_RUN_TIMED_OUT=""
    AN_RUN_COMMAND_RC=""
    AN_RUN_FILTER_RC=""
    AN_PARTIAL_BYTES=""
}

# Arguments: REASON [TOOL_RC]. The result is the class of the reason: they
# never diverge.
_cbs_flutter_qual_an_set() {
    local result

    result="$(cbs_flutter_qual_result_for_reason "$1")" || result="BLOCKED"

    AN_RESULT="$result"
    AN_REASON="$1"
    AN_TOOL_RC="${2:-}"
}

_cbs_flutter_qual_an_pass() {
    AN_RESULT="PASS"
    AN_REASON=""
    AN_TOOL_RC="0"
}

# Arguments: TEXT KEY. Prints the value of the first "KEY=VALUE" line of TEXT.
# Fails when there is none. Nothing is evaluated.
_cbs_flutter_qual_an_value() {
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
_cbs_flutter_qual_an_dir_is_private() {
    local path="$1"
    local found

    [[ -d "$path" && ! -L "$path" && -O "$path" && -w "$path" && -x "$path" ]] || return 1
    cbs_flutter_qual_dir_is_canonical "$path" || return 1

    found="$(find "$path" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" || return 1
    [[ -z "$found" ]]
}

# Arguments: PATH. Succeeds when nothing exists there (a dangling symbolic link
# counts as existing).
_cbs_flutter_qual_an_absent() {
    [[ ! -e "$1" && ! -L "$1" ]]
}

# Arguments: EVIDENCE_ROOT QUALIFICATION_ID. Checks, without writing, that the
# run may create its evidence; sets the paths. Never follows a link.
_cbs_flutter_qual_an_check_evidence() {
    local evidence_root="$1"
    local qualification_id="$2"

    _cbs_flutter_qual_an_dir_is_private "$evidence_root" || return 1

    AN_QDIR="$evidence_root/$qualification_id"
    AN_PARTIAL="$AN_QDIR/$CBS_FLUTTER_QUAL_ANALYZE_PARTIAL_NAME"
    AN_LOG="$AN_QDIR/$CBS_FLUTTER_QUAL_ANALYZE_LOG_NAME"
    AN_RESULT_FILE="$AN_QDIR/$CBS_FLUTTER_QUAL_ANALYZE_RESULT_NAME"

    if _cbs_flutter_qual_an_absent "$AN_QDIR"; then
        return 0
    fi

    _cbs_flutter_qual_an_dir_is_private "$AN_QDIR" || return 1

    _cbs_flutter_qual_an_absent "$AN_PARTIAL" || return 1
    _cbs_flutter_qual_an_absent "$AN_LOG" || return 1
    _cbs_flutter_qual_an_absent "$AN_RESULT_FILE" || return 1
}

# Creates the qualification directory (mode 700, no "-p": the evidence root is
# the parent) and reserves the capture file. Fails if anything exists.
_cbs_flutter_qual_an_create_evidence() {
    if _cbs_flutter_qual_an_absent "$AN_QDIR"; then
        ( umask 077; mkdir "$AN_QDIR" ) 2>/dev/null || return 1
    fi

    _cbs_flutter_qual_an_dir_is_private "$AN_QDIR" || return 1

    ( umask 077; set -C; : > "$AN_PARTIAL" ) 2>/dev/null || return 1
    [[ -f "$AN_PARTIAL" && ! -L "$AN_PARTIAL" ]]
}

# Arguments: FILE. Prints "<crc> <bytes>" (POSIX cksum, no padding).
_cbs_flutter_qual_an_cksum() {
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
_cbs_flutter_qual_an_gate() {
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
    operation="$(_cbs_flutter_qual_an_value "$out" CBS_FLUTTER_QUAL_OPERATION)" || operation=""
    operation_result="$(_cbs_flutter_qual_an_value "$out" CBS_FLUTTER_QUAL_OPERATION_RESULT)" || operation_result=""
    overall="$(_cbs_flutter_qual_an_value "$out" CBS_FLUTTER_QUAL_RESULT)" || overall=""
    reason="$(_cbs_flutter_qual_an_value "$out" CBS_FLUTTER_QUAL_REASON)" || reason=""

    AN_PREFLIGHT_RESULT="NOT_RUN"
    AN_PREFLIGHT_REASON=""

    # What is reported of a refusal: its result and its reason, only when the
    # reason is a closed reason of the contract that belongs to that result.
    if [[ "$operation" == "PREFLIGHT" ]] && cbs_flutter_qual_result_is_valid "$overall"; then
        AN_PREFLIGHT_RESULT="$overall"

        if [[ -n "$reason" ]] && cbs_flutter_qual_result_reason_consistent "$overall" "$reason"; then
            AN_PREFLIGHT_REASON="$reason"
        fi
    fi

    if [[ "$rc" -ne 0 || "$operation" != "PREFLIGHT" || "$operation_result" != "PASS" ||
        "$overall" != "PASS" || -n "$reason" || "$last" != "CBS_FLUTTER_QUAL_RESULT=PASS" ]]; then
        # An answer that is not a coherent PASS is never reported as a PASS.
        if [[ "$AN_PREFLIGHT_RESULT" == "PASS" ]]; then
            AN_PREFLIGHT_RESULT="NOT_RUN"
            AN_PREFLIGHT_REASON=""
        fi

        return 1
    fi

    # The contract decides whether a mutating operation may start.
    cbs_flutter_qual_gate_allows "ANALYZE" "$AN_PREFLIGHT_RESULT" || return 1

    value="$(_cbs_flutter_qual_an_value "$out" CBS_FLUTTER_QUAL_PREFLIGHT_COMMIT_OBSERVED)" || value=""
    if cbs_flutter_qual_commit_valid "$value"; then
        AN_COMMIT="$value"
    fi

    value="$(_cbs_flutter_qual_an_value "$out" CBS_FLUTTER_QUAL_PREFLIGHT_FLUTTER_VERSION)" || value=""
    if [[ "$value" =~ $version_pattern ]]; then
        AN_FLUTTER_VERSION="$value"
    fi

    return 0
}

# --- Execution -----------------------------------------------------------------

# Arguments: FLUTTER_PATH CHECKOUT LIMIT CAP. Runs "flutter analyze" under the
# supervisor and records what it reports. The output of the supervisor is made
# of its own lines only: nothing printed by flutter travels through it.
_cbs_flutter_qual_an_run() {
    local flutter="$1"
    local checkout="$2"
    local limit="$3"
    local cap="$4"
    local rest
    local line
    local started
    local run_pattern='^CBS_ANALYZE_RUN ([0-9]{1,3}) ([0-9]{1,3})$'
    local sup_pattern='^CBS_ANALYZE_SUP ([0-9]{1,3}) ([01])$'

    AN_RUN_SUP_RC=""
    AN_RUN_TIMED_OUT=""
    AN_RUN_COMMAND_RC=""
    AN_RUN_FILTER_RC=""

    started=$SECONDS

    AN_RUN_RAW="$("${BASH:-bash}" -c "$CBS_FLUTTER_QUAL_ANALYZE_SUPERVISOR" cbs-analyze-supervisor \
        "$CBS_FLUTTER_QUAL_ANALYZE_RUNNER" "$limit" "$cap" "$AN_PARTIAL" "$checkout" \
        "$CBS_FLUTTER_QUAL_ANALYZE_CONTRACT" \
        "$flutter" "$CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT" </dev/null 2>/dev/null)"

    AN_DURATION="$((SECONDS - started))"

    rest="$AN_RUN_RAW"

    while [[ -n "$rest" ]]; do
        line="${rest%%"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"*}"

        if [[ "$rest" == *"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"* ]]; then
            rest="${rest#*"$CBS_FLUTTER_QUAL_PREFLIGHT_NL"}"
        else
            rest=""
        fi

        if [[ -z "$AN_RUN_COMMAND_RC" && "$line" =~ $run_pattern ]]; then
            AN_RUN_COMMAND_RC="${BASH_REMATCH[1]}"
            AN_RUN_FILTER_RC="${BASH_REMATCH[2]}"
        elif [[ -z "$AN_RUN_SUP_RC" && "$line" =~ $sup_pattern ]]; then
            AN_RUN_SUP_RC="${BASH_REMATCH[1]}"
            AN_RUN_TIMED_OUT="${BASH_REMATCH[2]}"
        fi
    done
}

# Argument: CAP. Decides the outcome of the run from what the supervisor
# reported and from the size of the capture (never from the text of the log).
_cbs_flutter_qual_an_classify() {
    local cap="$1"
    local sum

    AN_LOG_TRUNCATED="NO"

    if ! sum="$(_cbs_flutter_qual_an_cksum "$AN_PARTIAL")"; then
        _cbs_flutter_qual_an_set "EVIDENCE_FAILURE"
        return 0
    fi

    AN_PARTIAL_BYTES="${sum#* }"

    # More than the limit: the capture stopped one byte after it, flutter was
    # cut by the closed pipe (or ran on until the timeout). The size wins over
    # the status of the tool: it is what was observed.
    if [[ "$((10#$AN_PARTIAL_BYTES))" -gt "$cap" ]]; then
        AN_LOG_TRUNCATED="YES"
        _cbs_flutter_qual_an_set "LOG_LIMIT_EXCEEDED"
        return 0
    fi

    if [[ "$AN_RUN_TIMED_OUT" == "1" ]]; then
        _cbs_flutter_qual_an_set "TIMEOUT"
        return 0
    fi

    # No status from the runner: the tool did not report, nothing is known of it.
    if [[ -z "$AN_RUN_COMMAND_RC" || -z "$AN_RUN_SUP_RC" ]]; then
        _cbs_flutter_qual_an_set "COMMAND_FAILED"
        return 0
    fi

    # The redaction or the capture failed: the evidence cannot be trusted.
    if [[ "$AN_RUN_FILTER_RC" != "0" ]]; then
        _cbs_flutter_qual_an_set "EVIDENCE_FAILURE"
        return 0
    fi

    if [[ "$((10#$AN_RUN_COMMAND_RC))" -ne 0 ]]; then
        _cbs_flutter_qual_an_set "COMMAND_FAILED" "$((10#$AN_RUN_COMMAND_RC))"
        return 0
    fi

    _cbs_flutter_qual_an_pass
}

# Argument: CAP. Turns the capture into the log (at most CAP bytes, exclusive
# create, mode 600) and removes the capture created by this run. Fails when the
# log cannot be written.
_cbs_flutter_qual_an_finalize_log() {
    local cap="$1"
    local sum

    ( umask 077; set -C; head -c "$cap" "$AN_PARTIAL" > "$AN_LOG" ) 2>/dev/null || return 1
    [[ -f "$AN_LOG" && ! -L "$AN_LOG" ]] || return 1

    sum="$(_cbs_flutter_qual_an_cksum "$AN_LOG")" || return 1
    AN_LOG_CRC="${sum%% *}"
    AN_LOG_BYTES="${sum#* }"

    # The capture of this run, at the path computed from validated parts.
    rm -f -- "$AN_PARTIAL" 2>/dev/null || return 1
    [[ ! -e "$AN_PARTIAL" ]]
}

# --- Structured output ---------------------------------------------------------

# Prints a fact only when its value has the shape of a closed word or a number.
# Arguments: NAME VALUE PATTERN
_cbs_flutter_qual_an_fact() {
    local name="$1"
    local value="$2"
    local pattern="$3"

    [[ -n "$value" && "$value" =~ $pattern ]] || return 0

    printf 'CBS_FLUTTER_QUAL_ANALYZE_%s=%s\n' "$name" "$value"
}

# Renders the whole structured answer into AN_BODY (facts, operation, result).
# Returns the contract return code of the reason, or 64 on an inconsistent
# emission.
_cbs_flutter_qual_an_render() {
    local version_pattern='^[0-9]+(\.[0-9]+){0,3}([-+][0-9A-Za-z.+-]+)?$'
    local operation_lines
    local result_lines

    if ! operation_lines="$(cbs_flutter_qual_emit_operation "ANALYZE" "$AN_RESULT" "$AN_REASON" "$AN_TOOL_RC" 2>/dev/null)" ||
        ! result_lines="$(cbs_flutter_qual_emit_result "$AN_RESULT" "$AN_REASON" 2>/dev/null)"; then
        AN_BODY=""
        return "$CBS_RC_FLUTTER_QUAL_USAGE"
    fi

    AN_BODY="$(
        [[ -z "$AN_REJECTED_KEY" ]] ||
            printf 'CBS_FLUTTER_QUAL_ANALYZE_REJECTED_KEY=%s\n' "$AN_REJECTED_KEY"

        if [[ -n "$AN_QUALIFICATION_ID" ]] && cbs_flutter_qual_id_valid "$AN_QUALIFICATION_ID"; then
            printf 'CBS_FLUTTER_QUAL_ANALYZE_QUALIFICATION_ID=%s\n' "$AN_QUALIFICATION_ID"
        fi

        _cbs_flutter_qual_an_fact "PREFLIGHT_RESULT" "$AN_PREFLIGHT_RESULT" '^(PASS|FAIL|BLOCKED|SKIPPED|NOT_RUN)$'
        _cbs_flutter_qual_an_fact "PREFLIGHT_REASON" "$AN_PREFLIGHT_REASON" '^[A-Z][A-Z0-9_]{0,63}$'

        if [[ -n "$AN_COMMIT" ]] && cbs_flutter_qual_commit_valid "$AN_COMMIT"; then
            printf 'CBS_FLUTTER_QUAL_ANALYZE_COMMIT_OBSERVED=%s\n' "$AN_COMMIT"
        fi

        _cbs_flutter_qual_an_fact "FLUTTER_VERSION" "$AN_FLUTTER_VERSION" "$version_pattern"

        # A command that was never started has no duration, no log.
        if [[ -n "$AN_DURATION" ]]; then
            printf 'CBS_FLUTTER_QUAL_ANALYZE_COMMAND=flutter_analyze\n'
            _cbs_flutter_qual_an_fact "DURATION_SECONDS" "$AN_DURATION" '^[0-9]{1,9}$'
            _cbs_flutter_qual_an_fact "LOG_BYTES" "$AN_LOG_BYTES" '^[0-9]{1,12}$'
            _cbs_flutter_qual_an_fact "LOG_CRC" "$AN_LOG_CRC" '^[0-9]{1,10}$'
            _cbs_flutter_qual_an_fact "LOG_TRUNCATED" "$AN_LOG_TRUNCATED" '^(YES|NO)$'
        fi

        printf 'CBS_FLUTTER_QUAL_ANALYZE_EVIDENCE=%s\n' "$AN_EVIDENCE"
        printf '%s\n' "$operation_lines"
        printf '%s\n' "$result_lines"
    )"

    return 0
}

# Writes AN_BODY as ANALYZE.result (exclusive create, mode 600).
_cbs_flutter_qual_an_write_result() {
    ( umask 077; set -C; printf '%s\n' "$AN_BODY" > "$AN_RESULT_FILE" ) 2>/dev/null || return 1
    [[ -f "$AN_RESULT_FILE" && ! -L "$AN_RESULT_FILE" ]]
}

# Prints the answer and returns the contract return code of the reason. The
# RESULT line is the last line of stdout; the reason is repeated on stderr.
_cbs_flutter_qual_an_conclude() {
    if [[ "$AN_STARTED" == "1" ]]; then
        # A PASS never survives a log that could not be written ...
        if [[ "$AN_EVIDENCE" == "FAILED" && "$AN_RESULT" == "PASS" ]]; then
            _cbs_flutter_qual_an_set "EVIDENCE_FAILURE"
        fi

        # ... nor an answer that could not be written: the file holds exactly
        # the answer that is printed.
        _cbs_flutter_qual_an_render || true

        if ! _cbs_flutter_qual_an_write_result; then
            AN_EVIDENCE="FAILED"

            if [[ "$AN_RESULT" == "PASS" ]]; then
                _cbs_flutter_qual_an_set "EVIDENCE_FAILURE"
            fi
        fi
    fi

    if ! _cbs_flutter_qual_an_render; then
        echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
        return "$CBS_RC_FLUTTER_QUAL_USAGE"
    fi

    printf '%s\n' "$AN_BODY"

    if [[ -n "$AN_REASON" ]]; then
        printf 'CBS_FLUTTER_QUAL_ERROR=%s\n' "$AN_REASON" >&2
    fi

    return "$(cbs_flutter_qual_rc_for_reason "$AN_REASON")"
}

# --- Entry ---------------------------------------------------------------------

# Arguments: KEY=VALUE... (the request).
cbs_flutter_qual_analyze() {
    local reason
    local actions
    local isolation_id
    local isolation_root
    local evidence_root
    local timeout
    local cap
    local checkout
    local flutter

    _cbs_flutter_qual_an_reset

    if [[ "$#" -eq 0 ]]; then
        _cbs_flutter_qual_an_set "USAGE"
        _cbs_flutter_qual_an_conclude
        return $?
    fi

    # ---- 1. request

    if ! cbs_flutter_qual_validate_request "$@"; then
        reason="$CBS_FLUTTER_QUAL_VALIDATION_REASON"
        AN_REJECTED_KEY="$CBS_FLUTTER_QUAL_VALIDATION_KEY"

        cbs_flutter_qual_reason_is_valid "$reason" || reason="INPUT_INVALID"

        _cbs_flutter_qual_an_set "$reason"
        _cbs_flutter_qual_an_conclude
        return $?
    fi

    actions="$(cbs_flutter_qual_entries_get actions "$@")"

    # This operation is the ANALYZE: it must have been selected.
    case ",$actions," in
        *,analyze,*) ;;
        *)
            AN_REJECTED_KEY="actions"
            _cbs_flutter_qual_an_set "ACTION_NOT_ALLOWED"
            _cbs_flutter_qual_an_conclude
            return $?
            ;;
    esac

    AN_QUALIFICATION_ID="$(cbs_flutter_qual_entries_get qualification_id "$@")"
    isolation_id="$(cbs_flutter_qual_entries_get isolation_id "$@")"
    isolation_root="$(cbs_flutter_qual_entries_get isolation_root "$@")"
    evidence_root="$(cbs_flutter_qual_entries_get evidence_root "$@")"
    timeout="$(cbs_flutter_qual_entries_get timeout_seconds "$@")"
    cap="$(cbs_flutter_qual_entries_get log_max_bytes "$@")"

    timeout="$((10#$timeout))"
    cap="$((10#$cap))"

    # ---- 2. evidence location (nothing is created yet)

    if ! _cbs_flutter_qual_an_check_evidence "$evidence_root" "$AN_QUALIFICATION_ID"; then
        AN_REJECTED_KEY="evidence_root"
        _cbs_flutter_qual_an_set "PATH_NOT_ALLOWED"
        _cbs_flutter_qual_an_conclude
        return $?
    fi

    # ---- 3. PREFLIGHT must be PASS (it verifies the checkout and the toolchain)

    if ! _cbs_flutter_qual_an_gate "$@"; then
        _cbs_flutter_qual_an_set "PREFLIGHT_NOT_PASSED"
        _cbs_flutter_qual_an_conclude
        return $?
    fi

    # ---- 4. the command and its working directory

    checkout="$isolation_root/$isolation_id"

    if [[ -L "$checkout" ]] || ! cbs_flutter_qual_dir_is_canonical "$checkout"; then
        _cbs_flutter_qual_an_set "ISOLATION_REJECTED"
        _cbs_flutter_qual_an_conclude
        return $?
    fi

    if ! flutter="$(_cbs_flutter_qual_pf_find_tool flutter)"; then
        _cbs_flutter_qual_an_set "TOOL_UNAVAILABLE"
        _cbs_flutter_qual_an_conclude
        return $?
    fi

    # ---- 5. evidence, then the command

    if ! _cbs_flutter_qual_an_check_evidence "$evidence_root" "$AN_QUALIFICATION_ID" ||
        ! _cbs_flutter_qual_an_create_evidence; then
        AN_REJECTED_KEY="evidence_root"
        _cbs_flutter_qual_an_set "PATH_NOT_ALLOWED"
        _cbs_flutter_qual_an_conclude
        return $?
    fi

    AN_STARTED="1"
    AN_EVIDENCE="WRITTEN"

    _cbs_flutter_qual_an_run "$flutter" "$checkout" "$timeout" "$cap"
    _cbs_flutter_qual_an_classify "$cap"

    # The log survives every outcome, including a failure or a timeout.
    _cbs_flutter_qual_an_finalize_log "$cap" || AN_EVIDENCE="FAILED"

    _cbs_flutter_qual_an_conclude
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -u
    CBS_FLUTTER_QUAL_ANALYZE_RC=0
    cbs_flutter_qual_analyze "$@" || CBS_FLUTTER_QUAL_ANALYZE_RC=$?
    exit "$CBS_FLUTTER_QUAL_ANALYZE_RC"
fi
