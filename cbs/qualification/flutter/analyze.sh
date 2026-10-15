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
# What is common to the operations (the steps below, the bounded execution, the
# evidence, the structured answer) lives in execution.sh (D04b-C.2e), which this
# file sources. This file keeps what belongs to ANALYZE: the selected action,
# the fixed argument, the lookup of flutter and the order of the steps.
#
# What this operation writes, and only this, under evidence_root (which must
# already exist: it is never created here):
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
# Compatible with Bash 3.2 (macOS) and later: no associative array, no empty
# array expansion, no case conversion expansion, no here-string, no GNU-only
# option. BSD tools only.

unset CDPATH

CBS_FLUTTER_QUAL_ANALYZE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [[ -z "$CBS_FLUTTER_QUAL_ANALYZE_DIR" || ! -f "$CBS_FLUTTER_QUAL_ANALYZE_DIR/execution.sh" ]]; then
    echo "CBS_FLUTTER_QUAL_ERROR=EXECUTION_UNAVAILABLE" >&2
    return 1 2>/dev/null || exit 1
fi

# The common execution engine: it sources PREFLIGHT (which loads the contract,
# scrubs the environment of Git and BASH_ENV, and exposes the helpers reused
# below). Nothing runs when sourced.
# shellcheck source=/dev/null
source "$CBS_FLUTTER_QUAL_ANALYZE_DIR/execution.sh"

# The one and only argument given to flutter. Never built from anything.
readonly CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT="analyze"

# --- Entry ---------------------------------------------------------------------

# Arguments: KEY=VALUE... (the request).
cbs_flutter_qual_analyze() {
    local flutter

    _cbs_flutter_qual_ex_reset "$CBS_FLUTTER_QUAL_OP_ANALYZE" "flutter_analyze"

    # ---- 1. request (this operation is the ANALYZE: it must have been selected)

    if ! _cbs_flutter_qual_ex_request "$@"; then
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

    # ---- 4. the command and its working directory

    if ! _cbs_flutter_qual_ex_checkout; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    if ! flutter="$(_cbs_flutter_qual_pf_find_tool flutter)"; then
        _cbs_flutter_qual_ex_set "TOOL_UNAVAILABLE"
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 5. evidence, then the command

    if ! _cbs_flutter_qual_ex_evidence_open; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    _cbs_flutter_qual_ex_execute "$flutter" "$CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT"

    _cbs_flutter_qual_ex_conclude
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -u
    CBS_FLUTTER_QUAL_ANALYZE_RC=0
    cbs_flutter_qual_analyze "$@" || CBS_FLUTTER_QUAL_ANALYZE_RC=$?
    exit "$CBS_FLUTTER_QUAL_ANALYZE_RC"
fi
