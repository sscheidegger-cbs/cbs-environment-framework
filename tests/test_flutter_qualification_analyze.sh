#!/usr/bin/env bash

# D04b-C.2b step 3: hermetic test of the Flutter/iOS qualification ANALYZE.
#
# Real Git repositories and real CBS isolations in a private directory; Flutter,
# Dart, Xcode and simctl are shims generated at run time. The PATH given to the
# executor holds only those shims and links to the system tools it needs: a real
# Flutter or Xcode of the host can never be found. The source repository and the
# isolation root are compared before and after every run.
#
# Nothing here qualifies a real Mac: see the BASH32 line for the one check that
# needs a native Bash 3.2.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANALYZE="$ROOT/cbs/qualification/flutter/analyze.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_ANALYZE"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/analyze_lib.sh"
source "$CONTRACT"

[[ -f "$ANALYZE" ]] || pf_fail "ANALYZE_MISSING"
bash -n "$ANALYZE" || pf_fail "ANALYZE_SYNTAX"

iso_fixture_init
pf_init
an_init

IS_ROOT=0
[[ "$(id -u)" -ne 0 ]] || IS_ROOT=1

# A run that must be refused before anything is written under the evidence root.
an_run_refused() {
    AN_EVIDENCE_EXPECT=same an_run "$@"
}

shim_mode() {
    export SHIM_ANALYZE_MODE="$1"
}

# No tool was started at all (not even a probe).
assert_no_tool() {
    [[ -z "$(cat "$PF_LOG")" ]] || pf_fail "${1}_TOOL_CALLED_$(head -n 1 "$PF_LOG" | tr ' ' '_')"
    [[ "$(an_calls)" -eq 0 ]] || pf_fail "${1}_ANALYZE_CALLED"
    [[ "$(pf_git_calls)" -eq 0 ]] || pf_fail "${1}_GIT_CALLED"
}

# PREFLIGHT did not pass: ANALYZE is NOT_RUN, nothing executed, nothing written.
# Arguments: LABEL QUALIFICATION_ID PREFLIGHT_RESULT PREFLIGHT_REASON
assert_not_run() {
    an_expect "$1" NOT_RUN PREFLIGHT_NOT_PASSED 136
    [[ "$(an_value PREFLIGHT_RESULT)" == "$3" ]] || pf_fail "${1}_PREFLIGHT_RESULT_$(an_value PREFLIGHT_RESULT)"
    [[ "$(an_value PREFLIGHT_REASON)" == "$4" ]] || pf_fail "${1}_PREFLIGHT_REASON_$(an_value PREFLIGHT_REASON)"
    [[ "$(an_calls)" -eq 0 ]] || pf_fail "${1}_ANALYZE_CALLED"
    [[ -z "$(an_value COMMAND)" ]] || pf_fail "${1}_COMMAND_REPORTED"
    [[ "$(an_value EVIDENCE)" == "NOT_WRITTEN" ]] || pf_fail "${1}_EVIDENCE_FACT"
    an_assert_no_evidence "$1" "$2"
}

# Seconds since the reference given.
elapsed_since() {
    echo "$((SECONDS - $1))"
}

# ---------------------------------------------------------------- 1. PASS

an_modes_reset
pf_new_isolation iso-an
iso_snapshot_source

an_req iso-an qual-pass
an_run PASS "${PF_REQ[@]}"
an_expect PASS PASS - 0 0

[[ "$(an_calls)" -eq 1 ]] || pf_fail "PASS_ANALYZE_CALLS_$(an_calls)"
CALL="$(cat "$AN_CALLS")"

# Exactly "flutter analyze": one argument, run from the isolated checkout, never
# from the source repository.
[[ "$CALL" == "argc=1 argv=analyze cwd=$ISO_ROOT/iso-an lc_all=C" ]] || pf_fail "PASS_CALL_$CALL"

# PREFLIGHT ran first, on the same request: its seven probes, and no more.
[[ "$(grep -c '^flutter --version$' "$PF_LOG")" -eq 1 ]] || pf_fail "PASS_PREFLIGHT_NOT_RUN"
[[ "$(pf_tool_calls)" -eq 7 ]] || pf_fail "PASS_PREFLIGHT_PROBES_$(pf_tool_calls)"

[[ "$(an_value PREFLIGHT_RESULT)" == "PASS" ]] || pf_fail "PASS_PREFLIGHT_RESULT"
[[ -z "$(an_value PREFLIGHT_REASON)" ]] || pf_fail "PASS_PREFLIGHT_REASON"
[[ "$(an_value QUALIFICATION_ID)" == "qual-pass" ]] || pf_fail "PASS_QUALIFICATION_ID"
[[ "$(an_value COMMIT_OBSERVED)" == "$C2" ]] || pf_fail "PASS_COMMIT"
[[ "$(an_value FLUTTER_VERSION)" == "$PF_FLUTTER_REQUIRED" ]] || pf_fail "PASS_FLUTTER_VERSION"
[[ "$(an_value COMMAND)" == "flutter_analyze" ]] || pf_fail "PASS_COMMAND"
[[ "$(an_value LOG_TRUNCATED)" == "NO" ]] || pf_fail "PASS_LOG_TRUNCATED"
[[ "$(an_value EVIDENCE)" == "WRITTEN" ]] || pf_fail "PASS_EVIDENCE"
[[ "$(an_value DURATION_SECONDS)" =~ ^[0-9]+$ ]] || pf_fail "PASS_DURATION"

# Evidence: private, complete, and the result file is the printed answer.
an_assert_evidence PASS qual-pass
an_assert_result_file PASS qual-pass
[[ "$(an_log qual-pass)" == "Analyzing app...
No issues found! (ran in 1.0s)" ]] || pf_fail "PASS_LOG_CONTENT"
[[ "$(an_value LOG_BYTES)" == "$(an_log_bytes qual-pass)" ]] || pf_fail "PASS_LOG_BYTES"
[[ "$(an_value LOG_CRC)" == "$(cksum < "$EVID/qual-pass/ANALYZE.log" | cut -d' ' -f1)" ]] || pf_fail "PASS_LOG_CRC"

# The checkout is as created (this shim writes nothing), the source untouched.
[[ -z "$(git -C "$ISO_ROOT/iso-an" status --porcelain)" ]] || pf_fail "PASS_CHECKOUT_DIRTIED"
iso_assert_source_untouched "PASS_SOURCE"

# The isolation manager still verifies the checkout: ANALYZE broke nothing.
iso_run verify iso-an "$SOURCE" "$ISO_ROOT"
iso_expect_pass "PASS_VERIFY"

# The structured answer is stable (only the qualification id differs).
FIRST_OUT="$(printf '%s\n' "$PF_OUT" | grep -v -e QUALIFICATION_ID -e DURATION_SECONDS)"
an_req iso-an qual-pass-2
an_run PASS_AGAIN "${PF_REQ[@]}"
an_expect PASS_AGAIN PASS - 0 0
SECOND_OUT="$(printf '%s\n' "$PF_OUT" | grep -v -e QUALIFICATION_ID -e DURATION_SECONDS)"
[[ "$SECOND_OUT" == "$FIRST_OUT" ]] || pf_fail "PASS_NOT_DETERMINISTIC"

pf_pass "PASS"

# ---------------------------------------------------------------- 2. the exit status of the tool is kept

an_modes_reset
shim_mode issues
an_req iso-an qual-issues
an_run ISSUES "${PF_REQ[@]}"
an_expect ISSUES FAIL COMMAND_FAILED 130 1
an_assert_evidence ISSUES qual-issues
an_assert_result_file ISSUES qual-issues
[[ "$(an_log qual-issues)" == *"1 issue found."* ]] || pf_fail "ISSUES_LOG"
[[ "$(an_value EVIDENCE)" == "WRITTEN" ]] || pf_fail "ISSUES_EVIDENCE"
[[ "$(an_calls)" -eq 1 ]] || pf_fail "ISSUES_CALLS"

for status in 2 3 64 126 255; do
    an_modes_reset
    shim_mode rc
    export SHIM_ANALYZE_RC="$status"
    an_req iso-an "qual-rc-$status"
    an_run "RC_$status" "${PF_REQ[@]}"
    # The tool status is reported as is; the contract code never replaces it.
    an_expect "RC_$status" FAIL COMMAND_FAILED 130 "$status"
    an_assert_evidence "RC_$status" "qual-rc-$status"
done

# A tool killed by a signal: the status is the shell's, reported exactly.
an_modes_reset
shim_mode killed
an_req iso-an qual-killed
an_run KILLED "${PF_REQ[@]}"
an_expect KILLED FAIL COMMAND_FAILED 130 137
[[ "$(an_log qual-killed)" == "about to be killed" ]] || pf_fail "KILLED_LOG"

pf_pass "TOOL_STATUS"

# ---------------------------------------------------------------- 3. input, streams, bytes

# No input: the tool sees the end of file at once.
an_modes_reset
shim_mode stdin
an_req iso-an qual-stdin
an_run STDIN "${PF_REQ[@]}"
an_expect STDIN PASS - 0 0
[[ "$(an_log qual-stdin)" == "stdin-eof" ]] || pf_fail "STDIN_NOT_EOF"

# stdout and stderr are merged, in order, in the log.
an_modes_reset
shim_mode streams
an_req iso-an qual-streams
an_run STREAMS "${PF_REQ[@]}"
an_expect STREAMS FAIL COMMAND_FAILED 130 1
[[ "$(an_log qual-streams)" == "to-stdout
to-stderr" ]] || pf_fail "STREAMS_LOG"

# Nothing printed by the tool reaches the standard output of the executor.
printf '%s\n' "$PF_OUT" | grep -F -e "to-stdout" -e "to-stderr" >/dev/null && pf_fail "STREAMS_LEAK_TO_STDOUT"

# A last line without newline is kept as is.
an_modes_reset
shim_mode noeol
an_req iso-an qual-noeol
an_run NOEOL "${PF_REQ[@]}"
an_expect NOEOL PASS - 0 0
[[ "$(an_log_bytes qual-noeol)" -eq 16 ]] || pf_fail "NOEOL_BYTES"
[[ "$(cat "$EVID/qual-noeol/ANALYZE.log")" == "no final newline" ]] || pf_fail "NOEOL_CONTENT"

# Bytes that are not text (invalid UTF-8) do not break redaction or evidence.
an_modes_reset
shim_mode binary
an_req iso-an qual-binary
an_run BINARY "${PF_REQ[@]}"
an_expect BINARY FAIL COMMAND_FAILED 130 1
an_assert_evidence BINARY qual-binary
[[ "$(LC_ALL=C tr -d '\200\300\376\377' < "$EVID/qual-binary/ANALYZE.log")" == "start  end" ]] || pf_fail "BINARY_CONTENT"

pf_pass "STREAMS"

# ---------------------------------------------------------------- 4. timeout

# Hanging tool: killed when the timeout expires, reported as TIMEOUT, log kept,
# nothing left running.
an_modes_reset
shim_mode hang
an_req iso-an qual-hang
pf_req_set timeout_seconds 3
STARTED=$SECONDS
an_run TIMEOUT "${PF_REQ[@]}"
ELAPSED="$(elapsed_since "$STARTED")"
an_expect TIMEOUT FAIL TIMEOUT 131
[[ "$ELAPSED" -le 20 ]] || pf_fail "TIMEOUT_TOO_SLOW_${ELAPSED}"
[[ "$ELAPSED" -ge 3 ]] || pf_fail "TIMEOUT_TOO_FAST_${ELAPSED}"
an_assert_evidence TIMEOUT qual-hang
[[ "$(an_log qual-hang)" == "analysis started" ]] || pf_fail "TIMEOUT_LOG"
[[ -s "$PF_HANG_PID" ]] || pf_fail "TIMEOUT_NO_PID"
pf_pid_gone "$(cat "$PF_HANG_PID")" 5 || pf_fail "TIMEOUT_PROCESS_SURVIVED"
[[ "$(pf_ps_count 'cbs-analyze-(supervisor|runner)')" -eq 0 ]] || pf_fail "TIMEOUT_SUPERVISOR_SURVIVED"

# A tool that ignores TERM is killed anyway.
an_modes_reset
shim_mode hangterm
an_req iso-an qual-hangterm
pf_req_set timeout_seconds 3
STARTED=$SECONDS
an_run TIMEOUT_TERM "${PF_REQ[@]}"
ELAPSED="$(elapsed_since "$STARTED")"
an_expect TIMEOUT_TERM FAIL TIMEOUT 131
[[ "$ELAPSED" -le 20 ]] || pf_fail "TIMEOUT_TERM_TOO_SLOW_${ELAPSED}"
pf_pid_gone "$(cat "$PF_HANG_PID")" 5 || pf_fail "TIMEOUT_TERM_PROCESS_SURVIVED"

# A background process left by the tool does not outlive the call, whether it
# keeps the output open (the run then lasts until the timeout) or not.
an_modes_reset
shim_mode leak
an_req iso-an qual-leak
an_run LEAK "${PF_REQ[@]}"
an_expect LEAK PASS - 0 0
pf_pid_gone "$(cat "$PF_HANG_PID")" 5 || pf_fail "LEAK_PROCESS_SURVIVED"

an_modes_reset
shim_mode leakpipe
an_req iso-an qual-leakpipe
pf_req_set timeout_seconds 3
an_run LEAKPIPE "${PF_REQ[@]}"
an_expect LEAKPIPE FAIL TIMEOUT 131
pf_pid_gone "$(cat "$PF_HANG_PID")" 5 || pf_fail "LEAKPIPE_PROCESS_SURVIVED"

pf_pass "TIMEOUT"

# ---------------------------------------------------------------- 5. log limit

# The limit is exact: a log of log_max_bytes bytes is complete, one byte more
# is exceeded and kept truncated at the limit.
an_modes_reset
shim_mode bytes
export SHIM_ANALYZE_BYTES=1024
an_req iso-an qual-exact
pf_req_set log_max_bytes 1024
an_run LIMIT_EXACT "${PF_REQ[@]}"
an_expect LIMIT_EXACT PASS - 0 0
[[ "$(an_log_bytes qual-exact)" -eq 1024 ]] || pf_fail "LIMIT_EXACT_BYTES_$(an_log_bytes qual-exact)"
[[ "$(an_value LOG_TRUNCATED)" == "NO" ]] || pf_fail "LIMIT_EXACT_TRUNCATED"

export SHIM_ANALYZE_BYTES=1025
an_req iso-an qual-over
pf_req_set log_max_bytes 1024
an_run LIMIT_OVER "${PF_REQ[@]}"
an_expect LIMIT_OVER FAIL LOG_LIMIT_EXCEEDED 133
an_assert_evidence LIMIT_OVER qual-over
[[ "$(an_log_bytes qual-over)" -eq 1024 ]] || pf_fail "LIMIT_OVER_BYTES_$(an_log_bytes qual-over)"
[[ "$(an_value LOG_BYTES)" == "1024" ]] || pf_fail "LIMIT_OVER_LOG_BYTES_FACT"
[[ "$(an_value LOG_TRUNCATED)" == "YES" ]] || pf_fail "LIMIT_OVER_TRUNCATED_FACT"
an_assert_result_file LIMIT_OVER qual-over

# A talkative tool is cut by the limit, quickly, and nothing stays in the
# evidence directory but the two files.
an_modes_reset
shim_mode big
export SHIM_ANALYZE_LINES=200000
an_req iso-an qual-big
pf_req_set log_max_bytes 4096
STARTED=$SECONDS
an_run LIMIT_BIG "${PF_REQ[@]}"
ELAPSED="$(elapsed_since "$STARTED")"
an_expect LIMIT_BIG FAIL LOG_LIMIT_EXCEEDED 133
[[ "$ELAPSED" -le 20 ]] || pf_fail "LIMIT_BIG_TOO_SLOW_${ELAPSED}"
[[ "$(an_log_bytes qual-big)" -eq 4096 ]] || pf_fail "LIMIT_BIG_BYTES"

# A tool that ignores SIGPIPE is still reported by the size of its log.
an_modes_reset
shim_mode bigignore
export SHIM_ANALYZE_LINES=3000
an_req iso-an qual-bigignore
pf_req_set log_max_bytes 2048
an_run LIMIT_IGNORE "${PF_REQ[@]}"
an_expect LIMIT_IGNORE FAIL LOG_LIMIT_EXCEEDED 133
[[ "$(an_log_bytes qual-bigignore)" -eq 2048 ]] || pf_fail "LIMIT_IGNORE_BYTES"

pf_pass "LOG_LIMIT"

# ---------------------------------------------------------------- 6. secrets are redacted before they are written

an_modes_reset
shim_mode secret
an_req iso-an qual-secret
an_run SECRET "${PF_REQ[@]}"
an_expect SECRET FAIL COMMAND_FAILED 130 1
an_assert_evidence SECRET qual-secret

LOG="$(an_log qual-secret)"
for leaked in ghp_abcdefghijklmnopqrstuvwxyz0123456789 abcdef.ghijkl.mnopqr hunter2secret supersecretvalue123 AKIAABCDEFGHIJKLMNOP private-body; do
    case "$LOG" in
        *"$leaked"*) pf_fail "SECRET_LOG_LEAK_$leaked" ;;
    esac
    # Not in the answer or in its file either.
    printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e "$leaked" >/dev/null && pf_fail "SECRET_ANSWER_LEAK_$leaked"
    grep -F -e "$leaked" "$EVID/qual-secret/ANALYZE.result" >/dev/null && pf_fail "SECRET_RESULT_FILE_LEAK_$leaked"
done

[[ "$LOG" == *"[REDACTED]"* ]] || pf_fail "SECRET_NOT_REDACTED"
[[ "$LOG" == *"ordinary line kept"* ]] || pf_fail "SECRET_OVERREDACTED"

# The raw capture never stays on disk, under any name.
[[ -z "$(grep -rl -e hunter2secret -e supersecretvalue123 "$EVID" 2>/dev/null || true)" ]] || pf_fail "SECRET_ON_DISK"

pf_pass "REDACTION"

# ---------------------------------------------------------------- 7. what the tool prints is data

# Lines that imitate the answer of the executor are only text of the log.
an_modes_reset
shim_mode forged
an_req iso-an qual-forged
an_run FORGED "${PF_REQ[@]}"
an_expect FORGED FAIL COMMAND_FAILED 130 1
[[ "$(an_log qual-forged)" == *"CBS_FLUTTER_QUAL_RESULT=PASS"* ]] || pf_fail "FORGED_NOT_IN_LOG"
[[ "$(printf '%s\n' "$PF_OUT" | grep -c '^CBS_FLUTTER_QUAL_RESULT=')" -eq 1 ]] || pf_fail "FORGED_RESULT_LINES"
[[ "$(printf '%s\n' "$PF_OUT" | grep -c '^CBS_FLUTTER_QUAL_OPERATION_RESULT=')" -eq 1 ]] || pf_fail "FORGED_OPERATION_LINES"

pf_pass "FORGERY"

# ---------------------------------------------------------------- 8. PREFLIGHT must be PASS

an_modes_reset
pf_new_isolation iso-gate

# Flutter of another version.
export SHIM_FLUTTER_VERSION="0.0.1"
an_req iso-gate qual-gate-version
an_run_refused GATE_VERSION "${PF_REQ[@]}"
assert_not_run GATE_VERSION qual-gate-version BLOCKED TOOLCHAIN_INCOMPATIBLE
unset SHIM_FLUTTER_VERSION

# Flutter that fails, and flutter that is absent.
export SHIM_FLUTTER_MODE=fail
an_req iso-gate qual-gate-fail
an_run_refused GATE_FLUTTER_FAIL "${PF_REQ[@]}"
assert_not_run GATE_FLUTTER_FAIL qual-gate-fail FAIL COMMAND_FAILED
unset SHIM_FLUTTER_MODE

PF_MISSING="flutter"
an_req iso-gate qual-gate-missing
an_run_refused GATE_FLUTTER_MISSING "${PF_REQ[@]}"
assert_not_run GATE_FLUTTER_MISSING qual-gate-missing BLOCKED TOOL_UNAVAILABLE
unset PF_MISSING

# Xcode too old, no iphoneos SDK, simulator that does not exist.
export SHIM_XCODE_VERSION="9.0"
an_req iso-gate qual-gate-xcode
an_run_refused GATE_XCODE "${PF_REQ[@]}"
assert_not_run GATE_XCODE qual-gate-xcode BLOCKED TOOLCHAIN_INCOMPATIBLE
unset SHIM_XCODE_VERSION

export SHIM_SDK_IPHONEOS_MODE=missing
an_req iso-gate qual-gate-sdk
an_run_refused GATE_SDK "${PF_REQ[@]}"
assert_not_run GATE_SDK qual-gate-sdk BLOCKED TOOLCHAIN_INCOMPATIBLE
unset SHIM_SDK_IPHONEOS_MODE

an_req iso-gate qual-gate-simulator
pf_req_set simulator_udid "$PF_UDID_ABSENT"
an_run_refused GATE_SIMULATOR "${PF_REQ[@]}"
assert_not_run GATE_SIMULATOR qual-gate-simulator BLOCKED SIMULATOR_UNAVAILABLE

# Checkout that is not the requested commit, not the expected origin, not known
# to CBS, not owned by CBS, modified.
an_req iso-gate qual-gate-commit
pf_req_set commit "$C1"
an_run_refused GATE_COMMIT "${PF_REQ[@]}"
assert_not_run GATE_COMMIT qual-gate-commit BLOCKED ISOLATION_REJECTED

an_req iso-gate qual-gate-origin
pf_req_set expected_origin "https://example.invalid/other/app.git"
an_run_refused GATE_ORIGIN "${PF_REQ[@]}"
assert_not_run GATE_ORIGIN qual-gate-origin BLOCKED ISOLATION_REJECTED

an_req iso-unknown qual-gate-unknown
an_run_refused GATE_UNKNOWN "${PF_REQ[@]}"
assert_not_run GATE_UNKNOWN qual-gate-unknown BLOCKED ISOLATION_REJECTED

mkdir "$ISO_ROOT/iso-foreign"
printf '%s\n' "not made by CBS" > "$ISO_ROOT/iso-foreign/file.txt"
an_req iso-foreign qual-gate-foreign
an_run_refused GATE_FOREIGN "${PF_REQ[@]}"
assert_not_run GATE_FOREIGN qual-gate-foreign BLOCKED ISOLATION_REJECTED

printf '%s\n' "local change" > "$ISO_ROOT/iso-gate/untracked.txt"
an_req iso-gate qual-gate-dirty
an_run_refused GATE_DIRTY "${PF_REQ[@]}"
assert_not_run GATE_DIRTY qual-gate-dirty BLOCKED ISOLATION_REJECTED
[[ "$(cat "$ISO_ROOT/iso-gate/untracked.txt")" == "local change" ]] || pf_fail "GATE_DIRTY_FILE_TOUCHED"
rm -f "$ISO_ROOT/iso-gate/untracked.txt"

# The gate is not sticky: the same checkout, repaired, is accepted.
an_req iso-gate qual-gate-repaired
an_run GATE_REPAIRED "${PF_REQ[@]}"
an_expect GATE_REPAIRED PASS - 0 0

pf_pass "PREFLIGHT_GATE"

# ---------------------------------------------------------------- 9. the gate reads the answer of PREFLIGHT strictly

# PREFLIGHT is replaced by a function that prints a chosen answer: only a
# coherent PASS lets ANALYZE start. The driver sources analyze.sh (nothing runs
# when it is sourced) and redefines cbs_flutter_qual_preflight.
cat > "$TMP/stub-driver.sh" <<'EOF'
set -u
source "$1"
shift
cbs_flutter_qual_preflight() {
    printf '%s\n' "$STUB_OUT"
    return "${STUB_RC:-0}"
}
cbs_flutter_qual_analyze "$@"
exit $?
EOF

STUB_PASS="CBS_FLUTTER_QUAL_PREFLIGHT_COMMIT_OBSERVED=$C2
CBS_FLUTTER_QUAL_PREFLIGHT_FLUTTER_VERSION=$PF_FLUTTER_REQUIRED
CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT
CBS_FLUTTER_QUAL_OPERATION_RESULT=PASS
CBS_FLUTTER_QUAL_OPERATION_RC=0
CBS_FLUTTER_QUAL_CONTRACT_VERSION=1
CBS_FLUTTER_QUAL_RESULT=PASS"

# stub_run <label> <qualification id> <stub output> <stub rc>
stub_run() {
    local label="$1"
    local id="$2"

    export STUB_OUT="$3"
    export STUB_RC="$4"

    an_modes_reset
    an_req iso-gate "$id"
    AN_SCRIPT_UNDER_TEST="$TMP/stub-driver.sh" AN_EVIDENCE_EXPECT=same an_run "$label" "$ANALYZE" "${PF_REQ[@]}"
}

# The reference answer, coherent: ANALYZE starts.
STUB_RC=0
export STUB_OUT="$STUB_PASS"
an_modes_reset
an_req iso-gate qual-stub-pass
AN_SCRIPT_UNDER_TEST="$TMP/stub-driver.sh" an_run STUB_PASS "$ANALYZE" "${PF_REQ[@]}"
an_expect STUB_PASS PASS - 0 0
[[ "$(an_calls)" -eq 1 ]] || pf_fail "STUB_PASS_CALLS"

# A coherent PASS but a non-zero status.
stub_run STUB_RC qual-stub-rc "$STUB_PASS" 1
assert_not_run STUB_RC qual-stub-rc NOT_RUN ""
[[ "$(an_value PREFLIGHT_RESULT)" == "NOT_RUN" ]] || pf_fail "STUB_RC_FACT"

# PASS lines carrying a reason, a wrong operation, a result line that is not
# last, no output at all.
stub_run STUB_REASON qual-stub-reason "CBS_FLUTTER_QUAL_REASON=INPUT_INVALID
$STUB_PASS" 0
assert_not_run STUB_REASON qual-stub-reason NOT_RUN ""

stub_run STUB_OPERATION qual-stub-operation "$(printf '%s\n' "$STUB_PASS" | sed 's/^CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT$/CBS_FLUTTER_QUAL_OPERATION=ANALYZE/')" 0
assert_not_run STUB_OPERATION qual-stub-operation NOT_RUN ""

stub_run STUB_NOT_LAST qual-stub-not-last "$STUB_PASS
CBS_FLUTTER_QUAL_PREFLIGHT_NOTE=late" 0
assert_not_run STUB_NOT_LAST qual-stub-not-last NOT_RUN ""

stub_run STUB_EMPTY qual-stub-empty "" 0
assert_not_run STUB_EMPTY qual-stub-empty NOT_RUN ""

stub_run STUB_OPERATION_RESULT qual-stub-op-result "$(printf '%s\n' "$STUB_PASS" | sed 's/^CBS_FLUTTER_QUAL_OPERATION_RESULT=PASS$/CBS_FLUTTER_QUAL_OPERATION_RESULT=FAIL/')" 0
assert_not_run STUB_OPERATION_RESULT qual-stub-op-result NOT_RUN ""

# A refusal of PREFLIGHT is reported with its closed reason ...
stub_run STUB_FAIL qual-stub-fail "CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT
CBS_FLUTTER_QUAL_OPERATION_RESULT=FAIL
CBS_FLUTTER_QUAL_REASON=COMMAND_FAILED
CBS_FLUTTER_QUAL_RESULT=FAIL" 130
assert_not_run STUB_FAIL qual-stub-fail FAIL COMMAND_FAILED

# ... but never with a reason that is not one of the contract.
stub_run STUB_INJECTION qual-stub-injection "CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT
CBS_FLUTTER_QUAL_OPERATION_RESULT=FAIL
CBS_FLUTTER_QUAL_REASON=rm_-rf_/_;_injected
CBS_FLUTTER_QUAL_RESULT=FAIL" 130
assert_not_run STUB_INJECTION qual-stub-injection FAIL ""

# A PASS whose flutter vanished before ANALYZE: the tool is looked up again.
PF_MISSING="flutter"
STUB_RC=0
export STUB_OUT="$STUB_PASS"
an_req iso-gate qual-stub-vanished
AN_SCRIPT_UNDER_TEST="$TMP/stub-driver.sh" AN_EVIDENCE_EXPECT=same an_run STUB_VANISHED "$ANALYZE" "${PF_REQ[@]}"
unset PF_MISSING
an_expect STUB_VANISHED BLOCKED TOOL_UNAVAILABLE 127
[[ "$(an_calls)" -eq 0 ]] || pf_fail "STUB_VANISHED_CALLED"
an_assert_no_evidence STUB_VANISHED qual-stub-vanished
unset STUB_OUT STUB_RC

pf_pass "GATE_STRICT"

# ---------------------------------------------------------------- 10. request and evidence location are checked first

an_modes_reset

# No argument: usage.
an_run_refused USAGE
an_expect USAGE BLOCKED USAGE 64
assert_no_tool USAGE

# ANALYZE must be selected; a mutating action cannot be selected without PREFLIGHT.
an_req iso-gate qual-actions
pf_req_set actions "preflight"
an_run_refused ACTIONS_NO_ANALYZE "${PF_REQ[@]}"
an_expect ACTIONS_NO_ANALYZE BLOCKED ACTION_NOT_ALLOWED 122
assert_no_tool ACTIONS_NO_ANALYZE
[[ "$(an_value REJECTED_KEY)" == "actions" ]] || pf_fail "ACTIONS_REJECTED_KEY"

pf_req_set actions "report"
an_run_refused ACTIONS_REPORT "${PF_REQ[@]}"
an_expect ACTIONS_REPORT BLOCKED ACTION_NOT_ALLOWED 122
assert_no_tool ACTIONS_REPORT

pf_req_set actions "analyze"
an_run_refused ACTIONS_NO_PREFLIGHT "${PF_REQ[@]}"
an_expect ACTIONS_NO_PREFLIGHT BLOCKED INPUT_INVALID 121
assert_no_tool ACTIONS_NO_PREFLIGHT

pf_req_set actions "preflight,analyze,rm"
an_run_refused ACTIONS_UNKNOWN "${PF_REQ[@]}"
an_expect ACTIONS_UNKNOWN BLOCKED ACTION_NOT_ALLOWED 122
assert_no_tool ACTIONS_UNKNOWN

# Missing key, unsupported contract version.
an_req iso-gate qual-missing-key
pf_req_unset timeout_seconds
an_run_refused MISSING_KEY "${PF_REQ[@]}"
an_expect MISSING_KEY BLOCKED INPUT_INVALID 121
assert_no_tool MISSING_KEY
[[ "$(an_value REJECTED_KEY)" == "timeout_seconds" ]] || pf_fail "MISSING_KEY_REJECTED_KEY"

an_req iso-gate qual-version
pf_req_set contract_version 2
an_run_refused CONTRACT_VERSION "${PF_REQ[@]}"
an_expect CONTRACT_VERSION BLOCKED CONTRACT_VERSION_UNSUPPORTED 120
assert_no_tool CONTRACT_VERSION

# Evidence root absent: refused before anything runs, and never created.
an_req iso-gate qual-no-root
pf_req_set evidence_root "$TMP/evidence-absent"
an_run_refused EVIDENCE_ABSENT "${PF_REQ[@]}"
an_expect EVIDENCE_ABSENT BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool EVIDENCE_ABSENT
[[ "$(an_value REJECTED_KEY)" == "evidence_root" ]] || pf_fail "EVIDENCE_ABSENT_REJECTED_KEY"
[[ ! -e "$TMP/evidence-absent" ]] || pf_fail "EVIDENCE_ROOT_CREATED"

# Evidence root writable by group or others: someone else could swap a file.
for mode in 770 707 777; do
    chmod "$mode" "$EVID"
    an_req iso-gate "qual-mode-$mode"
    an_run_refused "EVIDENCE_MODE_$mode" "${PF_REQ[@]}"
    an_expect "EVIDENCE_MODE_$mode" BLOCKED PATH_NOT_ALLOWED 124
    assert_no_tool "EVIDENCE_MODE_$mode"
done
chmod 700 "$EVID"

# Evidence root that is a link to a directory.
mkdir -m 700 "$TMP/evidence-real"
ln -s "$TMP/evidence-real" "$TMP/evidence-link"
an_req iso-gate qual-link-root
pf_req_set evidence_root "$TMP/evidence-link"
an_run_refused EVIDENCE_LINK "${PF_REQ[@]}"
an_expect EVIDENCE_LINK BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool EVIDENCE_LINK
[[ -z "$(ls -A "$TMP/evidence-real")" ]] || pf_fail "EVIDENCE_LINK_FOLLOWED"

# Evidence root that is a regular file.
: > "$TMP/evidence-file"
an_req iso-gate qual-file-root
pf_req_set evidence_root "$TMP/evidence-file"
an_run_refused EVIDENCE_FILE "${PF_REQ[@]}"
an_expect EVIDENCE_FILE BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool EVIDENCE_FILE

pf_pass "REQUEST_AND_EVIDENCE_LOCATION"

# ---------------------------------------------------------------- 11. evidence is never overwritten, never followed

an_modes_reset

# A second run with the same qualification id is refused; the first evidence
# stays exactly as it was.
an_req iso-an qual-pass
SUM_BEFORE="$(cd "$EVID/qual-pass" && cksum ANALYZE.log ANALYZE.result)"
an_run_refused EVIDENCE_REUSE "${PF_REQ[@]}"
an_expect EVIDENCE_REUSE BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool EVIDENCE_REUSE
[[ "$(cd "$EVID/qual-pass" && cksum ANALYZE.log ANALYZE.result)" == "$SUM_BEFORE" ]] || pf_fail "EVIDENCE_REUSE_OVERWRITTEN"

# Each file that could collide refuses the run: log, result, capture, also as a
# dangling link (whose target must not be created).
for name in ANALYZE.log ANALYZE.result ANALYZE.log.partial; do
    id="qual-exists-${name//./-}"
    mkdir -m 700 "$EVID/$id"
    printf '%s\n' "earlier evidence" > "$EVID/$id/$name"
    an_req iso-an "$id"
    an_run_refused "EVIDENCE_EXISTS_$name" "${PF_REQ[@]}"
    an_expect "EVIDENCE_EXISTS_$name" BLOCKED PATH_NOT_ALLOWED 124
    assert_no_tool "EVIDENCE_EXISTS_$name"
    [[ "$(cat "$EVID/$id/$name")" == "earlier evidence" ]] || pf_fail "EVIDENCE_EXISTS_${name}_TOUCHED"

    id="qual-dangling-${name//./-}"
    mkdir -m 700 "$EVID/$id"
    ln -s "$TMP/outside-target" "$EVID/$id/$name"
    an_req iso-an "$id"
    an_run_refused "EVIDENCE_DANGLING_$name" "${PF_REQ[@]}"
    an_expect "EVIDENCE_DANGLING_$name" BLOCKED PATH_NOT_ALLOWED 124
    assert_no_tool "EVIDENCE_DANGLING_$name"
    [[ ! -e "$TMP/outside-target" ]] || pf_fail "EVIDENCE_DANGLING_${name}_FOLLOWED"
done

# A qualification directory that is a link, or open to others, is refused.
mkdir -m 700 "$TMP/outside-dir"
ln -s "$TMP/outside-dir" "$EVID/qual-linked-dir"
an_req iso-an qual-linked-dir
an_run_refused QDIR_LINK "${PF_REQ[@]}"
an_expect QDIR_LINK BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool QDIR_LINK
[[ -z "$(ls -A "$TMP/outside-dir")" ]] || pf_fail "QDIR_LINK_FOLLOWED"

mkdir "$EVID/qual-open-dir"
chmod 777 "$EVID/qual-open-dir"
an_req iso-an qual-open-dir
an_run_refused QDIR_OPEN "${PF_REQ[@]}"
an_expect QDIR_OPEN BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool QDIR_OPEN
[[ -z "$(ls -A "$EVID/qual-open-dir")" ]] || pf_fail "QDIR_OPEN_WRITTEN"
chmod 700 "$EVID/qual-open-dir"

# A qualification directory prepared by the operator (private, empty) is used
# as it is: its mode is kept.
mkdir -m 700 "$EVID/qual-prepared"
an_req iso-an qual-prepared
an_run PREPARED "${PF_REQ[@]}"
an_expect PREPARED PASS - 0 0
an_assert_evidence PREPARED qual-prepared

# A qualification directory that cannot be written: refused before the run.
if [[ "$IS_ROOT" -eq 0 ]]; then
    mkdir -m 500 "$EVID/qual-readonly"
    an_req iso-an qual-readonly
    an_run_refused QDIR_READONLY "${PF_REQ[@]}"
    an_expect QDIR_READONLY BLOCKED PATH_NOT_ALLOWED 124
    assert_no_tool QDIR_READONLY
    chmod 700 "$EVID/qual-readonly"
    echo "${TEST_PREFIX}_READONLY_DIRECTORY=PASS"
else
    echo "${TEST_PREFIX}_READONLY_DIRECTORY=NOT_RUN"
fi

pf_pass "EVIDENCE_NEVER_OVERWRITTEN"

# ---------------------------------------------------------------- 12. evidence that cannot be written after the run

if [[ "$IS_ROOT" -eq 0 ]]; then
    # The tool ran and succeeded, but its evidence cannot be completed: never a
    # PASS. The capture that was already open is kept.
    an_modes_reset
    mkdir -m 700 "$EVID/qual-lock-pass"
    export SHIM_LOCK_DIR="$EVID/qual-lock-pass"
    an_req iso-an qual-lock-pass
    AN_EVIDENCE_EXPECT=changed an_run EVIDENCE_FAILURE "${PF_REQ[@]}"
    chmod 700 "$EVID/qual-lock-pass"
    an_expect EVIDENCE_FAILURE FAIL EVIDENCE_FAILURE 134
    [[ "$(an_value EVIDENCE)" == "FAILED" ]] || pf_fail "EVIDENCE_FAILURE_FACT"
    [[ -z "$(ls "$EVID/qual-lock-pass" | grep -v '^ANALYZE.log.partial$' || true)" ]] || pf_fail "EVIDENCE_FAILURE_FILES"
    [[ "$(cat "$EVID/qual-lock-pass/ANALYZE.log.partial")" == "Analyzing app...
No issues found! (ran in 1.0s)" ]] || pf_fail "EVIDENCE_FAILURE_CAPTURE_LOST"

    # The tool failed: its failure is kept as the reason, the evidence failure
    # is still reported as a fact.
    an_modes_reset
    shim_mode issues
    mkdir -m 700 "$EVID/qual-lock-issues"
    export SHIM_LOCK_DIR="$EVID/qual-lock-issues"
    an_req iso-an qual-lock-issues
    AN_EVIDENCE_EXPECT=changed an_run EVIDENCE_FAILURE_TOOL "${PF_REQ[@]}"
    chmod 700 "$EVID/qual-lock-issues"
    an_expect EVIDENCE_FAILURE_TOOL FAIL COMMAND_FAILED 130 1
    [[ "$(an_value EVIDENCE)" == "FAILED" ]] || pf_fail "EVIDENCE_FAILURE_TOOL_FACT"

    echo "${TEST_PREFIX}_EVIDENCE_FAILURE=PASS"
else
    echo "${TEST_PREFIX}_EVIDENCE_FAILURE=NOT_RUN"
fi

# ---------------------------------------------------------------- 12b. evidence planted during the run

# A file (or a link) that appears between the check and the write is never
# overwritten nor followed: the exclusive create refuses it.
for name in ANALYZE.log ANALYZE.result; do
    for kind in file link; do
        an_modes_reset
        id="qual-plant-${kind}-${name//./-}"
        mkdir -m 700 "$EVID/$id"
        shim_mode plant
        export SHIM_PLANT_PATH="$EVID/$id/$name"
        if [[ "$kind" == "link" ]]; then
            export SHIM_PLANT_TARGET="$TMP/plant-target-$id"
        fi
        an_req iso-an "$id"
        AN_EVIDENCE_EXPECT=changed an_run "PLANT_${kind}_$name" "${PF_REQ[@]}"
        an_expect "PLANT_${kind}_$name" FAIL EVIDENCE_FAILURE 134
        [[ "$(an_value EVIDENCE)" == "FAILED" ]] || pf_fail "PLANT_${kind}_${name}_FACT"

        if [[ "$kind" == "file" ]]; then
            [[ "$(cat "$EVID/$id/$name")" == "PLANTED" ]] || pf_fail "PLANT_${kind}_${name}_OVERWRITTEN"
        else
            [[ -L "$EVID/$id/$name" ]] || pf_fail "PLANT_${kind}_${name}_LINK_REPLACED"
            [[ ! -e "$TMP/plant-target-$id" ]] || pf_fail "PLANT_${kind}_${name}_FOLLOWED"
        fi
    done
done

an_modes_reset
pf_pass "EVIDENCE_PLANTED_DURING_RUN"

# ---------------------------------------------------------------- 13. the isolated checkout is the only place written

an_modes_reset
pf_new_isolation iso-write
shim_mode write
export AN_ISO_CHANGES=1
an_req iso-write qual-write
an_run WRITE "${PF_REQ[@]}"
an_expect WRITE PASS - 0 0
unset AN_ISO_CHANGES

[[ "$(cat "$ISO_ROOT/iso-write/.dart_tool/package_config.json")" == "generated" ]] || pf_fail "WRITE_NOT_IN_CHECKOUT"
[[ ! -e "$SOURCE/.dart_tool" ]] || pf_fail "WRITE_IN_SOURCE"
iso_assert_source_untouched "WRITE_SOURCE"
an_assert_evidence WRITE qual-write

# What the tool wrote makes the checkout "modified": the next operation starts
# with a PREFLIGHT that refuses it, and nothing is deleted or reset.
an_modes_reset
an_req iso-write qual-write-next
an_run_refused WRITE_NEXT "${PF_REQ[@]}"
assert_not_run WRITE_NEXT qual-write-next BLOCKED ISOLATION_REJECTED
[[ -f "$ISO_ROOT/iso-write/.dart_tool/package_config.json" ]] || pf_fail "WRITE_NEXT_CLEANED"

pf_pass "CHECKOUT_ONLY"

# ---------------------------------------------------------------- 14. sourcing runs nothing

an_modes_reset
: > "$PF_LOG"
: > "$PF_GITLOG"
: > "$AN_CALLS"
pf_make_view
set +e
SOURCED_OUT="$(cd "$TMP" && env PATH="$PF_VIEW:$PF_TOOLS" "$BASH" -c 'source "$1"; declare -F cbs_flutter_qual_analyze >/dev/null' x "$ANALYZE" 2>&1)"
SOURCED_RC=$?
set -e
[[ "$SOURCED_RC" -eq 0 && -z "$SOURCED_OUT" ]] || pf_fail "SOURCE_RUNS_$SOURCED_RC"
assert_no_tool SOURCE

pf_pass "SOURCE_ONLY"

# ---------------------------------------------------------------- 15. isolation left as it was by every run

iso_run verify iso-an "$SOURCE" "$ISO_ROOT"
iso_expect_pass "FINAL_VERIFY_AN"
iso_run verify iso-gate "$SOURCE" "$ISO_ROOT"
iso_expect_pass "FINAL_VERIFY_GATE"
iso_assert_source_untouched "FINAL_SOURCE"
[[ "$(git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ')" -eq 4 ]] || pf_fail "FINAL_WORKTREE_COUNT"

pf_pass "NO_SIDE_EFFECT"

# ---------------------------------------------------------------- 16. Bash 3.2

# Native Bash 3.2 (macOS): a PASS, a tool failure and a gate refusal run under it
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
    an_modes_reset
    AN_BASH="$BASH32"
    an_req iso-an qual-bash32-pass
    an_run BASH32_PASS "${PF_REQ[@]}"
    an_expect BASH32_PASS PASS - 0 0

    shim_mode issues
    an_req iso-an qual-bash32-issues
    an_run BASH32_ISSUES "${PF_REQ[@]}"
    an_expect BASH32_ISSUES FAIL COMMAND_FAILED 130 1

    an_modes_reset
    AN_BASH="$BASH32"
    shim_mode hang
    an_req iso-an qual-bash32-hang
    pf_req_set timeout_seconds 3
    an_run BASH32_TIMEOUT "${PF_REQ[@]}"
    an_expect BASH32_TIMEOUT FAIL TIMEOUT 131
    pf_pid_gone "$(cat "$PF_HANG_PID")" 5 || pf_fail "BASH32_TIMEOUT_PROCESS_SURVIVED"

    an_modes_reset
    AN_BASH="$BASH32"
    PF_MISSING="flutter"
    an_req iso-an qual-bash32-gate
    an_run_refused BASH32_GATE "${PF_REQ[@]}"
    assert_not_run BASH32_GATE qual-bash32-gate BLOCKED TOOL_UNAVAILABLE

    echo "${TEST_PREFIX}_BASH32=PASS"
else
    echo "${TEST_PREFIX}_BASH32=NOT_RUN"
fi

an_modes_reset

echo "${TEST_PREFIX}_RESULT=PASS"
