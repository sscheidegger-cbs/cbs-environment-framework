#!/usr/bin/env bash

# D04b-C.2f - Flutter/iOS qualification: TEST.
#
#   test.sh KEY=VALUE...
#
# The arguments are the request defined by contract.sh (data only). TEST runs
# one "flutter test" in the isolated checkout, and nothing else. Everything
# that does not depend on the operation (request validation, evidence
# location, PREFLIGHT gate, checkout check, bounded supervised execution,
# timeout, redaction, log bound, classification, structured answer, evidence
# files) is the common execution engine, execution.sh (D04b-C.2e), which this
# file sources and does not duplicate. This file keeps what belongs to TEST:
# the selected action, the selection of the tests, the lookup of flutter, the
# check of the simulator of an integration run and the order of the steps.
#
# Selection (test_scope, test_targets and simulator_udid of the request):
#
#   unit_widget, no test_targets   flutter test
#   unit_widget, test_targets      flutter test <file>...
#   integration, test_targets      flutter test <file>... -d <simulator_udid>
#   integration, no test_targets   refused, see below
#
# The words "test" and "-d" are constants of this file. The only values of the
# request that reach the command line are the test files (already validated by
# the contract: relative, "test/" or "integration_test/" according to the
# scope, "_test.dart", no "..", no glob, no space, at most 16, no duplicate)
# and, for an integration run, the explicit simulator identifier (8-4-4-4-12
# hexadecimal). They are separate words of a command that is never parsed by a
# shell: no eval, no source of the request, no option and no Flutter argument
# supplied by a caller, no secret and no dart-define (the contract refuses
# them), no argument built from the checkout.
#
# Test files are checked in the isolated checkout, before anything runs: no
# component of the path (the "test" directory included) is a symbolic link, the
# file exists and is a regular file. A missing file is INPUT_INVALID, a link or
# a file that is not regular is PATH_NOT_ALLOWED (key test_targets), nothing is
# executed and nothing is written. Without test_targets, the "test" directory
# of the checkout must not be, nor hold, a symbolic link (PATH_NOT_ALLOWED). A
# missing "test" directory is left to flutter, which reports it (FAIL).
#
# OPEN CONTRACT DECISION, handled explicitly here and not by changing the
# contract. contract.sh accepts test_scope=integration without test_targets.
# No selection command that is both safe and explicit can be derived from that
# request: "flutter test" alone runs the "test" directory, not the integration
# tests, and naming the "integration_test" directory would be a selection that
# the caller never validated (and a Flutter behaviour that is not confirmed on
# a real toolchain). TEST therefore refuses that request on its own: BLOCKED,
# INPUT_INVALID (121), rejected key test_targets, before PREFLIGHT, nothing
# executed, nothing written. contract.sh is unchanged; the decision on the
# contract rule is left open (README, "TEST").
#
# Simulator (integration only). PREFLIGHT must be PASS first (it verifies that
# the simulator exists under an iOS runtime). Then the state of the requested
# simulator is observed again, read-only, with the observation of
# preflight.sh ("xcrun simctl list devices"), and the run starts only when it
# is BOOTED. A SHUTDOWN or TRANSITIONAL simulator, a simulator that vanished or
# a failed observation is BLOCKED, SIMULATOR_UNAVAILABLE (129): TEST never
# boots, creates, erases or deletes a simulator. For unit_widget, a given
# simulator_udid is not used (PREFLIGHT still checks that it exists).
#
# What this operation writes, and only this, under evidence_root (which must
# already exist: it is never created here):
#   <evidence_root>/<qualification_id>/TEST.log      redacted, bounded output
#   <evidence_root>/<qualification_id>/TEST.result   the structured answer
# Files are created with an exclusive create (never overwritten), mode 600, in
# a directory of mode 700 (engine). An evidence file that already exists
# refuses the run (PATH_NOT_ALLOWED): a new qualification_id is needed.
#
# What flutter itself may write is out of this file's control: the checkout
# (.dart_tool/, build/, pubspec.lock, ...) and the caches of the user. The
# source repository is never a working directory, never written, never read.
#
# Results (contract.sh):
#   PASS     flutter exited with 0 (tool status 0)
#   FAIL     COMMAND_FAILED (flutter exited non-zero, its exact status is
#            OPERATION_TOOL_RC), TIMEOUT, LOG_LIMIT_EXCEEDED, EVIDENCE_FAILURE
#   BLOCKED  request refused (including integration without test_targets),
#            PATH_NOT_ALLOWED (evidence location, link or irregular test file),
#            INPUT_INVALID (missing test file), ISOLATION_REJECTED (checkout
#            path), TOOL_UNAVAILABLE (flutter vanished after PREFLIGHT),
#            SIMULATOR_UNAVAILABLE (simulator not BOOTED)
#   NOT_RUN  PREFLIGHT_NOT_PASSED
# NETWORK_FAILURE is never emitted (the real messages of the tool are not
# frozen).
#
# Compatible with Bash 3.2 (macOS) and later: no associative array, no empty
# array expansion, no case conversion expansion, no here-string, no GNU-only
# option. BSD tools only.

unset CDPATH

CBS_FLUTTER_QUAL_TESTOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [[ -z "$CBS_FLUTTER_QUAL_TESTOP_DIR" || ! -f "$CBS_FLUTTER_QUAL_TESTOP_DIR/execution.sh" ]]; then
    echo "CBS_FLUTTER_QUAL_ERROR=EXECUTION_UNAVAILABLE" >&2
    return 1 2>/dev/null || exit 1
fi

# The common execution engine: it sources PREFLIGHT (which loads the contract,
# scrubs the environment of Git and BASH_ENV, and exposes the helpers reused
# below). Nothing runs when sourced.
# shellcheck source=/dev/null
source "$CBS_FLUTTER_QUAL_TESTOP_DIR/execution.sh"

# The words of the command that belong to this file. Never built from anything.
readonly CBS_FLUTTER_QUAL_TESTOP_ARGUMENT="test"
readonly CBS_FLUTTER_QUAL_TESTOP_DEVICE_OPTION="-d"

# --- State -----------------------------------------------------------------------

# Every variable is set here: none comes from the environment.
_cbs_flutter_qual_tst_reset() {
    TST_SCOPE=""
    TST_TARGETS=""
    TST_UDID=""
    TST_COMMAND=("")
}

# --- Selection -------------------------------------------------------------------

# Arguments: ENTRY... (the request, already validated by the engine). Reads the
# selection from it and applies the rules of this operation on top of the
# contract. Returns 1 after recording the refusal.
_cbs_flutter_qual_tst_selection() {
    TST_SCOPE="$(cbs_flutter_qual_entries_get test_scope "$@" || true)"
    TST_TARGETS="$(cbs_flutter_qual_entries_get test_targets "$@" || true)"
    TST_UDID="$(cbs_flutter_qual_entries_get simulator_udid "$@" || true)"

    case "$TST_SCOPE" in
        "$CBS_FLUTTER_QUAL_TEST_SCOPE_UNIT_WIDGET")
            # No device is used: a simulator given for another purpose never
            # reaches the command.
            TST_UDID=""
            return 0
            ;;
        "$CBS_FLUTTER_QUAL_TEST_SCOPE_INTEGRATION")
            ;;
        *)
            EX_REJECTED_KEY="test_scope"
            _cbs_flutter_qual_ex_set "INPUT_INVALID"
            return 1
            ;;
    esac

    # Accepted by the contract, not by this operation: see the header.
    if [[ -z "$TST_TARGETS" ]]; then
        EX_REJECTED_KEY="test_targets"
        _cbs_flutter_qual_ex_set "INPUT_INVALID"
        return 1
    fi

    if [[ -z "$TST_UDID" ]] || [[ ! "$TST_UDID" =~ $CBS_FLUTTER_QUAL_PATTERN_SIMULATOR_UDID ]]; then
        EX_REJECTED_KEY="simulator_udid"
        _cbs_flutter_qual_ex_set "INPUT_INVALID"
        return 1
    fi

    return 0
}

# Argument: TARGET (relative path, "/" separated). Reads the checkout only.
# Returns 0 when every component is neither a link nor a "." / ".." component,
# every directory is a directory and the last component is a regular file;
# 1 when something is absent; 2 when it is refused (link, not regular).
_cbs_flutter_qual_tst_check_path() {
    local rest="$1"
    local current="$EX_CHECKOUT"
    local component

    [[ "$rest" =~ $CBS_FLUTTER_QUAL_PATTERN_TEST_TARGET ]] || return 2

    while [[ -n "$rest" ]]; do
        component="${rest%%/*}"

        if [[ "$rest" == */* ]]; then
            rest="${rest#*/}"
        else
            rest=""
        fi

        case "$component" in
            ""|.|..)
                return 2
                ;;
        esac

        current="$current/$component"

        if [[ -L "$current" ]]; then
            return 2
        fi

        [[ -e "$current" ]] || return 1

        if [[ -n "$rest" ]]; then
            [[ -d "$current" ]] || return 1
        else
            [[ -f "$current" ]] || return 2
        fi
    done

    return 0
}

# Without explicit target, flutter reads the whole "test" directory of the
# checkout: neither it nor anything below it may be a symbolic link. A missing
# directory is not refused here (flutter reports it). Returns 0 or 1.
_cbs_flutter_qual_tst_check_default_tree() {
    local dir="$EX_CHECKOUT/test"
    local found

    if [[ -L "$dir" ]]; then
        return 1
    fi

    [[ -d "$dir" ]] || return 0

    found="$(find "$dir" -type l 2>/dev/null)" || return 1

    [[ -z "$found" ]]
}

# Checks, in the isolated checkout and without writing, what flutter will be
# given. Records the refusal and returns 1 when it is not acceptable.
_cbs_flutter_qual_tst_check_selection() {
    local rest="$TST_TARGETS"
    local target
    local status

    if [[ -z "$rest" ]]; then
        if ! _cbs_flutter_qual_tst_check_default_tree; then
            EX_REJECTED_KEY="test_scope"
            _cbs_flutter_qual_ex_set "PATH_NOT_ALLOWED"
            return 1
        fi

        return 0
    fi

    EX_REJECTED_KEY="test_targets"

    while [[ -n "$rest" ]]; do
        target="${rest%%,*}"

        if [[ "$rest" == *,* ]]; then
            rest="${rest#*,}"
        else
            rest=""
        fi

        status=0
        _cbs_flutter_qual_tst_check_path "$target" || status=$?

        case "$status" in
            0)
                ;;
            1)
                _cbs_flutter_qual_ex_set "INPUT_INVALID"
                return 1
                ;;
            *)
                _cbs_flutter_qual_ex_set "PATH_NOT_ALLOWED"
                return 1
                ;;
        esac
    done

    EX_REJECTED_KEY=""
    return 0
}

# --- Simulator ---------------------------------------------------------------------

# An integration run needs a simulator that is already BOOTED. It is observed
# with the read-only probes of preflight.sh and never changed. Records the
# refusal and returns 1 otherwise.
_cbs_flutter_qual_tst_check_simulator() {
    _cbs_flutter_qual_pf_reset
    PF_TIMEOUT="$EX_TIMEOUT"

    _cbs_flutter_qual_pf_check_simctl

    if [[ "$(_cbs_flutter_qual_pf_result SIMCTL)" == "PASS" ]]; then
        _cbs_flutter_qual_pf_check_simulator "$TST_UDID"

        if [[ "$(_cbs_flutter_qual_pf_result SIMULATOR)" == "PASS" && "$PF_SIMULATOR_STATE" == "BOOTED" ]]; then
            return 0
        fi
    fi

    EX_REJECTED_KEY="simulator_udid"
    _cbs_flutter_qual_ex_set "SIMULATOR_UNAVAILABLE"
    return 1
}

# --- Command ---------------------------------------------------------------------

# Argument: FLUTTER (absolute path found by the lookup of PREFLIGHT). Sets
# TST_COMMAND, which is never empty.
_cbs_flutter_qual_tst_build_command() {
    local rest="$TST_TARGETS"
    local target

    TST_COMMAND=("$1" "$CBS_FLUTTER_QUAL_TESTOP_ARGUMENT")

    while [[ -n "$rest" ]]; do
        target="${rest%%,*}"

        if [[ "$rest" == *,* ]]; then
            rest="${rest#*,}"
        else
            rest=""
        fi

        TST_COMMAND[${#TST_COMMAND[@]}]="$target"
    done

    if [[ "$TST_SCOPE" == "$CBS_FLUTTER_QUAL_TEST_SCOPE_INTEGRATION" ]]; then
        TST_COMMAND[${#TST_COMMAND[@]}]="$CBS_FLUTTER_QUAL_TESTOP_DEVICE_OPTION"
        TST_COMMAND[${#TST_COMMAND[@]}]="$TST_UDID"
    fi
}

# --- Entry -------------------------------------------------------------------------

# Arguments: KEY=VALUE... (the request).
cbs_flutter_qual_test() {
    local flutter

    _cbs_flutter_qual_ex_reset "$CBS_FLUTTER_QUAL_OP_TEST" "flutter_test"
    _cbs_flutter_qual_tst_reset

    # ---- 1. request (this operation is the TEST: it must have been selected)

    if ! _cbs_flutter_qual_ex_request "$@"; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    if ! _cbs_flutter_qual_tst_selection "$@"; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 2. evidence location (nothing is created yet)

    if ! _cbs_flutter_qual_ex_evidence_location; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 3. PREFLIGHT must be PASS (it verifies the checkout and the toolchain)

    if ! _cbs_flutter_qual_ex_preflight_gate "$@"; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 4. the checkout and the tool

    if ! _cbs_flutter_qual_ex_checkout; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    if ! flutter="$(_cbs_flutter_qual_pf_find_tool flutter)"; then
        _cbs_flutter_qual_ex_set "TOOL_UNAVAILABLE"
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 5. what flutter will be given, in the isolated checkout

    if ! _cbs_flutter_qual_tst_check_selection; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 6. the simulator of an integration run must already be BOOTED

    if [[ "$TST_SCOPE" == "$CBS_FLUTTER_QUAL_TEST_SCOPE_INTEGRATION" ]]; then
        if ! _cbs_flutter_qual_tst_check_simulator; then
            _cbs_flutter_qual_ex_conclude
            return $?
        fi
    fi

    # ---- 7. evidence, then the command

    if ! _cbs_flutter_qual_ex_evidence_open; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    _cbs_flutter_qual_tst_build_command "$flutter"
    _cbs_flutter_qual_ex_execute "${TST_COMMAND[@]}"

    _cbs_flutter_qual_ex_conclude
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -u
    CBS_FLUTTER_QUAL_TESTOP_RC=0
    cbs_flutter_qual_test "$@" || CBS_FLUTTER_QUAL_TESTOP_RC=$?
    exit "$CBS_FLUTTER_QUAL_TESTOP_RC"
fi
