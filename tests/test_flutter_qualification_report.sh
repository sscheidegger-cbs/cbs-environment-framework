#!/usr/bin/env bash

# D04b-C.2h: hermetic test of the Flutter/iOS qualification REPORT.
#
# Proportionate on purpose: REPORT only reads the ".result" files that the
# executors leave under <evidence_root>/<qualification_id>/. The mechanisms of
# the engine (execution.sh) and of the executors are qualified by their own
# suites and are not requalified here: the answers read by REPORT are written by
# this test, line for line as the engine writes them, in a private directory.
# No Git repository, no isolation, no real or simulated toolchain is needed.
#
# Covered, and only this:
#
#   1. consolidation of coherent answers (PASS, FAIL, SKIPPED, never PASS for
#      what was not observed);
#   2. an absent operation (NOT_RUN, never invented);
#   3. an incoherent or malformed answer (BLOCKED, never read as shell, never
#      echoed);
#   4. protection against symbolic links;
#   5. no external qualification tool is ever called, nothing is written.
#
# Nothing here qualifies a real Mac: see the BASH32 line for the one check that
# needs a native Bash 3.2.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$ROOT/cbs/qualification/flutter/report.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_REPORT"

source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$CONTRACT"

[[ -f "$REPORT" ]] || fq_fail "REPORT_MISSING"
bash -n "$REPORT" || fq_fail "REPORT_SYNTAX"

fq_init
fq_shims_install

# Files written by this test are private, whatever the umask of the host: REPORT
# refuses an answer that group or others could have written.
umask 077

EVID="$FQ_TMP/evidence"
OUTSIDE="$FQ_TMP/outside"
STATE="$FQ_TMP/state"
PWNED="$FQ_TMP/pwned"
mkdir -m 700 "$EVID" "$OUTSIDE" "$STATE"

RP_OUT=""
RP_ERR=""
RP_RC=0

rp_pass() {
    echo "${TEST_PREFIX}_$1=PASS"
}

# The forbidden-tool shims must be effective: a call is logged and fails with 99.
set +e
env PATH="$FQ_SHIM_BIN:$PATH" flutter --version >/dev/null 2>&1
SHIM_RC=$?
set -e
[[ "$SHIM_RC" -eq 99 && -s "$FQ_SHIM_LOG" ]] || fq_fail "SHIM_NOT_EFFECTIVE"
: > "$FQ_SHIM_LOG"

# ---------------------------------------------------------------- helpers

# rp_answer OPERATION RESULT REASON TOOL_RC QUALIFICATION_ID COMMIT
# Prints an answer with the lines and the order of the engine (facts, then the
# operation, then the final result). RP_EXTRA, when set, is one more line placed
# before the operation line.
rp_answer() {
    local operation="$1"
    local result="$2"
    local reason="$3"
    local tool_rc="$4"
    local qualification_id="$5"
    local commit="$6"
    local rc

    rc="$(cbs_flutter_qual_rc_for_reason "$reason")"

    printf 'CBS_FLUTTER_QUAL_%s_QUALIFICATION_ID=%s\n' "$operation" "$qualification_id"
    printf 'CBS_FLUTTER_QUAL_%s_PREFLIGHT_RESULT=PASS\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_%s_COMMIT_OBSERVED=%s\n' "$operation" "$commit"
    printf 'CBS_FLUTTER_QUAL_%s_FLUTTER_VERSION=3.47.6\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_%s_COMMAND=flutter_run\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_%s_DURATION_SECONDS=3\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_%s_LOG_BYTES=120\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_%s_LOG_CRC=1234567\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_%s_LOG_TRUNCATED=NO\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_%s_EVIDENCE=WRITTEN\n' "$operation"

    if [[ -n "${RP_EXTRA:-}" ]]; then
        printf '%s\n' "$RP_EXTRA"
    fi

    printf 'CBS_FLUTTER_QUAL_OPERATION=%s\n' "$operation"
    printf 'CBS_FLUTTER_QUAL_OPERATION_RESULT=%s\n' "$result"

    if [[ -n "$reason" ]]; then
        printf 'CBS_FLUTTER_QUAL_OPERATION_REASON=%s\n' "$reason"
    fi

    printf 'CBS_FLUTTER_QUAL_OPERATION_RC=%s\n' "$rc"

    if [[ -n "$tool_rc" ]]; then
        printf 'CBS_FLUTTER_QUAL_OPERATION_TOOL_RC=%s\n' "$tool_rc"
    fi

    if [[ -n "$reason" ]]; then
        printf 'CBS_FLUTTER_QUAL_REASON=%s\n' "$reason"
    fi

    printf 'CBS_FLUTTER_QUAL_CONTRACT_VERSION=1\n'
    printf 'CBS_FLUTTER_QUAL_RESULT=%s\n' "$result"
}

# rp_dir ID: a private evidence directory, as the engine creates it.
rp_dir() {
    mkdir -m 700 "$EVID/$1"
}

# rp_put ID OPERATION RESULT REASON TOOL_RC [QUALIFICATION_ID_IN_FILE] [COMMIT_IN_FILE]
rp_put() {
    local id="$1"

    rp_answer "$2" "$3" "$4" "$5" "${6:-$id}" "${7:-$FQ_COMMIT}" > "$EVID/$id/$2.result"
    chmod 600 "$EVID/$id/$2.result"
}

# Observable state of what REPORT must leave untouched (names and contents).
rp_fingerprint() {
    (
        cd "$FQ_TMP"
        find evidence outside -print | LC_ALL=C sort
        find evidence outside -type f -exec cksum {} \; | LC_ALL=C sort
    )
}

# rp_run LABEL BASH ARGUMENT...
# Runs REPORT with the forbidden-tool shims first in PATH. Sets RP_OUT, RP_ERR
# and RP_RC, and fails when anything under the evidence changed or a forbidden
# tool was called.
rp_run() {
    local label="$1"
    local shell="$2"
    local before
    local after

    shift 2

    before="$(rp_fingerprint)"

    set +e
    RP_OUT="$(cd "$FQ_TMP" && env PATH="$FQ_SHIM_BIN:$PATH" "$shell" "$REPORT" "$@" 2>"$STATE/stderr")"
    RP_RC=$?
    set -e

    RP_ERR="$(cat "$STATE/stderr")"
    after="$(rp_fingerprint)"

    [[ "$before" == "$after" ]] || fq_fail "${label}_EVIDENCE_MUTATED"
    fq_shims_assert_unused "$label"
}

# rp_req ACTIONS [QUALIFICATION_ID] [EVIDENCE_ROOT]: the reference request of the
# contract, with the actions and the location of the evidence of this case.
rp_req() {
    fq_request_reset
    fq_request_set qualification_id "${2:-qual-report-1}"
    fq_request_set evidence_root "${3:-$EVID}"
    fq_request_set actions "$1"

    case ",$1," in
        *,test,*) ;;
        *)
            fq_request_unset test_scope
            fq_request_unset test_targets
            ;;
    esac
}

# Value of a full key in the last answer, first match.
rp_kv() {
    printf '%s\n' "$RP_OUT" | sed -n "s/^$1=//p" | head -n 1
}

# rp_expect LABEL RESULT REASON|- RC: the answer of REPORT itself.
rp_expect() {
    local label="$1"
    local result="$2"
    local reason="$3"
    local rc="$4"

    [[ "$RP_RC" -eq "$rc" ]] || fq_fail "${label}_RC_EXPECTED_${rc}_GOT_${RP_RC}"
    [[ "$(rp_kv CBS_FLUTTER_QUAL_OPERATION)" == "REPORT" ]] || fq_fail "${label}_OPERATION"
    [[ "$(rp_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)" == "$result" ]] || fq_fail "${label}_OPERATION_RESULT_$(rp_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)"
    [[ "$(rp_kv CBS_FLUTTER_QUAL_RESULT)" == "$result" ]] || fq_fail "${label}_RESULT_$(rp_kv CBS_FLUTTER_QUAL_RESULT)"
    [[ "$(rp_kv CBS_FLUTTER_QUAL_OPERATION_RC)" == "$rc" ]] || fq_fail "${label}_OPERATION_RC_$(rp_kv CBS_FLUTTER_QUAL_OPERATION_RC)"
    [[ "$(rp_kv CBS_FLUTTER_QUAL_CONTRACT_VERSION)" == "1" ]] || fq_fail "${label}_CONTRACT_VERSION"
    [[ "$(printf '%s\n' "$RP_OUT" | tail -n 1)" == "CBS_FLUTTER_QUAL_RESULT=$result" ]] || fq_fail "${label}_RESULT_NOT_LAST"

    if [[ "$reason" == "-" ]]; then
        [[ -z "$(rp_kv CBS_FLUTTER_QUAL_REASON)" ]] || fq_fail "${label}_UNEXPECTED_REASON"
        [[ -z "$(rp_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" ]] || fq_fail "${label}_UNEXPECTED_OPERATION_REASON"
        [[ -z "$RP_ERR" ]] || fq_fail "${label}_STDERR_ON_PASS"
    else
        [[ "$(rp_kv CBS_FLUTTER_QUAL_REASON)" == "$reason" ]] || fq_fail "${label}_REASON_EXPECTED_${reason}_GOT_$(rp_kv CBS_FLUTTER_QUAL_REASON)"
        [[ "$(rp_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" == "$reason" ]] || fq_fail "${label}_OPERATION_REASON"
        [[ "$(cbs_flutter_qual_rc_for_reason "$reason")" == "$rc" ]] || fq_fail "${label}_REASON_RC_DISAGREE"
        [[ "$(cbs_flutter_qual_result_for_reason "$reason")" == "$result" ]] || fq_fail "${label}_REASON_CLASS_DISAGREE"
        [[ "$RP_ERR" == "CBS_FLUTTER_QUAL_ERROR=$reason" ]] || fq_fail "${label}_STDERR"
    fi

    # Every stdout line is a closed fact of the contract namespace.
    if printf '%s\n' "$RP_OUT" | grep -v '^CBS_FLUTTER_QUAL_[A-Z0-9_]*=[A-Za-z0-9._+-]*$' >/dev/null; then
        fq_fail "${label}_FOREIGN_OUTPUT_LINE"
    fi
}

# rp_op_expect LABEL OPERATION RESULT REASON|- RC EVIDENCE [TOOL_RC|-]
rp_op_expect() {
    local label="$1"
    local operation="$2"
    local reason="$4"
    local prefix="CBS_FLUTTER_QUAL_REPORT_${2}"

    [[ "$(rp_kv "${prefix}_RESULT")" == "$3" ]] || fq_fail "${label}_${operation}_RESULT_EXPECTED_${3}_GOT_$(rp_kv "${prefix}_RESULT")"
    [[ "$(rp_kv "${prefix}_RC")" == "$5" ]] || fq_fail "${label}_${operation}_RC_$(rp_kv "${prefix}_RC")"
    [[ "$(rp_kv "${prefix}_EVIDENCE")" == "$6" ]] || fq_fail "${label}_${operation}_EVIDENCE_$(rp_kv "${prefix}_EVIDENCE")"

    if [[ "$reason" == "-" ]]; then
        [[ -z "$(rp_kv "${prefix}_REASON")" ]] || fq_fail "${label}_${operation}_UNEXPECTED_REASON"
    else
        [[ "$(rp_kv "${prefix}_REASON")" == "$reason" ]] || fq_fail "${label}_${operation}_REASON_$(rp_kv "${prefix}_REASON")"
    fi

    if [[ "${7:-}" == "-" ]]; then
        [[ -z "$(rp_kv "${prefix}_TOOL_RC")" ]] || fq_fail "${label}_${operation}_UNEXPECTED_TOOL_RC"
    elif [[ -n "${7:-}" ]]; then
        [[ "$(rp_kv "${prefix}_TOOL_RC")" == "$7" ]] || fq_fail "${label}_${operation}_TOOL_RC_$(rp_kv "${prefix}_TOOL_RC")"
    fi
}

# rp_expect_bad LABEL [ID]: ANALYZE.result of the directory ID (default
# qual-bad) was written by the case; it must be refused as incoherent, never
# turned into a result, never executed, never echoed.
rp_expect_bad() {
    local label="$1"
    local id="${2:-qual-bad}"

    rp_req "preflight,analyze,report" "$id"
    rp_run "$label" "$BASH" "${FQ_REQUEST[@]}"

    rp_expect "$label" BLOCKED INPUT_INVALID 121
    rp_op_expect "$label" ANALYZE BLOCKED INPUT_INVALID 121 REJECTED -
    rp_op_expect "$label" PREFLIGHT NOT_RUN NOT_EXECUTED 135 ABSENT -
    rp_op_expect "$label" TEST SKIPPED NOT_SELECTED 137 NOT_SELECTED -
    rp_op_expect "$label" BUILD_IOS SKIPPED NOT_SELECTED 137 NOT_SELECTED -

    [[ ! -e "$PWNED" ]] || fq_fail "${label}_EXECUTED"

    case "$RP_OUT$RP_ERR" in
        *ghp_*|*hacked*|*touch*|*EXTRA*) fq_fail "${label}_ECHOED" ;;
    esac
}

# ---------------------------------------------------------------- 1. consolidation of coherent answers

rp_dir qual-ok
rp_put qual-ok ANALYZE PASS "" 0
rp_put qual-ok TEST PASS "" 0
rp_put qual-ok BUILD_IOS PASS "" 0

rp_req "preflight,analyze,test,build_ios,report" qual-ok
rp_run CONSISTENT "$BASH" "${FQ_REQUEST[@]}"
rp_expect CONSISTENT PASS - 0
rp_op_expect CONSISTENT PREFLIGHT PASS - 0 DERIVED -
rp_op_expect CONSISTENT ANALYZE PASS - 0 READ 0
rp_op_expect CONSISTENT TEST PASS - 0 READ 0
rp_op_expect CONSISTENT BUILD_IOS PASS - 0 READ 0
[[ "$(rp_kv CBS_FLUTTER_QUAL_REPORT_QUALIFICATION_ID)" == "qual-ok" ]] || fq_fail "CONSISTENT_QUALIFICATION_ID"
[[ "$(rp_kv CBS_FLUTTER_QUAL_REPORT_COMMIT_EXPECTED)" == "$FQ_COMMIT" ]] || fq_fail "CONSISTENT_COMMIT_EXPECTED"
[[ "$(rp_kv CBS_FLUTTER_QUAL_REPORT_COMMIT_OBSERVED)" == "$FQ_COMMIT" ]] || fq_fail "CONSISTENT_COMMIT_OBSERVED"

# What is not selected is SKIPPED, and its file is never read: TEST.result exists
# here and is valid, but the request does not select it.
rp_req "preflight,analyze,build_ios,report" qual-ok
rp_run NOT_SELECTED "$BASH" "${FQ_REQUEST[@]}"
rp_expect NOT_SELECTED PASS - 0
rp_op_expect NOT_SELECTED TEST SKIPPED NOT_SELECTED 137 NOT_SELECTED -
rp_op_expect NOT_SELECTED ANALYZE PASS - 0 READ 0

# A failed operation is consolidated as FAIL, with its own status; the others are
# kept as they are, and PASS never wins.
rp_dir qual-fail
rp_put qual-fail ANALYZE PASS "" 0
rp_put qual-fail BUILD_IOS FAIL COMMAND_FAILED 1

rp_req "preflight,analyze,build_ios,report" qual-fail
rp_run FAILED "$BASH" "${FQ_REQUEST[@]}"
rp_expect FAILED FAIL COMMAND_FAILED 130
rp_op_expect FAILED PREFLIGHT PASS - 0 DERIVED -
rp_op_expect FAILED ANALYZE PASS - 0 READ 0
rp_op_expect FAILED BUILD_IOS FAIL COMMAND_FAILED 130 READ 1

rp_pass "CONSOLIDATION"

# ---------------------------------------------------------------- 2. absent operation

# TEST was selected and left nothing: NOT_RUN, never a PASS, and the report is
# not a PASS either.
rp_dir qual-absent
rp_put qual-absent ANALYZE PASS "" 0

rp_req "preflight,analyze,test,report" qual-absent
rp_run ABSENT "$BASH" "${FQ_REQUEST[@]}"
rp_expect ABSENT NOT_RUN NOT_EXECUTED 135
rp_op_expect ABSENT ANALYZE PASS - 0 READ 0
rp_op_expect ABSENT TEST NOT_RUN NOT_EXECUTED 135 ABSENT -
rp_op_expect ABSENT PREFLIGHT PASS - 0 DERIVED -

# No evidence directory at all: nothing was observed, PREFLIGHT included (it
# leaves no file of its own).
rp_req "preflight,analyze,report" qual-nodir
rp_run NO_DIRECTORY "$BASH" "${FQ_REQUEST[@]}"
rp_expect NO_DIRECTORY NOT_RUN NOT_EXECUTED 135
rp_op_expect NO_DIRECTORY ANALYZE NOT_RUN NOT_EXECUTED 135 ABSENT -
rp_op_expect NO_DIRECTORY PREFLIGHT NOT_RUN NOT_EXECUTED 135 ABSENT -
[[ -z "$(rp_kv CBS_FLUTTER_QUAL_REPORT_COMMIT_OBSERVED)" ]] || fq_fail "NO_DIRECTORY_COMMIT_OBSERVED"
[[ ! -e "$EVID/qual-nodir" ]] || fq_fail "NO_DIRECTORY_CREATED"

# PREFLIGHT alone, and REPORT alone: never a PASS.
rp_req "preflight,report" qual-nodir
rp_run PREFLIGHT_ONLY "$BASH" "${FQ_REQUEST[@]}"
rp_expect PREFLIGHT_ONLY NOT_RUN NOT_EXECUTED 135
rp_op_expect PREFLIGHT_ONLY PREFLIGHT NOT_RUN NOT_EXECUTED 135 ABSENT -

rp_req "report" qual-nodir
rp_run REPORT_ONLY "$BASH" "${FQ_REQUEST[@]}"
rp_expect REPORT_ONLY NOT_RUN NOT_EXECUTED 135
rp_op_expect REPORT_ONLY PREFLIGHT SKIPPED NOT_SELECTED 137 NOT_SELECTED -
rp_op_expect REPORT_ONLY BUILD_IOS SKIPPED NOT_SELECTED 137 NOT_SELECTED -

rp_pass "ABSENT_OPERATION"

# ---------------------------------------------------------------- 3. incoherent or malformed answer

rp_dir qual-bad
BAD="$EVID/qual-bad/ANALYZE.result"

# Another qualification, another commit.
rp_put qual-bad ANALYZE PASS "" 0 other-qual
rp_expect_bad QUALIFICATION_MISMATCH
rp_put qual-bad ANALYZE PASS "" 0 qual-bad fedcba9876543210fedcba9876543210fedcba98
rp_expect_bad COMMIT_MISMATCH

# The operation result and the final result disagree.
rp_answer ANALYZE PASS "" 0 qual-bad "$FQ_COMMIT" | sed 's/^CBS_FLUTTER_QUAL_RESULT=PASS$/CBS_FLUTTER_QUAL_RESULT=FAIL/' > "$BAD"
rp_expect_bad RESULT_DISAGREE

# Result, reason, status that the contract does not allow together; a result
# that an executor never writes.
rp_put qual-bad ANALYZE FAIL NOT_EXECUTED ""
rp_expect_bad REASON_OF_ANOTHER_CLASS
rp_put qual-bad ANALYZE PASS "" 3
rp_expect_bad PASS_WITH_FAILED_TOOL
rp_put qual-bad ANALYZE BLOCKED INPUT_INVALID ""
rp_expect_bad RESULT_NEVER_WRITTEN

# Truncated, empty, without final newline.
rp_answer ANALYZE PASS "" 0 qual-bad "$FQ_COMMIT" | sed -n '1,12p' > "$BAD"
rp_expect_bad TRUNCATED
: > "$BAD"
rp_expect_bad EMPTY
printf '%s' "$(rp_answer ANALYZE PASS "" 0 qual-bad "$FQ_COMMIT")" > "$BAD"
rp_expect_bad NO_FINAL_NEWLINE

# A key that is unknown, given twice, a line that is not KEY=VALUE, a secret and
# a command substitution: refused as data, never executed, never printed.
RP_EXTRA="CBS_FLUTTER_QUAL_ANALYZE_EXTRA=1" rp_put qual-bad ANALYZE PASS "" 0
rp_expect_bad UNKNOWN_KEY
RP_EXTRA="CBS_FLUTTER_QUAL_ANALYZE_EVIDENCE=WRITTEN" rp_put qual-bad ANALYZE PASS "" 0
rp_expect_bad DUPLICATE_KEY
RP_EXTRA="echo hacked" rp_put qual-bad ANALYZE PASS "" 0
rp_expect_bad FOREIGN_LINE
RP_EXTRA="token=ghp_abcdefghijklmnopqrstuvwxyz0123456789" rp_put qual-bad ANALYZE PASS "" 0
rp_expect_bad SECRET_LINE
RP_EXTRA='$(touch '"$PWNED"')' rp_put qual-bad ANALYZE PASS "" 0
rp_expect_bad COMMAND_SUBSTITUTION
RP_EXTRA='CBS_FLUTTER_QUAL_ANALYZE_EXTRA=`touch '"$PWNED"'`' rp_put qual-bad ANALYZE PASS "" 0
rp_expect_bad BACKQUOTE

# A run that started and left no answer is not "never run".
rp_dir qual-partial
: > "$EVID/qual-partial/ANALYZE.log.partial"
rp_expect_bad INCOMPLETE qual-partial

# One incoherent answer does not hide the others, and never becomes a PASS.
rp_dir qual-mixed
rp_put qual-mixed ANALYZE PASS "" 0 other-qual
rp_put qual-mixed BUILD_IOS PASS "" 0

rp_req "preflight,analyze,build_ios,report" qual-mixed
rp_run MIXED "$BASH" "${FQ_REQUEST[@]}"
rp_expect MIXED BLOCKED INPUT_INVALID 121
rp_op_expect MIXED ANALYZE BLOCKED INPUT_INVALID 121 REJECTED -
rp_op_expect MIXED BUILD_IOS PASS - 0 READ 0
rp_op_expect MIXED PREFLIGHT PASS - 0 DERIVED -

rp_pass "INCOHERENT_ANSWER"

# ---------------------------------------------------------------- 4. symbolic links

# A valid answer outside the evidence, reached through a link: refused, not read,
# not followed. (rp_run checks that the target is unchanged.)
mkdir -m 700 "$OUTSIDE/real-qual"
printf '%s\n' "target of a link" > "$OUTSIDE/target.txt"
rp_answer ANALYZE PASS "" 0 qual-link "$FQ_COMMIT" > "$OUTSIDE/ANALYZE.result"
chmod 600 "$OUTSIDE/ANALYZE.result"

rp_dir qual-link
ln -s "$OUTSIDE/ANALYZE.result" "$EVID/qual-link/ANALYZE.result"

rp_req "preflight,analyze,report" qual-link
rp_run LINK_FILE "$BASH" "${FQ_REQUEST[@]}"
rp_expect LINK_FILE BLOCKED PATH_NOT_ALLOWED 124
rp_op_expect LINK_FILE ANALYZE BLOCKED PATH_NOT_ALLOWED 124 REJECTED -
rp_op_expect LINK_FILE PREFLIGHT NOT_RUN NOT_EXECUTED 135 ABSENT -

rp_dir qual-dangling
ln -s "$OUTSIDE/missing.result" "$EVID/qual-dangling/ANALYZE.result"

rp_req "preflight,analyze,report" qual-dangling
rp_run LINK_DANGLING "$BASH" "${FQ_REQUEST[@]}"
rp_expect LINK_DANGLING BLOCKED PATH_NOT_ALLOWED 124
rp_op_expect LINK_DANGLING ANALYZE BLOCKED PATH_NOT_ALLOWED 124 REJECTED -
[[ ! -e "$OUTSIDE/missing.result" ]] || fq_fail "LINK_DANGLING_CREATED"

# A link in place of the evidence directory of the qualification, then in place of
# the evidence root: the whole report is refused, nothing is consolidated.
rp_answer ANALYZE PASS "" 0 qual-linkdir "$FQ_COMMIT" > "$OUTSIDE/real-qual/ANALYZE.result"
chmod 600 "$OUTSIDE/real-qual/ANALYZE.result"
ln -s "$OUTSIDE/real-qual" "$EVID/qual-linkdir"

rp_req "preflight,analyze,report" qual-linkdir
rp_run LINK_DIRECTORY "$BASH" "${FQ_REQUEST[@]}"
rp_expect LINK_DIRECTORY BLOCKED PATH_NOT_ALLOWED 124
[[ "$(rp_kv CBS_FLUTTER_QUAL_REPORT_REJECTED_KEY)" == "qualification_id" ]] || fq_fail "LINK_DIRECTORY_KEY"
[[ -z "$(rp_kv CBS_FLUTTER_QUAL_REPORT_ANALYZE_RESULT)" ]] || fq_fail "LINK_DIRECTORY_CONSOLIDATED"

ln -s "$EVID" "$FQ_TMP/evidence-link"

rp_req "preflight,analyze,report" qual-ok "$FQ_TMP/evidence-link"
rp_run LINK_ROOT "$BASH" "${FQ_REQUEST[@]}"
rp_expect LINK_ROOT BLOCKED PATH_NOT_ALLOWED 124
[[ "$(rp_kv CBS_FLUTTER_QUAL_REPORT_REJECTED_KEY)" == "evidence_root" ]] || fq_fail "LINK_ROOT_KEY"
[[ -z "$(rp_kv CBS_FLUTTER_QUAL_REPORT_ANALYZE_RESULT)" ]] || fq_fail "LINK_ROOT_CONSOLIDATED"

[[ "$(cat "$OUTSIDE/target.txt")" == "target of a link" ]] || fq_fail "LINK_TARGET_TOUCHED"

rp_pass "SYMBOLIC_LINKS"

# ---------------------------------------------------------------- 5. no external tool, nothing written

# Every run above went through rp_run: the shims of flutter, dart, xcrun,
# xcodebuild, simctl, git, ssh, scp, curl, wget and open stayed uncalled, and
# nothing under the evidence or outside it changed. The code is checked too.
fq_shims_assert_unused "FINAL"

rp_code_matches() {
    local hits

    hits="$(grep -En -e "$2" "$1" | grep -Ev '^[0-9]+:[[:space:]]*#' || true)"
    [[ -n "$hits" ]]
}

WORD='(^|[^A-Za-z0-9_])'
END='([^A-Za-z0-9_]|$)'

if rp_code_matches "$REPORT" "${WORD}(flutter|dart|xcrun|xcodebuild|simctl|git|ssh|scp|curl|wget|open)${END}"; then
    fq_fail "CODE_CALLS_EXTERNAL_TOOL"
fi

if rp_code_matches "$REPORT" "${WORD}(eval|rm|mv|mkdir|rmdir|touch|ln|chmod|cp|tee|mktemp|install|dd|sed|awk)${END}"; then
    fq_fail "CODE_WRITES_OR_EVALUATES"
fi

# No redirection to a file: only /dev/null and the standard error remain.
REDIRECTIONS="$(grep -Ev '^[[:space:]]*#' "$REPORT" | sed -e 's#2>/dev/null##g' -e 's#>/dev/null##g' -e 's#>&2##g' | grep -F '>' || true)"
[[ -z "$REDIRECTIONS" ]] || fq_fail "CODE_REDIRECTS_TO_FILE"

# One "source" only: the contract of this directory, never a request or a result.
SOURCES="$(grep -Ev '^[[:space:]]*#' "$REPORT" | grep -Ec '(^|[[:space:];])source[[:space:]]' || true)"
[[ "$SOURCES" == "1" ]] || fq_fail "CODE_SOURCE_COUNT_$SOURCES"

# Sourcing runs nothing and writes nothing.
set +e
SOURCED_OUT="$(cd "$FQ_TMP" && env PATH="$FQ_SHIM_BIN:$PATH" "$BASH" -c 'source "$1"; declare -F cbs_flutter_qual_report >/dev/null' x "$REPORT" 2>&1)"
SOURCED_RC=$?
set -e
[[ "$SOURCED_RC" -eq 0 && -z "$SOURCED_OUT" ]] || fq_fail "SOURCE_RUNS_$SOURCED_RC"
fq_shims_assert_unused "SOURCE"

rp_pass "NO_EXTERNAL_TOOL"

# ---------------------------------------------------------------- 6. Bash 3.2

# Native Bash 3.2 (macOS): a PASS, a FAIL and an incoherent answer run under it
# when one is available. Otherwise NOT_RUN: this is not a claim of macOS
# qualification.
BASH32=""
for candidate in /bin/bash /usr/bin/bash /usr/local/bin/bash; do
    if [[ -x "$candidate" ]] && [[ "$("$candidate" -c 'printf "%s%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null)" == "32" ]]; then
        BASH32="$candidate"
        break
    fi
done

if [[ -n "$BASH32" ]]; then
    rp_req "preflight,analyze,test,build_ios,report" qual-ok
    rp_run BASH32_PASS "$BASH32" "${FQ_REQUEST[@]}"
    rp_expect BASH32_PASS PASS - 0
    rp_op_expect BASH32_PASS BUILD_IOS PASS - 0 READ 0

    rp_req "preflight,analyze,build_ios,report" qual-fail
    rp_run BASH32_FAIL "$BASH32" "${FQ_REQUEST[@]}"
    rp_expect BASH32_FAIL FAIL COMMAND_FAILED 130

    rp_req "preflight,analyze,build_ios,report" qual-mixed
    rp_run BASH32_BAD "$BASH32" "${FQ_REQUEST[@]}"
    rp_expect BASH32_BAD BLOCKED INPUT_INVALID 121

    echo "${TEST_PREFIX}_BASH32=PASS"
else
    echo "${TEST_PREFIX}_BASH32=NOT_RUN"
fi

echo "${TEST_PREFIX}_RESULT=PASS"
