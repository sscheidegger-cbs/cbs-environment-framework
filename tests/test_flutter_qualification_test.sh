#!/usr/bin/env bash

# D04b-C.2f: hermetic test of the Flutter/iOS qualification TEST.
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
TESTOP="$ROOT/cbs/qualification/flutter/test.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_TEST"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/test_lib.sh"
source "$CONTRACT"

[[ -f "$TESTOP" ]] || pf_fail "TEST_OPERATION_MISSING"
bash -n "$TESTOP" || pf_fail "TEST_OPERATION_SYNTAX"

iso_fixture_init
pf_init
tt_init

# The commit that holds the test files, then the isolations built from it.
tt_make_commit

shim_mode() {
    export SHIM_TEST_MODE="$1"
}

# No tool was started at all (not even a probe).
assert_no_tool() {
    [[ -z "$(cat "$PF_LOG")" ]] || pf_fail "${1}_TOOL_CALLED_$(head -n 1 "$PF_LOG" | tr ' ' '_')"
    [[ "$(tt_calls)" -eq 0 ]] || pf_fail "${1}_TEST_CALLED"
    [[ "$(pf_git_calls)" -eq 0 ]] || pf_fail "${1}_GIT_CALLED"
}

# PREFLIGHT did not pass: TEST is NOT_RUN, nothing executed, nothing written.
# Arguments: LABEL QUALIFICATION_ID PREFLIGHT_RESULT PREFLIGHT_REASON
assert_not_run() {
    tt_expect "$1" NOT_RUN PREFLIGHT_NOT_PASSED 136
    [[ "$(tt_value PREFLIGHT_RESULT)" == "$3" ]] || pf_fail "${1}_PREFLIGHT_RESULT_$(tt_value PREFLIGHT_RESULT)"
    [[ "$(tt_value PREFLIGHT_REASON)" == "$4" ]] || pf_fail "${1}_PREFLIGHT_REASON_$(tt_value PREFLIGHT_REASON)"
    [[ "$(tt_calls)" -eq 0 ]] || pf_fail "${1}_TEST_CALLED"
    [[ -z "$(tt_value COMMAND)" ]] || pf_fail "${1}_COMMAND_REPORTED"
    [[ "$(tt_value EVIDENCE)" == "NOT_WRITTEN" ]] || pf_fail "${1}_EVIDENCE_FACT"
    tt_assert_no_evidence "$1" "$2"
}

# A refusal of this operation after a PREFLIGHT PASS: nothing executed, nothing
# written. Arguments: LABEL QUALIFICATION_ID RESULT REASON RC REJECTED_KEY
assert_refused() {
    tt_expect "$1" "$3" "$4" "$5"
    [[ "$(tt_calls)" -eq 0 ]] || pf_fail "${1}_TEST_CALLED"
    [[ -z "$(tt_value COMMAND)" ]] || pf_fail "${1}_COMMAND_REPORTED"
    [[ "$(tt_value EVIDENCE)" == "NOT_WRITTEN" ]] || pf_fail "${1}_EVIDENCE_FACT"
    [[ "$(tt_value REJECTED_KEY)" == "$6" ]] || pf_fail "${1}_REJECTED_KEY_$(tt_value REJECTED_KEY)"
    tt_assert_no_evidence "$1" "$2"
}

# Seconds since the reference given.
elapsed_since() {
    echo "$((SECONDS - $1))"
}

# ---------------------------------------------------------------- 1. PASS, unit_widget, no explicit target

tt_modes_reset
pf_new_isolation iso-t "$TT_COMMIT"
iso_snapshot_source

tt_req iso-t qual-pass
tt_run PASS "${PF_REQ[@]}"
tt_expect PASS PASS - 0 0

[[ "$(tt_calls)" -eq 1 ]] || pf_fail "PASS_TEST_CALLS_$(tt_calls)"
CALL="$(cat "$TT_CALLS")"

# Exactly "flutter test": one argument, run from the isolated checkout, never
# from the source repository, without any device (the simulator given in the
# request is not used by a unit_widget run).
[[ "$CALL" == "$(tt_call_line 1 test "$ISO_ROOT/iso-t")" ]] || pf_fail "PASS_CALL_$CALL"

# PREFLIGHT ran first, on the same request: its seven probes, and no more.
[[ "$(grep -c '^flutter --version$' "$PF_LOG")" -eq 1 ]] || pf_fail "PASS_PREFLIGHT_NOT_RUN"
[[ "$(pf_tool_calls)" -eq 7 ]] || pf_fail "PASS_PREFLIGHT_PROBES_$(pf_tool_calls)"
[[ "$(tt_simulator_lists)" -eq 1 ]] || pf_fail "PASS_SIMULATOR_LISTS_$(tt_simulator_lists)"

[[ "$(tt_value PREFLIGHT_RESULT)" == "PASS" ]] || pf_fail "PASS_PREFLIGHT_RESULT"
[[ -z "$(tt_value PREFLIGHT_REASON)" ]] || pf_fail "PASS_PREFLIGHT_REASON"
[[ "$(tt_value QUALIFICATION_ID)" == "qual-pass" ]] || pf_fail "PASS_QUALIFICATION_ID"
[[ "$(tt_value COMMIT_OBSERVED)" == "$TT_COMMIT" ]] || pf_fail "PASS_COMMIT"
[[ "$(tt_value FLUTTER_VERSION)" == "$PF_FLUTTER_REQUIRED" ]] || pf_fail "PASS_FLUTTER_VERSION"
[[ "$(tt_value COMMAND)" == "flutter_test" ]] || pf_fail "PASS_COMMAND"
[[ "$(tt_value LOG_TRUNCATED)" == "NO" ]] || pf_fail "PASS_LOG_TRUNCATED"
[[ "$(tt_value EVIDENCE)" == "WRITTEN" ]] || pf_fail "PASS_EVIDENCE"
[[ -z "$(tt_value REJECTED_KEY)" ]] || pf_fail "PASS_REJECTED_KEY"
[[ "$(tt_value DURATION_SECONDS)" =~ ^[0-9]+$ ]] || pf_fail "PASS_DURATION"

# Evidence: private, complete, and the result file is the printed answer.
tt_assert_evidence PASS qual-pass
tt_assert_result_file PASS qual-pass
[[ "$(tt_log qual-pass)" == "00:01 +2: All tests passed!" ]] || pf_fail "PASS_LOG_CONTENT"
[[ "$(tt_value LOG_BYTES)" == "$(tt_log_bytes qual-pass)" ]] || pf_fail "PASS_LOG_BYTES"
[[ "$(tt_value LOG_CRC)" == "$(cksum < "$EVID/qual-pass/TEST.log" | cut -d' ' -f1)" ]] || pf_fail "PASS_LOG_CRC"

# The checkout is as created (this shim writes nothing), the source untouched.
[[ -z "$(git -C "$ISO_ROOT/iso-t" status --porcelain)" ]] || pf_fail "PASS_CHECKOUT_DIRTIED"
iso_assert_source_untouched "PASS_SOURCE"

# The isolation manager still verifies the checkout: TEST broke nothing.
iso_run verify iso-t "$SOURCE" "$ISO_ROOT"
iso_expect_pass "PASS_VERIFY"

# The structured answer is stable (only the qualification id differs).
FIRST_OUT="$(printf '%s\n' "$PF_OUT" | grep -v -e QUALIFICATION_ID -e DURATION_SECONDS)"
tt_req iso-t qual-pass-2
tt_run PASS_AGAIN "${PF_REQ[@]}"
tt_expect PASS_AGAIN PASS - 0 0
SECOND_OUT="$(printf '%s\n' "$PF_OUT" | grep -v -e QUALIFICATION_ID -e DURATION_SECONDS)"
[[ "$SECOND_OUT" == "$FIRST_OUT" ]] || pf_fail "PASS_NOT_DETERMINISTIC"

# Without a simulator in the request, the same run: no observation of simulators.
tt_req iso-t qual-pass-nosim
pf_req_unset simulator_udid
pf_req_unset simulator_policy
tt_run PASS_NO_SIMULATOR "${PF_REQ[@]}"
tt_expect PASS_NO_SIMULATOR PASS - 0 0
[[ "$(tt_simulator_lists)" -eq 0 ]] || pf_fail "PASS_NO_SIMULATOR_LISTS"
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 1 test "$ISO_ROOT/iso-t")" ]] || pf_fail "PASS_NO_SIMULATOR_CALL"

pf_pass "PASS_UNIT_WIDGET"

# ---------------------------------------------------------------- 2. PASS, explicit selection

tt_modes_reset
tt_req iso-t qual-select
pf_req_set test_targets "test/a_test.dart,test/widget/b_test.dart"
tt_run SELECT "${PF_REQ[@]}"
tt_expect SELECT PASS - 0 0
[[ "$(tt_calls)" -eq 1 ]] || pf_fail "SELECT_CALLS"
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 3 "test test/a_test.dart test/widget/b_test.dart" "$ISO_ROOT/iso-t")" ]] || pf_fail "SELECT_CALL_$(cat "$TT_CALLS")"
tt_assert_evidence SELECT qual-select
tt_assert_result_file SELECT qual-select

# A single file; the order of the request is the order of the command.
tt_req iso-t qual-select-one
pf_req_set test_targets "test/widget/b_test.dart"
tt_run SELECT_ONE "${PF_REQ[@]}"
tt_expect SELECT_ONE PASS - 0 0
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 2 "test test/widget/b_test.dart" "$ISO_ROOT/iso-t")" ]] || pf_fail "SELECT_ONE_CALL"

tt_req iso-t qual-select-order
pf_req_set test_targets "test/widget/b_test.dart,test/a_test.dart"
tt_run SELECT_ORDER "${PF_REQ[@]}"
tt_expect SELECT_ORDER PASS - 0 0
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 3 "test test/widget/b_test.dart test/a_test.dart" "$ISO_ROOT/iso-t")" ]] || pf_fail "SELECT_ORDER_CALL"

pf_pass "PASS_EXPLICIT_SELECTION"

# ---------------------------------------------------------------- 3. PASS, integration on the simulator given

tt_modes_reset
tt_req_integration iso-t qual-integration
tt_run INTEGRATION "${PF_REQ[@]}"
tt_expect INTEGRATION PASS - 0 0
[[ "$(tt_calls)" -eq 1 ]] || pf_fail "INTEGRATION_CALLS"
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 4 "test integration_test/app_test.dart -d $PF_UDID_BOOTED" "$ISO_ROOT/iso-t")" ]] || pf_fail "INTEGRATION_CALL_$(cat "$TT_CALLS")"

# The simulator was observed twice, read-only: by PREFLIGHT, then by TEST right
# before the run. Nothing else was asked of simctl (any other call is refused
# by the shim and fails the run).
[[ "$(tt_simulator_lists)" -eq 2 ]] || pf_fail "INTEGRATION_SIMULATOR_LISTS_$(tt_simulator_lists)"
tt_assert_evidence INTEGRATION qual-integration
tt_assert_result_file INTEGRATION qual-integration
[[ "$(tt_value COMMAND)" == "flutter_test" ]] || pf_fail "INTEGRATION_COMMAND"

# The identifier is given as the request wrote it (lowercase hexadecimal here).
LOWER_UDID="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
LOWER_UDID_UPPER="AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
{
    printf '== Devices ==\n-- iOS 17.5 --\n'
    printf '    iPhone 15 Pro (%s) (Booted)\n' "$LOWER_UDID_UPPER"
} > "$PF_LIST"
tt_req_integration iso-t qual-integration-lower "$LOWER_UDID"
tt_run INTEGRATION_LOWER "${PF_REQ[@]}"
tt_expect INTEGRATION_LOWER PASS - 0 0
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 4 "test integration_test/app_test.dart -d $LOWER_UDID" "$ISO_ROOT/iso-t")" ]] || pf_fail "INTEGRATION_LOWER_CALL"
tt_devices_default

pf_pass "PASS_INTEGRATION"

# ---------------------------------------------------------------- 4. the exit status of the tool is kept

tt_modes_reset
shim_mode fail
tt_req iso-t qual-fail
tt_run FAILURE "${PF_REQ[@]}"
tt_expect FAILURE FAIL COMMAND_FAILED 130 1
tt_assert_evidence FAILURE qual-fail
tt_assert_result_file FAILURE qual-fail
[[ "$(tt_log qual-fail)" == *"Some tests failed."* ]] || pf_fail "FAILURE_LOG"
[[ "$(tt_value EVIDENCE)" == "WRITTEN" ]] || pf_fail "FAILURE_EVIDENCE"
[[ "$(tt_calls)" -eq 1 ]] || pf_fail "FAILURE_CALLS"

for status in 2 3 64 126 255; do
    tt_modes_reset
    shim_mode rc
    export SHIM_TEST_RC="$status"
    tt_req iso-t "qual-rc-$status"
    tt_run "RC_$status" "${PF_REQ[@]}"
    # The tool status is reported as is; the contract code never replaces it.
    tt_expect "RC_$status" FAIL COMMAND_FAILED 130 "$status"
    tt_assert_evidence "RC_$status" "qual-rc-$status"
done

# A failure of an explicit selection and of an integration run keeps its status too.
tt_modes_reset
shim_mode rc
export SHIM_TEST_RC=7
tt_req iso-t qual-rc-select
pf_req_set test_targets "test/a_test.dart"
tt_run RC_SELECT "${PF_REQ[@]}"
tt_expect RC_SELECT FAIL COMMAND_FAILED 130 7

tt_modes_reset
shim_mode rc
export SHIM_TEST_RC=8
tt_req_integration iso-t qual-rc-integration
tt_run RC_INTEGRATION "${PF_REQ[@]}"
tt_expect RC_INTEGRATION FAIL COMMAND_FAILED 130 8
tt_assert_evidence RC_INTEGRATION qual-rc-integration

# A tool killed by a signal: the status is the shell's, reported exactly.
tt_modes_reset
shim_mode killed
tt_req iso-t qual-killed
tt_run KILLED "${PF_REQ[@]}"
tt_expect KILLED FAIL COMMAND_FAILED 130 137
[[ "$(tt_log qual-killed)" == "about to be killed" ]] || pf_fail "KILLED_LOG"

# No input: the tool sees the end of file at once.
tt_modes_reset
shim_mode stdin
tt_req iso-t qual-stdin
tt_run STDIN "${PF_REQ[@]}"
tt_expect STDIN PASS - 0 0
[[ "$(tt_log qual-stdin)" == "stdin-eof" ]] || pf_fail "STDIN_NOT_EOF"

pf_pass "TOOL_STATUS"

# ---------------------------------------------------------------- 5. timeout

# Hanging tool: killed when the timeout expires, reported as TIMEOUT, log kept,
# nothing left running.
tt_modes_reset
shim_mode hang
tt_req iso-t qual-hang
pf_req_set timeout_seconds 3
STARTED=$SECONDS
tt_run TIMEOUT "${PF_REQ[@]}"
ELAPSED="$(elapsed_since "$STARTED")"
tt_expect TIMEOUT FAIL TIMEOUT 131
[[ "$ELAPSED" -le 20 ]] || pf_fail "TIMEOUT_TOO_SLOW_${ELAPSED}"
[[ "$ELAPSED" -ge 3 ]] || pf_fail "TIMEOUT_TOO_FAST_${ELAPSED}"
tt_assert_evidence TIMEOUT qual-hang
[[ "$(tt_log qual-hang)" == "tests started" ]] || pf_fail "TIMEOUT_LOG"
[[ -s "$PF_HANG_PID" ]] || pf_fail "TIMEOUT_NO_PID"
pf_pid_gone "$(cat "$PF_HANG_PID")" 5 || pf_fail "TIMEOUT_PROCESS_SURVIVED"
[[ "$(pf_ps_count 'cbs-analyze-(supervisor|runner)')" -eq 0 ]] || pf_fail "TIMEOUT_SUPERVISOR_SURVIVED"

# A tool that ignores TERM is killed anyway.
tt_modes_reset
shim_mode hangterm
tt_req iso-t qual-hangterm
pf_req_set timeout_seconds 3
STARTED=$SECONDS
tt_run TIMEOUT_TERM "${PF_REQ[@]}"
ELAPSED="$(elapsed_since "$STARTED")"
tt_expect TIMEOUT_TERM FAIL TIMEOUT 131
[[ "$ELAPSED" -le 20 ]] || pf_fail "TIMEOUT_TERM_TOO_SLOW_${ELAPSED}"
pf_pass "TIMEOUT"

# ---------------------------------------------------------------- 6. log limit

# The limit is exact: a log of log_max_bytes bytes is complete, one byte more
# is exceeded and kept truncated at the limit.
tt_modes_reset
shim_mode bytes
export SHIM_TEST_BYTES=1024
tt_req iso-t qual-exact
pf_req_set log_max_bytes 1024
tt_run LIMIT_EXACT "${PF_REQ[@]}"
tt_expect LIMIT_EXACT PASS - 0 0
[[ "$(tt_log_bytes qual-exact)" -eq 1024 ]] || pf_fail "LIMIT_EXACT_BYTES_$(tt_log_bytes qual-exact)"
[[ "$(tt_value LOG_TRUNCATED)" == "NO" ]] || pf_fail "LIMIT_EXACT_TRUNCATED"

export SHIM_TEST_BYTES=1025
tt_req iso-t qual-over
pf_req_set log_max_bytes 1024
tt_run LIMIT_OVER "${PF_REQ[@]}"
tt_expect LIMIT_OVER FAIL LOG_LIMIT_EXCEEDED 133
tt_assert_evidence LIMIT_OVER qual-over
[[ "$(tt_log_bytes qual-over)" -eq 1024 ]] || pf_fail "LIMIT_OVER_BYTES_$(tt_log_bytes qual-over)"
[[ "$(tt_value LOG_BYTES)" == "1024" ]] || pf_fail "LIMIT_OVER_LOG_BYTES_FACT"
[[ "$(tt_value LOG_TRUNCATED)" == "YES" ]] || pf_fail "LIMIT_OVER_TRUNCATED_FACT"
tt_assert_result_file LIMIT_OVER qual-over

# A talkative tool is cut by the limit, quickly.
tt_modes_reset
shim_mode big
export SHIM_TEST_LINES=200000
tt_req iso-t qual-big
pf_req_set log_max_bytes 4096
STARTED=$SECONDS
tt_run LIMIT_BIG "${PF_REQ[@]}"
ELAPSED="$(elapsed_since "$STARTED")"
tt_expect LIMIT_BIG FAIL LOG_LIMIT_EXCEEDED 133
[[ "$ELAPSED" -le 20 ]] || pf_fail "LIMIT_BIG_TOO_SLOW_${ELAPSED}"
[[ "$(tt_log_bytes qual-big)" -eq 4096 ]] || pf_fail "LIMIT_BIG_BYTES"

# The size wins over the status of the tool, on a selection and on an integration run.
tt_modes_reset
shim_mode big
export SHIM_TEST_LINES=3000
tt_req_integration iso-t qual-big-integration
pf_req_set log_max_bytes 2048
tt_run LIMIT_INTEGRATION "${PF_REQ[@]}"
tt_expect LIMIT_INTEGRATION FAIL LOG_LIMIT_EXCEEDED 133
[[ "$(tt_log_bytes qual-big-integration)" -eq 2048 ]] || pf_fail "LIMIT_INTEGRATION_BYTES"

pf_pass "LOG_LIMIT"

# ---------------------------------------------------------------- 7. secrets are redacted before they are written

tt_modes_reset
shim_mode secret
tt_req iso-t qual-secret
tt_run SECRET "${PF_REQ[@]}"
tt_expect SECRET FAIL COMMAND_FAILED 130 1
tt_assert_evidence SECRET qual-secret

LOG="$(tt_log qual-secret)"
for leaked in ghp_abcdefghijklmnopqrstuvwxyz0123456789 abcdef.ghijkl.mnopqr hunter2secret supersecretvalue123 AKIAABCDEFGHIJKLMNOP private-body; do
    case "$LOG" in
        *"$leaked"*) pf_fail "SECRET_LOG_LEAK_$leaked" ;;
    esac
    # Not in the answer or in its file either.
    printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e "$leaked" >/dev/null && pf_fail "SECRET_ANSWER_LEAK_$leaked"
    grep -F -e "$leaked" "$EVID/qual-secret/TEST.result" >/dev/null && pf_fail "SECRET_RESULT_FILE_LEAK_$leaked"
done

[[ "$LOG" == *"[REDACTED]"* ]] || pf_fail "SECRET_NOT_REDACTED"
[[ "$LOG" == *"ordinary line kept"* ]] || pf_fail "SECRET_OVERREDACTED"

# The raw capture never stays on disk, under any name.
[[ -z "$(grep -rl -e hunter2secret -e supersecretvalue123 "$EVID" 2>/dev/null || true)" ]] || pf_fail "SECRET_ON_DISK"

# Lines that imitate the answer of the executor are only text of the log.
tt_modes_reset
shim_mode forged
tt_req iso-t qual-forged
tt_run FORGED "${PF_REQ[@]}"
tt_expect FORGED FAIL COMMAND_FAILED 130 1
[[ "$(tt_log qual-forged)" == *"CBS_FLUTTER_QUAL_RESULT=PASS"* ]] || pf_fail "FORGED_NOT_IN_LOG"
[[ "$(printf '%s\n' "$PF_OUT" | grep -c '^CBS_FLUTTER_QUAL_RESULT=')" -eq 1 ]] || pf_fail "FORGED_RESULT_LINES"

pf_pass "REDACTION"

# ---------------------------------------------------------------- 8. PREFLIGHT must be PASS

tt_modes_reset
pf_new_isolation iso-gate "$TT_COMMIT"

# Flutter of another version.
export SHIM_FLUTTER_VERSION="0.0.1"
tt_req iso-gate qual-gate-version
tt_run_refused GATE_VERSION "${PF_REQ[@]}"
assert_not_run GATE_VERSION qual-gate-version BLOCKED TOOLCHAIN_INCOMPATIBLE
unset SHIM_FLUTTER_VERSION

# Flutter that fails, and flutter that is absent.
export SHIM_FLUTTER_MODE=fail
tt_req iso-gate qual-gate-fail
tt_run_refused GATE_FLUTTER_FAIL "${PF_REQ[@]}"
assert_not_run GATE_FLUTTER_FAIL qual-gate-fail FAIL COMMAND_FAILED
unset SHIM_FLUTTER_MODE

PF_MISSING="flutter"
tt_req iso-gate qual-gate-missing
tt_run_refused GATE_FLUTTER_MISSING "${PF_REQ[@]}"
assert_not_run GATE_FLUTTER_MISSING qual-gate-missing BLOCKED TOOL_UNAVAILABLE
unset PF_MISSING

# Xcode too old, no iphoneos SDK, no simctl.
export SHIM_XCODE_VERSION="9.0"
tt_req iso-gate qual-gate-xcode
tt_run_refused GATE_XCODE "${PF_REQ[@]}"
assert_not_run GATE_XCODE qual-gate-xcode BLOCKED TOOLCHAIN_INCOMPATIBLE
unset SHIM_XCODE_VERSION

export SHIM_SDK_IPHONEOS_MODE=missing
tt_req iso-gate qual-gate-sdk
tt_run_refused GATE_SDK "${PF_REQ[@]}"
assert_not_run GATE_SDK qual-gate-sdk BLOCKED TOOLCHAIN_INCOMPATIBLE
unset SHIM_SDK_IPHONEOS_MODE

export SHIM_SIMCTL_MODE=missing
tt_req_integration iso-gate qual-gate-simctl
tt_run_refused GATE_SIMCTL "${PF_REQ[@]}"
assert_not_run GATE_SIMCTL qual-gate-simctl BLOCKED TOOL_UNAVAILABLE
unset SHIM_SIMCTL_MODE

# A simulator that does not exist, or that is not an iOS device: PREFLIGHT
# refuses, the reason of PREFLIGHT is preserved.
for udid in "$PF_UDID_ABSENT" "$PF_UDID_UNAVAILABLE" "$PF_UDID_TVOS"; do
    tt_req_integration iso-gate "qual-gate-sim-$udid" "$udid"
    tt_run_refused "GATE_SIMULATOR_$udid" "${PF_REQ[@]}"
    assert_not_run "GATE_SIMULATOR_$udid" "qual-gate-sim-$udid" BLOCKED SIMULATOR_UNAVAILABLE
done

tt_req iso-gate qual-gate-sim-unit
pf_req_set simulator_udid "$PF_UDID_ABSENT"
tt_run_refused GATE_SIMULATOR_UNIT "${PF_REQ[@]}"
assert_not_run GATE_SIMULATOR_UNIT qual-gate-sim-unit BLOCKED SIMULATOR_UNAVAILABLE

# Checkout that is not the requested commit, not the expected origin, not known
# to CBS, not owned by CBS, modified.
tt_req iso-gate qual-gate-commit
pf_req_set commit "$C1"
tt_run_refused GATE_COMMIT "${PF_REQ[@]}"
assert_not_run GATE_COMMIT qual-gate-commit BLOCKED ISOLATION_REJECTED

tt_req iso-gate qual-gate-origin
pf_req_set expected_origin "https://example.invalid/other/app.git"
tt_run_refused GATE_ORIGIN "${PF_REQ[@]}"
assert_not_run GATE_ORIGIN qual-gate-origin BLOCKED ISOLATION_REJECTED

tt_req iso-unknown qual-gate-unknown
tt_run_refused GATE_UNKNOWN "${PF_REQ[@]}"
assert_not_run GATE_UNKNOWN qual-gate-unknown BLOCKED ISOLATION_REJECTED

mkdir "$ISO_ROOT/iso-foreign"
printf '%s\n' "not made by CBS" > "$ISO_ROOT/iso-foreign/file.txt"
tt_req iso-foreign qual-gate-foreign
tt_run_refused GATE_FOREIGN "${PF_REQ[@]}"
assert_not_run GATE_FOREIGN qual-gate-foreign BLOCKED ISOLATION_REJECTED

printf '%s\n' "local change" > "$ISO_ROOT/iso-gate/untracked.txt"
tt_req iso-gate qual-gate-dirty
tt_run_refused GATE_DIRTY "${PF_REQ[@]}"
assert_not_run GATE_DIRTY qual-gate-dirty BLOCKED ISOLATION_REJECTED
[[ "$(cat "$ISO_ROOT/iso-gate/untracked.txt")" == "local change" ]] || pf_fail "GATE_DIRTY_FILE_TOUCHED"
rm -f "$ISO_ROOT/iso-gate/untracked.txt"

# The gate is not sticky: the same checkout, repaired, is accepted.
tt_req iso-gate qual-gate-repaired
tt_run GATE_REPAIRED "${PF_REQ[@]}"
tt_expect GATE_REPAIRED PASS - 0 0

pf_pass "PREFLIGHT_GATE"

# ---------------------------------------------------------------- 9. the gate reads the answer of PREFLIGHT strictly

# PREFLIGHT is replaced by a function that prints a chosen answer: only a
# coherent PASS lets TEST start. The driver sources test.sh (nothing runs when
# it is sourced) and redefines cbs_flutter_qual_preflight.
cat > "$TMP/stub-driver.sh" <<'EOF'
set -u
source "$1"
shift
cbs_flutter_qual_preflight() {
    printf '%s\n' "$STUB_OUT"
    return "${STUB_RC:-0}"
}
cbs_flutter_qual_test "$@"
exit $?
EOF

STUB_PASS="CBS_FLUTTER_QUAL_PREFLIGHT_COMMIT_OBSERVED=$TT_COMMIT
CBS_FLUTTER_QUAL_PREFLIGHT_FLUTTER_VERSION=$PF_FLUTTER_REQUIRED
CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT
CBS_FLUTTER_QUAL_OPERATION_RESULT=PASS
CBS_FLUTTER_QUAL_OPERATION_RC=0
CBS_FLUTTER_QUAL_CONTRACT_VERSION=1
CBS_FLUTTER_QUAL_RESULT=PASS"

STUB_DRIVER="$TMP/stub-driver.sh"

# stub_run <label> <isolation id> <qualification id> <stub output> <stub rc>
# Runs TEST with the stubbed PREFLIGHT on the request of tt_req (the caller may
# have adapted PF_REQ afterwards: it is rebuilt here from the arguments only).
stub_run() {
    export STUB_OUT="$4"
    export STUB_RC="$5"

    tt_modes_reset
    tt_req "$2" "$3"
    TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" TT_EVIDENCE_EXPECT=same tt_run "$1" "$TESTOP" "${PF_REQ[@]}"
}

# The reference answer, coherent: TEST starts.
STUB_RC=0
export STUB_OUT="$STUB_PASS"
tt_modes_reset
tt_req iso-gate qual-stub-pass
TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" tt_run STUB_PASS "$TESTOP" "${PF_REQ[@]}"
tt_expect STUB_PASS PASS - 0 0
[[ "$(tt_calls)" -eq 1 ]] || pf_fail "STUB_PASS_CALLS"

# A coherent PASS but a non-zero status.
stub_run STUB_RC iso-gate qual-stub-rc "$STUB_PASS" 1
assert_not_run STUB_RC qual-stub-rc NOT_RUN ""

# PASS lines carrying a reason, a wrong operation, a result line that is not
# last, no output at all.
stub_run STUB_REASON iso-gate qual-stub-reason "CBS_FLUTTER_QUAL_REASON=INPUT_INVALID
$STUB_PASS" 0
assert_not_run STUB_REASON qual-stub-reason NOT_RUN ""

stub_run STUB_OPERATION iso-gate qual-stub-operation "$(printf '%s\n' "$STUB_PASS" | sed 's/^CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT$/CBS_FLUTTER_QUAL_OPERATION=TEST/')" 0
assert_not_run STUB_OPERATION qual-stub-operation NOT_RUN ""

stub_run STUB_NOT_LAST iso-gate qual-stub-not-last "$STUB_PASS
CBS_FLUTTER_QUAL_PREFLIGHT_NOTE=late" 0
assert_not_run STUB_NOT_LAST qual-stub-not-last NOT_RUN ""

stub_run STUB_EMPTY iso-gate qual-stub-empty "" 0
assert_not_run STUB_EMPTY qual-stub-empty NOT_RUN ""

# A refusal of PREFLIGHT is reported with its closed reason ...
stub_run STUB_FAIL iso-gate qual-stub-fail "CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT
CBS_FLUTTER_QUAL_OPERATION_RESULT=FAIL
CBS_FLUTTER_QUAL_REASON=COMMAND_FAILED
CBS_FLUTTER_QUAL_RESULT=FAIL" 130
assert_not_run STUB_FAIL qual-stub-fail FAIL COMMAND_FAILED

# ... but never with a reason that is not one of the contract.
stub_run STUB_INJECTION iso-gate qual-stub-injection "CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT
CBS_FLUTTER_QUAL_OPERATION_RESULT=FAIL
CBS_FLUTTER_QUAL_REASON=rm_-rf_/_;_injected
CBS_FLUTTER_QUAL_RESULT=FAIL" 130
assert_not_run STUB_INJECTION qual-stub-injection FAIL ""

# A PASS whose flutter vanished before TEST: the tool is looked up again.
STUB_RC=0
export STUB_OUT="$STUB_PASS"
tt_modes_reset
tt_req iso-gate qual-stub-vanished
PF_MISSING="flutter"
TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" TT_EVIDENCE_EXPECT=same tt_run STUB_VANISHED "$TESTOP" "${PF_REQ[@]}"
unset PF_MISSING
tt_expect STUB_VANISHED BLOCKED TOOL_UNAVAILABLE 127
[[ "$(tt_calls)" -eq 0 ]] || pf_fail "STUB_VANISHED_CALLED"
tt_assert_no_evidence STUB_VANISHED qual-stub-vanished
unset STUB_OUT STUB_RC

pf_pass "GATE_STRICT"

# ---------------------------------------------------------------- 10. invalid requests

tt_modes_reset

# No argument: usage.
tt_run_refused USAGE
tt_expect USAGE BLOCKED USAGE 64
assert_no_tool USAGE

# TEST must be selected; a mutating action cannot be selected without PREFLIGHT.
tt_req iso-t qual-actions
pf_req_unset test_scope
pf_req_set actions "preflight"
tt_run_refused ACTIONS_NO_TEST "${PF_REQ[@]}"
tt_expect ACTIONS_NO_TEST BLOCKED ACTION_NOT_ALLOWED 122
assert_no_tool ACTIONS_NO_TEST
[[ "$(tt_value REJECTED_KEY)" == "actions" ]] || pf_fail "ACTIONS_REJECTED_KEY"

pf_req_set actions "preflight,analyze"
tt_run_refused ACTIONS_ANALYZE_ONLY "${PF_REQ[@]}"
tt_expect ACTIONS_ANALYZE_ONLY BLOCKED ACTION_NOT_ALLOWED 122
assert_no_tool ACTIONS_ANALYZE_ONLY

pf_req_set actions "report"
tt_run_refused ACTIONS_REPORT "${PF_REQ[@]}"
tt_expect ACTIONS_REPORT BLOCKED ACTION_NOT_ALLOWED 122
assert_no_tool ACTIONS_REPORT

tt_req iso-t qual-actions
pf_req_set actions "test"
tt_run_refused ACTIONS_NO_PREFLIGHT "${PF_REQ[@]}"
tt_expect ACTIONS_NO_PREFLIGHT BLOCKED INPUT_INVALID 121
assert_no_tool ACTIONS_NO_PREFLIGHT

tt_req iso-t qual-actions
pf_req_set actions "preflight,test,rm"
tt_run_refused ACTIONS_UNKNOWN "${PF_REQ[@]}"
tt_expect ACTIONS_UNKNOWN BLOCKED ACTION_NOT_ALLOWED 122
assert_no_tool ACTIONS_UNKNOWN

# Scope: required with TEST, closed set.
tt_req iso-t qual-scope
pf_req_unset test_scope
tt_run_refused SCOPE_MISSING "${PF_REQ[@]}"
tt_expect SCOPE_MISSING BLOCKED INPUT_INVALID 121
assert_no_tool SCOPE_MISSING
[[ "$(tt_value REJECTED_KEY)" == "test_scope" ]] || pf_fail "SCOPE_MISSING_KEY"

for scope in e2e unit widget Integration unit_widget,integration ""; do
    tt_req iso-t qual-scope
    pf_req_set test_scope "$scope"
    tt_run_refused "SCOPE_INVALID" "${PF_REQ[@]}"
    tt_expect SCOPE_INVALID BLOCKED INPUT_INVALID 121
    assert_no_tool SCOPE_INVALID
done

# Targets: the contract's own rules (limits, scope directory, form, duplicates).
# Arguments of the loop: the value, the expected reason and rc.
check_targets() {
    local scope="$1"
    local value="$2"
    local reason="$3"
    local rc="$4"

    tt_req iso-t qual-targets
    pf_req_set test_scope "$scope"
    pf_req_set test_targets "$value"

    if [[ "$scope" == "integration" ]]; then
        pf_req_set simulator_udid "$PF_UDID_BOOTED"
    fi

    tt_run_refused TARGETS "${PF_REQ[@]}"
    tt_expect TARGETS BLOCKED "$reason" "$rc"
    assert_no_tool TARGETS
    [[ "$(tt_value REJECTED_KEY)" == "test_targets" ]] || pf_fail "TARGETS_KEY_$value"
}

check_targets unit_widget "integration_test/app_test.dart" INPUT_INVALID 121
check_targets integration "test/a_test.dart" INPUT_INVALID 121
check_targets unit_widget "test/a_test.dart,test/a_test.dart" INPUT_INVALID 121
check_targets unit_widget "test/a_test.dart," INPUT_INVALID 121
check_targets unit_widget ",test/a_test.dart" INPUT_INVALID 121
check_targets unit_widget "test/../a_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "test/widget/../a_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "test//a_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "test/./a_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "/etc/passwd_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "/test/a_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "./test/a_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "test/a_test.dart/" PATH_NOT_ALLOWED 124
check_targets unit_widget "test/a test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "test/*_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "test/{a,b}_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "test/a_test.sh" PATH_NOT_ALLOWED 124
check_targets unit_widget "test/a.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "lib/a_test.dart" PATH_NOT_ALLOWED 124
check_targets unit_widget "test" PATH_NOT_ALLOWED 124
check_targets unit_widget "tests/a_test.dart" PATH_NOT_ALLOWED 124

# More than sixteen targets.
MANY=""
n=0
while [[ "$n" -lt 17 ]]; do
    MANY="$MANY,test/t${n}_test.dart"
    n=$((n + 1))
done
check_targets unit_widget "${MANY#,}" INPUT_INVALID 121

# Anything that looks like an option or a secret is refused whatever the key.
for word in --no-pub --machine --coverage --update-goldens --dart-define=A=b --dart-define-from-file=env.json -d "-d $PF_UDID_BOOTED" flutter test analyze 'KEY' '=value' 'Key=value'; do
    tt_req iso-t qual-args
    tt_run_refused ARGUMENT "${PF_REQ[@]}" "$word"
    [[ "$PF_RC" -ge 120 && "$PF_RC" -le 125 ]] || pf_fail "ARGUMENT_RC_${PF_RC}"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "BLOCKED" ]] || pf_fail "ARGUMENT_NOT_BLOCKED"
    assert_no_tool ARGUMENT
done

for key in flutter_args test_args args device device_id d coverage machine name plain_name tags reporter extra; do
    tt_req iso-t qual-keys
    tt_run_refused "KEY_$key" "${PF_REQ[@]}" "$key=--coverage"
    tt_expect "KEY_$key" BLOCKED ARGUMENT_REFUSED 123
    assert_no_tool "KEY_$key"
done

for key in token secret password dart_define dart_define_from_file api_key; do
    tt_req iso-t qual-secret-keys
    tt_run_refused "SECRET_$key" "${PF_REQ[@]}" "$key=hunter2-value"
    tt_expect "SECRET_$key" BLOCKED SECRET_REFUSED 125
    assert_no_tool "SECRET_$key"
    printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'hunter2-value' >/dev/null && pf_fail "SECRET_${key}_ECHOED"
done

# Simulator: an explicit identifier, never an alias.
for udid in booted all "" 22222222-2222-4222-8222-22222222222 22222222222242228222222222222222 "22222222-2222-4222-8222-222222222222 "; do
    tt_req_integration iso-t qual-udid
    pf_req_set simulator_udid "$udid"
    tt_run_refused UDID "${PF_REQ[@]}"
    tt_expect UDID BLOCKED INPUT_INVALID 121
    assert_no_tool UDID
done

tt_req_integration iso-t qual-udid
pf_req_unset simulator_udid
tt_run_refused UDID_MISSING "${PF_REQ[@]}"
tt_expect UDID_MISSING BLOCKED INPUT_INVALID 121
assert_no_tool UDID_MISSING
[[ "$(tt_value REJECTED_KEY)" == "simulator_udid" ]] || pf_fail "UDID_MISSING_KEY"

tt_req iso-t qual-policy
pf_req_set simulator_policy create
tt_run_refused POLICY_CREATE "${PF_REQ[@]}"
tt_expect POLICY_CREATE BLOCKED INPUT_INVALID 121
assert_no_tool POLICY_CREATE

tt_req iso-t qual-policy
pf_req_set simulator_policy boot
tt_run_refused POLICY_BOOT "${PF_REQ[@]}"
tt_expect POLICY_BOOT BLOCKED INPUT_INVALID 121
assert_no_tool POLICY_BOOT

# Missing key, unsupported contract version, duplicate key.
tt_req iso-t qual-missing-key
pf_req_unset timeout_seconds
tt_run_refused MISSING_KEY "${PF_REQ[@]}"
tt_expect MISSING_KEY BLOCKED INPUT_INVALID 121
assert_no_tool MISSING_KEY
[[ "$(tt_value REJECTED_KEY)" == "timeout_seconds" ]] || pf_fail "MISSING_KEY_REJECTED_KEY"

tt_req iso-t qual-version
pf_req_set contract_version 2
tt_run_refused CONTRACT_VERSION "${PF_REQ[@]}"
tt_expect CONTRACT_VERSION BLOCKED CONTRACT_VERSION_UNSUPPORTED 120
assert_no_tool CONTRACT_VERSION

tt_req iso-t qual-duplicate
tt_run_refused DUPLICATE "${PF_REQ[@]}" "test_targets=test/a_test.dart" "test_targets=test/widget/b_test.dart"
tt_expect DUPLICATE BLOCKED INPUT_INVALID 121
assert_no_tool DUPLICATE

# Evidence root absent, writable by others, a link, a regular file: refused
# before anything runs, and never created.
tt_req iso-t qual-no-root
pf_req_set evidence_root "$TMP/evidence-absent"
tt_run_refused EVIDENCE_ABSENT "${PF_REQ[@]}"
tt_expect EVIDENCE_ABSENT BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool EVIDENCE_ABSENT
[[ "$(tt_value REJECTED_KEY)" == "evidence_root" ]] || pf_fail "EVIDENCE_ABSENT_REJECTED_KEY"
[[ ! -e "$TMP/evidence-absent" ]] || pf_fail "EVIDENCE_ROOT_CREATED"

for mode in 770 707 777; do
    chmod "$mode" "$EVID"
    tt_req iso-t "qual-mode-$mode"
    tt_run_refused "EVIDENCE_MODE_$mode" "${PF_REQ[@]}"
    tt_expect "EVIDENCE_MODE_$mode" BLOCKED PATH_NOT_ALLOWED 124
    assert_no_tool "EVIDENCE_MODE_$mode"
done
chmod 700 "$EVID"

mkdir -m 700 "$TMP/evidence-real"
ln -s "$TMP/evidence-real" "$TMP/evidence-link"
tt_req iso-t qual-link-root
pf_req_set evidence_root "$TMP/evidence-link"
tt_run_refused EVIDENCE_LINK "${PF_REQ[@]}"
tt_expect EVIDENCE_LINK BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool EVIDENCE_LINK
[[ -z "$(ls -A "$TMP/evidence-real")" ]] || pf_fail "EVIDENCE_LINK_FOLLOWED"

pf_pass "INVALID_REQUESTS"

# ---------------------------------------------------------------- 11. integration without explicit target (open contract decision)

# The contract accepts it; TEST refuses it on its own, before PREFLIGHT, with
# an existing reason: no tool is started, nothing is written.
tt_modes_reset
tt_req_integration iso-t qual-int-notarget
pf_req_unset test_targets
tt_run_refused INTEGRATION_NO_TARGET "${PF_REQ[@]}"
assert_no_tool INTEGRATION_NO_TARGET
tt_expect INTEGRATION_NO_TARGET BLOCKED INPUT_INVALID 121
[[ "$(tt_value REJECTED_KEY)" == "test_targets" ]] || pf_fail "INTEGRATION_NO_TARGET_KEY"
[[ "$(tt_value EVIDENCE)" == "NOT_WRITTEN" ]] || pf_fail "INTEGRATION_NO_TARGET_EVIDENCE"
tt_assert_no_evidence INTEGRATION_NO_TARGET qual-int-notarget

# The contract itself still accepts that request (it is not changed here).
fq_request_reset
fq_request_set actions "preflight,test"
fq_request_set test_scope integration
fq_request_unset test_targets
fq_request_set simulator_udid "$PF_UDID_BOOTED"
fq_validate_request
[[ "$FQ_RC" -eq 0 ]] || pf_fail "CONTRACT_CHANGED_FOR_INTEGRATION_WITHOUT_TARGETS"

pf_pass "INTEGRATION_WITHOUT_TARGETS"

# ---------------------------------------------------------------- 12. targets absent, not regular

tt_modes_reset

tt_req iso-t qual-absent
pf_req_set test_targets "test/missing_test.dart"
tt_run_refused TARGET_ABSENT "${PF_REQ[@]}"
assert_refused TARGET_ABSENT qual-absent BLOCKED INPUT_INVALID 121 test_targets
# PREFLIGHT did run (the checkout is verified before the selection is read).
[[ "$(grep -c '^flutter --version$' "$PF_LOG")" -eq 1 ]] || pf_fail "TARGET_ABSENT_NO_PREFLIGHT"

# One present and one absent: nothing is executed.
tt_req iso-t qual-absent-one
pf_req_set test_targets "test/a_test.dart,test/widget/missing_test.dart"
tt_run_refused TARGET_ONE_ABSENT "${PF_REQ[@]}"
assert_refused TARGET_ONE_ABSENT qual-absent-one BLOCKED INPUT_INVALID 121 test_targets

# A directory below a file, a missing directory.
tt_req iso-t qual-absent-below-file
pf_req_set test_targets "test/a_test.dart/b_test.dart"
tt_run_refused TARGET_BELOW_FILE "${PF_REQ[@]}"
assert_refused TARGET_BELOW_FILE qual-absent-below-file BLOCKED INPUT_INVALID 121 test_targets

tt_req iso-t qual-absent-dir
pf_req_set test_targets "test/nodir/b_test.dart"
tt_run_refused TARGET_NO_DIR "${PF_REQ[@]}"
assert_refused TARGET_NO_DIR qual-absent-dir BLOCKED INPUT_INVALID 121 test_targets

# A directory named like a test file is not a test file.
tt_req iso-t qual-irregular
pf_req_set test_targets "test/dir_test.dart"
tt_run_refused TARGET_DIRECTORY "${PF_REQ[@]}"
assert_refused TARGET_DIRECTORY qual-irregular BLOCKED PATH_NOT_ALLOWED 124 test_targets

# A file of the other scope's directory is absent for an integration run.
tt_req_integration iso-t qual-int-absent
pf_req_set test_targets "integration_test/missing_test.dart"
tt_run_refused TARGET_INTEGRATION_ABSENT "${PF_REQ[@]}"
assert_refused TARGET_INTEGRATION_ABSENT qual-int-absent BLOCKED INPUT_INVALID 121 test_targets
[[ "$(tt_simulator_lists)" -eq 1 ]] || pf_fail "TARGET_INTEGRATION_ABSENT_SIMULATOR_LISTS"

# The refusal leaves the qualification id free: the corrected request runs.
tt_req iso-t qual-absent
pf_req_set test_targets "test/a_test.dart"
tt_run TARGET_CORRECTED "${PF_REQ[@]}"
tt_expect TARGET_CORRECTED PASS - 0 0

pf_pass "TARGETS_ABSENT"

# ---------------------------------------------------------------- 13. symbolic links (checkouts built for the purpose, PREFLIGHT stubbed)

# These checkouts are plain directories of the isolation root: the real
# isolation manager is not the subject here, the selection is. PREFLIGHT is
# replaced by the coherent answer used above.
mkdir -p "$TMP/outside/dir" "$TMP/outside-test" "$TMP/outside-int"
printf '%s\n' "void main() {}" > "$TMP/outside/x_test.dart"
printf '%s\n' "void main() {}" > "$TMP/outside/dir/x_test.dart"
printf '%s\n' "void main() {}" > "$TMP/outside-test/x_test.dart"
printf '%s\n' "void main() {}" > "$TMP/outside-int/app_test.dart"

# iso-ln1: links of every kind below "test".
mkdir -p "$ISO_ROOT/iso-ln1/test" "$ISO_ROOT/iso-ln1/integration_test"
printf '%s\n' "void main() {}" > "$ISO_ROOT/iso-ln1/test/ok_test.dart"
printf '%s\n' "void main() {}" > "$ISO_ROOT/iso-ln1/integration_test/app_test.dart"
ln -s ok_test.dart "$ISO_ROOT/iso-ln1/test/link_test.dart"
ln -s missing-target "$ISO_ROOT/iso-ln1/test/dangling_test.dart"
ln -s "$TMP/outside/x_test.dart" "$ISO_ROOT/iso-ln1/test/escape_test.dart"
ln -s "$TMP/outside/dir" "$ISO_ROOT/iso-ln1/test/linkdir"

# iso-ln2: "test" itself is a link to a directory outside the checkout.
mkdir -p "$ISO_ROOT/iso-ln2"
ln -s "$TMP/outside-test" "$ISO_ROOT/iso-ln2/test"

# iso-ln3: "integration_test" is a link.
mkdir -p "$ISO_ROOT/iso-ln3/test"
printf '%s\n' "void main() {}" > "$ISO_ROOT/iso-ln3/test/ok_test.dart"
ln -s "$TMP/outside-int" "$ISO_ROOT/iso-ln3/integration_test"

# iso-ln4: clean, with both directories.
mkdir -p "$ISO_ROOT/iso-ln4/test/widget" "$ISO_ROOT/iso-ln4/integration_test"
printf '%s\n' "void main() {}" > "$ISO_ROOT/iso-ln4/test/ok_test.dart"
printf '%s\n' "void main() {}" > "$ISO_ROOT/iso-ln4/test/widget/w_test.dart"
printf '%s\n' "void main() {}" > "$ISO_ROOT/iso-ln4/integration_test/app_test.dart"

# iso-ln5: no "test" directory at all.
mkdir -p "$ISO_ROOT/iso-ln5"

# The reference: a plain file of iso-ln1 is accepted (the stubbed flow works).
STUB_RC=0
export STUB_OUT="$STUB_PASS"

# link_run <label> <isolation id> <qualification id> <targets or empty> [<scope>]
# LINK_EVIDENCE=changed states that the run is expected to write its evidence
# (a refusal writes nothing: "same").
link_run() {
    local label="$1"
    local expectation="${LINK_EVIDENCE:-same}"

    tt_modes_reset
    if [[ "${5:-unit_widget}" == "integration" ]]; then
        tt_req_integration "$2" "$3"
    else
        tt_req "$2" "$3"
    fi

    if [[ -n "$4" ]]; then
        pf_req_set test_targets "$4"
    fi

    TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" TT_EVIDENCE_EXPECT="$expectation" tt_run "$label" "$TESTOP" "${PF_REQ[@]}"
}

tt_modes_reset
tt_req iso-ln1 qual-ln-ok
pf_req_set test_targets "test/ok_test.dart"
TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" tt_run LINK_REFERENCE "$TESTOP" "${PF_REQ[@]}"
tt_expect LINK_REFERENCE PASS - 0 0
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 2 "test test/ok_test.dart" "$ISO_ROOT/iso-ln1")" ]] || pf_fail "LINK_REFERENCE_CALL"

# A target that is a link (to a file inside, dangling, to a file outside), or
# below a link: PATH_NOT_ALLOWED, key test_targets, nothing executed.
link_run LINK_FILE iso-ln1 qual-ln-file "test/link_test.dart"
assert_refused LINK_FILE qual-ln-file BLOCKED PATH_NOT_ALLOWED 124 test_targets

link_run LINK_DANGLING iso-ln1 qual-ln-dangling "test/dangling_test.dart"
assert_refused LINK_DANGLING qual-ln-dangling BLOCKED PATH_NOT_ALLOWED 124 test_targets

link_run LINK_ESCAPE iso-ln1 qual-ln-escape "test/escape_test.dart"
assert_refused LINK_ESCAPE qual-ln-escape BLOCKED PATH_NOT_ALLOWED 124 test_targets

link_run LINK_DIRECTORY iso-ln1 qual-ln-dir "test/linkdir/x_test.dart"
assert_refused LINK_DIRECTORY qual-ln-dir BLOCKED PATH_NOT_ALLOWED 124 test_targets

# One link among good targets refuses everything.
link_run LINK_AMONG iso-ln1 qual-ln-among "test/ok_test.dart,test/link_test.dart"
assert_refused LINK_AMONG qual-ln-among BLOCKED PATH_NOT_ALLOWED 124 test_targets

# "test" is a link: with and without explicit target.
link_run LINK_TEST_DIR iso-ln2 qual-ln-testdir "test/x_test.dart"
assert_refused LINK_TEST_DIR qual-ln-testdir BLOCKED PATH_NOT_ALLOWED 124 test_targets

link_run LINK_TEST_DIR_DEFAULT iso-ln2 qual-ln-testdir-default ""
assert_refused LINK_TEST_DIR_DEFAULT qual-ln-testdir-default BLOCKED PATH_NOT_ALLOWED 124 test_scope

# No explicit target, a link below "test": refused too (flutter would read it).
link_run LINK_DEFAULT_TREE iso-ln1 qual-ln-default ""
assert_refused LINK_DEFAULT_TREE qual-ln-default BLOCKED PATH_NOT_ALLOWED 124 test_scope

# No explicit target, nothing linked: the default selection runs.
LINK_EVIDENCE=changed link_run DEFAULT_CLEAN iso-ln4 qual-ln-default-clean ""
tt_expect DEFAULT_CLEAN PASS - 0 0
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 1 test "$ISO_ROOT/iso-ln4")" ]] || pf_fail "DEFAULT_CLEAN_CALL"

# No "test" directory: left to flutter, which is run (and reports it).
LINK_EVIDENCE=changed link_run DEFAULT_NO_TEST_DIR iso-ln5 qual-ln-default-none ""
tt_expect DEFAULT_NO_TEST_DIR PASS - 0 0
[[ "$(tt_calls)" -eq 1 ]] || pf_fail "DEFAULT_NO_TEST_DIR_CALLS"

# Integration: "integration_test" is a link. Refused before the simulator is
# looked at.
link_run LINK_INTEGRATION iso-ln3 qual-ln-int "integration_test/app_test.dart" integration
assert_refused LINK_INTEGRATION qual-ln-int BLOCKED PATH_NOT_ALLOWED 124 test_targets
[[ "$(tt_simulator_lists)" -eq 0 ]] || pf_fail "LINK_INTEGRATION_SIMULATOR_LOOKED_AT"

# The checkout itself replaced by a link: refused by the engine.
ln -s "$ISO_ROOT/iso-ln4" "$ISO_ROOT/iso-lnk"
link_run LINK_CHECKOUT iso-lnk qual-ln-checkout ""
tt_expect LINK_CHECKOUT BLOCKED ISOLATION_REJECTED 126
[[ "$(tt_calls)" -eq 0 ]] || pf_fail "LINK_CHECKOUT_CALLED"
tt_assert_no_evidence LINK_CHECKOUT qual-ln-checkout

# What the links point at was neither read nor written.
[[ "$(cat "$TMP/outside/x_test.dart")" == "void main() {}" ]] || pf_fail "LINK_TARGET_TOUCHED"
[[ -z "$(ls -A "$EVID" | grep -e '^qual-ln-' | grep -v -e '^qual-ln-ok$' -e '^qual-ln-default-clean$' -e '^qual-ln-default-none$' || true)" ]] || pf_fail "LINK_EVIDENCE_WRITTEN"

unset STUB_OUT STUB_RC
pf_pass "SYMBOLIC_LINKS"

# ---------------------------------------------------------------- 14. the simulator must already be BOOTED

# With the real PREFLIGHT: it passes (the simulator exists), then TEST looks at
# the state and refuses, without any attempt to start anything.
tt_modes_reset
for udid in "$PF_UDID_SHUTDOWN" "$TT_UDID_BOOTING"; do
    tt_req_integration iso-t "qual-sim-$udid" "$udid"
    tt_run_refused "SIM_STATE_$udid" "${PF_REQ[@]}"
    assert_refused "SIM_STATE_$udid" "qual-sim-$udid" BLOCKED SIMULATOR_UNAVAILABLE 129 simulator_udid
    [[ "$(tt_value PREFLIGHT_RESULT)" == "PASS" ]] || pf_fail "SIM_STATE_${udid}_PREFLIGHT"
    [[ "$(tt_simulator_lists)" -eq 2 ]] || pf_fail "SIM_STATE_${udid}_LISTS"
done

# With a PREFLIGHT that says PASS whatever the simulator is: TEST observes the
# simulator itself, it does not rely on PREFLIGHT for the state.
export STUB_OUT="$STUB_PASS"
export STUB_RC=0

# sim_stub_run <label> <qualification id> <udid>
# SIM_EVIDENCE=changed states that the run is expected to write its evidence.
sim_stub_run() {
    local expectation="${SIM_EVIDENCE:-same}"

    tt_modes_reset
    tt_req_integration iso-ln4 "$2" "$3"
    TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" TT_EVIDENCE_EXPECT="$expectation" tt_run "$1" "$TESTOP" "${PF_REQ[@]}"
}

for udid in "$PF_UDID_SHUTDOWN" "$TT_UDID_BOOTING" "$PF_UDID_ABSENT" "$PF_UDID_UNAVAILABLE" "$PF_UDID_TVOS"; do
    sim_stub_run "SIM_STUB_$udid" "qual-simstub-$udid" "$udid"
    assert_refused "SIM_STUB_$udid" "qual-simstub-$udid" BLOCKED SIMULATOR_UNAVAILABLE 129 simulator_udid
    [[ "$(tt_simulator_lists)" -eq 1 ]] || pf_fail "SIM_STUB_${udid}_LISTS"
done

# The observation itself fails.
export SHIM_SIMCTL_MODE=listfail
tt_req_integration iso-ln4 qual-simstub-listfail
TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" TT_EVIDENCE_EXPECT=same tt_run SIM_STUB_LISTFAIL "$TESTOP" "${PF_REQ[@]}"
assert_refused SIM_STUB_LISTFAIL qual-simstub-listfail BLOCKED SIMULATOR_UNAVAILABLE 129 simulator_udid
unset SHIM_SIMCTL_MODE

# No simulator tool at all.
PF_MISSING="xcrun"
tt_req_integration iso-ln4 qual-simstub-noxcrun
TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" TT_EVIDENCE_EXPECT=same tt_run SIM_STUB_NOXCRUN "$TESTOP" "${PF_REQ[@]}"
unset PF_MISSING
assert_refused SIM_STUB_NOXCRUN qual-simstub-noxcrun BLOCKED SIMULATOR_UNAVAILABLE 129 simulator_udid

# A BOOTED simulator is accepted (the stubbed flow is not broken).
SIM_EVIDENCE=changed sim_stub_run SIM_STUB_BOOTED qual-simstub-booted "$PF_UDID_BOOTED"
tt_expect SIM_STUB_BOOTED PASS - 0 0
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 4 "test integration_test/app_test.dart -d $PF_UDID_BOOTED" "$ISO_ROOT/iso-ln4")" ]] || pf_fail "SIM_STUB_BOOTED_CALL"

# A unit_widget run does not look at the state of the simulator that it is given.
tt_modes_reset
tt_req iso-ln4 qual-simstub-unit
pf_req_set simulator_udid "$PF_UDID_SHUTDOWN"
TT_SCRIPT_UNDER_TEST="$STUB_DRIVER" tt_run SIM_STUB_UNIT "$TESTOP" "${PF_REQ[@]}"
tt_expect SIM_STUB_UNIT PASS - 0 0
[[ "$(tt_simulator_lists)" -eq 0 ]] || pf_fail "SIM_STUB_UNIT_LISTS"

unset STUB_OUT STUB_RC

# A simulator that is BOOTED and an integration run: nothing but the allowed
# observations was asked of the simulator tools (the shim refuses the rest, and
# a refused call fails the run: boot, create, erase, delete, shutdown).
tt_modes_reset
tt_req_integration iso-t qual-sim-booted "$PF_UDID_BOOTED"
tt_run SIM_BOOTED "${PF_REQ[@]}"
tt_expect SIM_BOOTED PASS - 0 0
pf_assert_tools_allowed SIM_BOOTED

pf_pass "SIMULATOR_BOOTED"

# ---------------------------------------------------------------- 15. evidence is never overwritten, never followed

tt_modes_reset

# A second run with the same qualification id is refused; the first evidence
# stays exactly as it was.
tt_req iso-t qual-pass
SUM_BEFORE="$(cd "$EVID/qual-pass" && cksum TEST.log TEST.result)"
tt_run_refused EVIDENCE_REUSE "${PF_REQ[@]}"
tt_expect EVIDENCE_REUSE BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool EVIDENCE_REUSE
[[ "$(cd "$EVID/qual-pass" && cksum TEST.log TEST.result)" == "$SUM_BEFORE" ]] || pf_fail "EVIDENCE_REUSE_OVERWRITTEN"

# Each file that could collide refuses the run: log, result, capture, also as a
# dangling link (whose target must not be created).
for name in TEST.log TEST.result TEST.log.partial; do
    id="qual-exists-${name//./-}"
    mkdir -m 700 "$EVID/$id"
    printf '%s\n' "earlier evidence" > "$EVID/$id/$name"
    tt_req iso-t "$id"
    tt_run_refused "EVIDENCE_EXISTS_$name" "${PF_REQ[@]}"
    tt_expect "EVIDENCE_EXISTS_$name" BLOCKED PATH_NOT_ALLOWED 124
    assert_no_tool "EVIDENCE_EXISTS_$name"
    [[ "$(cat "$EVID/$id/$name")" == "earlier evidence" ]] || pf_fail "EVIDENCE_EXISTS_${name}_TOUCHED"

    id="qual-dangling-${name//./-}"
    mkdir -m 700 "$EVID/$id"
    ln -s "$TMP/outside-target" "$EVID/$id/$name"
    tt_req iso-t "$id"
    tt_run_refused "EVIDENCE_DANGLING_$name" "${PF_REQ[@]}"
    tt_expect "EVIDENCE_DANGLING_$name" BLOCKED PATH_NOT_ALLOWED 124
    assert_no_tool "EVIDENCE_DANGLING_$name"
    [[ ! -e "$TMP/outside-target" ]] || pf_fail "EVIDENCE_DANGLING_${name}_FOLLOWED"
done

# The evidence of another operation of the same qualification is kept as it is:
# TEST adds its own files next to it and never touches the ANALYZE evidence.
mkdir -m 700 "$EVID/qual-both"
printf '%s\n' "analyze evidence" > "$EVID/qual-both/ANALYZE.log"
printf '%s\n' "analyze result" > "$EVID/qual-both/ANALYZE.result"
chmod 600 "$EVID/qual-both/ANALYZE.log" "$EVID/qual-both/ANALYZE.result"
tt_req iso-t qual-both
tt_run BOTH "${PF_REQ[@]}"
tt_expect BOTH PASS - 0 0
[[ "$(cat "$EVID/qual-both/ANALYZE.log")" == "analyze evidence" ]] || pf_fail "BOTH_ANALYZE_LOG_TOUCHED"
[[ "$(cat "$EVID/qual-both/ANALYZE.result")" == "analyze result" ]] || pf_fail "BOTH_ANALYZE_RESULT_TOUCHED"
[[ "$(ls -A "$EVID/qual-both" | LC_ALL=C sort | tr '\n' ' ')" == "ANALYZE.log ANALYZE.result TEST.log TEST.result " ]] || pf_fail "BOTH_ENTRIES"
tt_assert_mode BOTH_LOG "$EVID/qual-both/TEST.log" 600
tt_assert_mode BOTH_RESULT "$EVID/qual-both/TEST.result" 600

# A qualification directory that is a link, or open to others, is refused.
mkdir -m 700 "$TMP/outside-dir"
ln -s "$TMP/outside-dir" "$EVID/qual-linked-dir"
tt_req iso-t qual-linked-dir
tt_run_refused QDIR_LINK "${PF_REQ[@]}"
tt_expect QDIR_LINK BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool QDIR_LINK
[[ -z "$(ls -A "$TMP/outside-dir")" ]] || pf_fail "QDIR_LINK_FOLLOWED"

mkdir "$EVID/qual-open-dir"
chmod 777 "$EVID/qual-open-dir"
tt_req iso-t qual-open-dir
tt_run_refused QDIR_OPEN "${PF_REQ[@]}"
tt_expect QDIR_OPEN BLOCKED PATH_NOT_ALLOWED 124
assert_no_tool QDIR_OPEN
[[ -z "$(ls -A "$EVID/qual-open-dir")" ]] || pf_fail "QDIR_OPEN_WRITTEN"
chmod 700 "$EVID/qual-open-dir"

pf_pass "EVIDENCE_NEVER_OVERWRITTEN"

# ---------------------------------------------------------------- 16. sources and isolations are protected

# Whatever the outcome, the source repository (HEAD, branches, status,
# untracked files, .local) is exactly as it was, no call was made from it, and
# the isolation stays valid, clean and registered. Nothing is cleaned.
for mode in ok fail hang big; do
    tt_modes_reset
    shim_mode "$mode"
    export SHIM_TEST_LINES=3000
    tt_req iso-t "qual-preserve-$mode"
    pf_req_set timeout_seconds 3
    pf_req_set log_max_bytes 4096
    tt_run "PRESERVE_$mode" "${PF_REQ[@]}"
    iso_assert_source_untouched "PRESERVE_${mode}_SOURCE"
    [[ "$(cat "$SOURCE/.local/note.txt")" == "local-dev-state" ]] || pf_fail "PRESERVE_${mode}_LOCAL"
    [[ -z "$(git -C "$ISO_ROOT/iso-t" status --porcelain)" ]] || pf_fail "PRESERVE_${mode}_CHECKOUT"

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        case "$line" in
            *"cwd=$ISO_ROOT/iso-t "*) ;;
            *) pf_fail "PRESERVE_${mode}_CALL_$line" ;;
        esac
    done < "$TT_CALLS"
done

iso_run verify iso-t "$SOURCE" "$ISO_ROOT"
iso_expect_pass "PRESERVE_VERIFY_T"
iso_run verify iso-gate "$SOURCE" "$ISO_ROOT"
iso_expect_pass "PRESERVE_VERIFY_GATE"
[[ -f "$ISO_ROOT/.cbs-isolation/iso-t.proof" ]] || pf_fail "PRESERVE_PROOF_LOST_T"
[[ -f "$ISO_ROOT/.cbs-isolation/iso-gate.proof" ]] || pf_fail "PRESERVE_PROOF_LOST_GATE"
iso_is_registered "$ISO_ROOT/iso-t" || pf_fail "PRESERVE_UNREGISTERED_T"
iso_is_registered "$ISO_ROOT/iso-gate" || pf_fail "PRESERVE_UNREGISTERED_GATE"
[[ -d "$ISO_ROOT/iso-t/test" && -d "$ISO_ROOT/iso-gate/test" ]] || pf_fail "PRESERVE_CHECKOUT_CLEANED"

pf_pass "SOURCES_AND_ISOLATIONS_PROTECTED"

# ---------------------------------------------------------------- 17. sourcing runs nothing

tt_modes_reset
: > "$PF_LOG"
: > "$PF_GITLOG"
: > "$TT_CALLS"
pf_make_view
set +e
SOURCED_OUT="$(cd "$TMP" && env PATH="$PF_VIEW:$PF_TOOLS" "$BASH" -c 'source "$1"; declare -F cbs_flutter_qual_test >/dev/null' x "$TESTOP" 2>&1)"
SOURCED_RC=$?
set -e
[[ "$SOURCED_RC" -eq 0 && -z "$SOURCED_OUT" ]] || pf_fail "SOURCE_RUNS_$SOURCED_RC"
assert_no_tool SOURCE

pf_pass "SOURCE_ONLY"

# ---------------------------------------------------------------- 18. final state

iso_assert_source_untouched "FINAL_SOURCE"
# The source repository and the two isolations created by CBS.
[[ "$(git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ')" -eq 3 ]] || pf_fail "FINAL_WORKTREE_COUNT"

pf_pass "NO_SIDE_EFFECT"

# ---------------------------------------------------------------- 19. Bash 3.2

# Native Bash 3.2 (macOS): a PASS, an explicit selection, an integration run, a
# tool failure, a timeout and a refusal run under it when one is available.
# Otherwise NOT_RUN: this is not a claim of macOS qualification.
BASH32=""
for candidate in /bin/bash /usr/bin/bash /usr/local/bin/bash; do
    if [[ -x "$candidate" ]] && [[ "$("$candidate" -c 'printf "%s%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null)" == "32" ]]; then
        BASH32="$candidate"
        break
    fi
done

if [[ -n "$BASH32" ]]; then
    tt_modes_reset
    TT_BASH="$BASH32"
    tt_req iso-t qual-bash32-pass
    tt_run BASH32_PASS "${PF_REQ[@]}"
    tt_expect BASH32_PASS PASS - 0 0

    tt_req iso-t qual-bash32-select
    pf_req_set test_targets "test/a_test.dart,test/widget/b_test.dart"
    tt_run BASH32_SELECT "${PF_REQ[@]}"
    tt_expect BASH32_SELECT PASS - 0 0

    tt_req_integration iso-t qual-bash32-integration
    tt_run BASH32_INTEGRATION "${PF_REQ[@]}"
    tt_expect BASH32_INTEGRATION PASS - 0 0

    shim_mode fail
    tt_req iso-t qual-bash32-fail
    tt_run BASH32_FAIL "${PF_REQ[@]}"
    tt_expect BASH32_FAIL FAIL COMMAND_FAILED 130 1

    tt_modes_reset
    TT_BASH="$BASH32"
    shim_mode hang
    tt_req iso-t qual-bash32-hang
    pf_req_set timeout_seconds 3
    tt_run BASH32_TIMEOUT "${PF_REQ[@]}"
    tt_expect BASH32_TIMEOUT FAIL TIMEOUT 131
    pf_pid_gone "$(cat "$PF_HANG_PID")" 5 || pf_fail "BASH32_TIMEOUT_PROCESS_SURVIVED"

    tt_modes_reset
    TT_BASH="$BASH32"
    tt_req iso-t qual-bash32-absent
    pf_req_set test_targets "test/missing_test.dart"
    tt_run_refused BASH32_ABSENT "${PF_REQ[@]}"
    assert_refused BASH32_ABSENT qual-bash32-absent BLOCKED INPUT_INVALID 121 test_targets

    tt_modes_reset
    TT_BASH="$BASH32"
    PF_MISSING="flutter"
    tt_req iso-t qual-bash32-gate
    tt_run_refused BASH32_GATE "${PF_REQ[@]}"
    assert_not_run BASH32_GATE qual-bash32-gate BLOCKED TOOL_UNAVAILABLE

    echo "${TEST_PREFIX}_BASH32=PASS"
else
    echo "${TEST_PREFIX}_BASH32=NOT_RUN"
fi

tt_modes_reset

echo "${TEST_PREFIX}_RESULT=PASS"
