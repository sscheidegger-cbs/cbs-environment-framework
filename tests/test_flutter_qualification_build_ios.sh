#!/usr/bin/env bash

# D04b-C.2g: hermetic test of the Flutter/iOS qualification BUILD_IOS.
#
# Proportionate on purpose: the mechanisms of the common engine (execution.sh:
# supervision, timeout, redaction, log bound, evidence modes) are qualified by
# the ANALYZE and TEST suites and are not requalified here. This test covers
# the risks that BUILD_IOS adds:
#
#   1. the command is built exactly as the contract allows, and nothing else;
#   2. nothing configures a signature, implicitly or by a request parameter;
#   3. the build runs in the verified isolation, never in the source
#      repository, and writes nowhere else; nothing is cleaned afterwards;
#   4. the exact exit status of flutter is kept;
#   5. the gates (PREFLIGHT, links in the checkout, evidence) stop the run
#      before flutter is started;
#   6. the logs are bounded and redacted by the engine (wiring only).
#
# Real Git repositories and real CBS isolations in a private directory; Flutter,
# Dart, Xcode and simctl are shims generated at run time. The PATH given to the
# executor holds only those shims and links to the system tools it needs: a real
# Flutter or Xcode of the host can never be found. No real build is ever run.
#
# Nothing here qualifies a real Mac: see the BASH32 line for the one check that
# needs a native Bash 3.2.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/cbs/qualification/flutter/build_ios.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_BUILD_IOS"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$CONTRACT"

[[ -f "$BUILD" ]] || pf_fail "BUILD_IOS_OPERATION_MISSING"
bash -n "$BUILD" || pf_fail "BUILD_IOS_OPERATION_SYNTAX"

# A signing configuration of the host must never reach this test.
for name in $(compgen -e FLUTTER_XCODE_ || true); do
    unset "$name"
done

iso_fixture_init
pf_init

BI_CALLS=""
BI_BEFORE_SOURCE=""
BI_BEFORE_ISO=""
BI_BEFORE_EVID=""

# ---------------------------------------------------------------- helpers

# The flutter shim answers "--version" like the one of PREFLIGHT, records every
# "build" (argument count, arguments, working directory, locale) in BI_CALLS and
# behaves according to SHIM_BUILD_MODE:
#   ok       prints a success line, exit 0
#   fail     prints a failure line, exit 1
#   rc       exit SHIM_BUILD_RC
#   killed   the tool kills itself with SIGKILL
#   write    writes a file under ./build (the checkout) and exits 0
#   big      prints SHIM_BUILD_LINES lines, exit 0
#   secret   prints strings that look like secrets, exit 1
# Any other word given to the shim ("analyze", "pub", "test", ...) is an
# unexpected call: logged in PF_BAD, exit 99.
bi_init() {
    chmod 700 "$EVID"
    BI_CALLS="$PF_STATE/build-calls.log"
    : > "$BI_CALLS"

    {
        printf '#!/bin/sh\n'
        printf 'PF_LOG=%s\nPF_BAD=%s\nBI_CALLS=%s\nFLUTTER_REQUIRED=%s\n' \
            "$PF_LOG" "$PF_BAD" "$BI_CALLS" "$PF_FLUTTER_REQUIRED"
        cat <<'EOF'
if [ "$*" = "--version" ]; then
    echo "flutter --version" >> "$PF_LOG"
    case "${SHIM_FLUTTER_MODE:-ok}" in
        ok)
            echo "Flutter ${SHIM_FLUTTER_VERSION:-$FLUTTER_REQUIRED} • channel stable • https://github.com/flutter/flutter.git"
            echo "Framework • revision 0000000000 (1 year ago) • 2025-01-01 00:00:00 +0000"
            echo "Engine • revision 0000000000"
            echo "Tools • Dart 3.9.0 • DevTools 2.40.0"
            exit 0 ;;
    esac
    exit 98
fi
if [ "$1" = "build" ]; then
    echo "argc=$# argv=$* cwd=$(pwd -P) lc_all=${LC_ALL:-unset}" >> "$BI_CALLS"
    case "${SHIM_BUILD_MODE:-ok}" in
        ok)
            echo "Built build/ios/iphonesimulator/Runner.app"
            exit 0 ;;
        fail)
            echo "Xcode build failed"
            exit 1 ;;
        rc)
            echo "build stopped"
            exit "${SHIM_BUILD_RC:-3}" ;;
        killed)
            echo "about to be killed"
            kill -9 $$ ;;
        write)
            mkdir -p build/ios/iphonesimulator
            echo "built" > build/ios/iphonesimulator/marker
            echo "wrote build/"
            exit 0 ;;
        big)
            i=0
            while [ "$i" -lt "${SHIM_BUILD_LINES:-5000}" ]; do
                echo "info line $i ......................................................................"
                i=$((i + 1))
            done
            exit 0 ;;
        secret)
            echo "token=ghp_abcdefghijklmnopqrstuvwxyz0123456789"
            echo "Authorization: Bearer abcdef.ghijkl.mnopqr"
            echo "flutter build --dart-define=API_KEY=supersecretvalue123"
            echo "ordinary line kept"
            exit 1 ;;
    esac
    exit 98
fi
echo "flutter $*" >> "$PF_BAD"
exit 99
EOF
    } > "$PF_SHIMS/flutter"

    chmod 755 "$PF_SHIMS/flutter"
}

bi_modes_reset() {
    pf_modes_reset
    unset SHIM_BUILD_MODE SHIM_BUILD_RC SHIM_BUILD_LINES
    unset BI_ISO_CHANGES BI_ENV_ASSIGN BI_SCRIPT_UNDER_TEST BI_EVIDENCE_EXPECT BI_BASH
    : > "$BI_CALLS"
    chmod 700 "$EVID"
}

# Reference request: preflight then build_ios, on the isolation given. The
# simulator of the reference request of PREFLIGHT is given (SHUTDOWN): BUILD_IOS
# neither boots nor uses it. Arguments: ISOLATION_ID QUALIFICATION_ID
bi_req() {
    pf_req_reset "$1"
    pf_req_set qualification_id "$2"
    pf_req_set commit "$C2"
    pf_req_set actions "preflight,build_ios"
}

bi_state_before() {
    BI_BEFORE_SOURCE="$(GIT_OPTIONAL_LOCKS=0 iso_source_state; iso_tree_fingerprint "$SOURCE")"
    BI_BEFORE_ISO="$(iso_tree_fingerprint "$ISO_ROOT")"
    BI_BEFORE_EVID="$(iso_tree_fingerprint "$EVID")"
}

# Arguments: LABEL EVIDENCE (same|changed). The source repository and the
# isolation root never change by themselves (BI_ISO_CHANGES=1 states that the
# build of the shim writes in its checkout).
bi_state_after() {
    local label="$1"
    local after

    after="$(GIT_OPTIONAL_LOCKS=0 iso_source_state; iso_tree_fingerprint "$SOURCE")"
    [[ "$after" == "$BI_BEFORE_SOURCE" ]] || pf_fail "${label}_SOURCE_MUTATED"

    after="$(iso_tree_fingerprint "$ISO_ROOT")"

    if [[ "${BI_ISO_CHANGES:-0}" != "1" ]]; then
        [[ "$after" == "$BI_BEFORE_ISO" ]] || pf_fail "${label}_ISOLATION_ROOT_MUTATED"
    fi

    after="$(iso_tree_fingerprint "$EVID")"

    if [[ "${2:-same}" == "same" ]]; then
        [[ "$after" == "$BI_BEFORE_EVID" ]] || pf_fail "${label}_EVIDENCE_MUTATED"
    fi
}

# bi_run <label> <argument...>
# Runs BUILD_IOS with the hermetic PATH, from a directory that is neither the
# source nor an isolation. Sets PF_OUT, PF_ERR and PF_RC.
bi_run() {
    local label="$1"

    shift

    pf_make_view
    : > "$PF_LOG"
    : > "$PF_BAD"
    : > "$PF_GITLOG"
    : > "$BI_CALLS"

    bi_state_before

    set +e
    # shellcheck disable=SC2086
    PF_OUT="$(cd "$TMP" && env ${BI_ENV_ASSIGN:-} PATH="$PF_VIEW:$PF_TOOLS" "${BI_BASH:-$BASH}" "${BI_SCRIPT_UNDER_TEST:-$BUILD}" "$@" 2>"$PF_ERRFILE")"
    PF_RC=$?
    set -e

    PF_ERR="$(cat "$PF_ERRFILE")"

    bi_state_after "$label" "${BI_EVIDENCE_EXPECT:-changed}"

    [[ -z "$(cat "$PF_BAD")" ]] || pf_fail "${label}_UNEXPECTED_TOOL_CALL_$(head -n 1 "$PF_BAD" | tr ' ' '_')"
}

# A run that must be refused before anything is written under the evidence root.
bi_run_refused() {
    BI_EVIDENCE_EXPECT=same bi_run "$@"
}

# Value of CBS_FLUTTER_QUAL_BUILD_IOS_<suffix>.
bi_value() {
    pf_kv "CBS_FLUTTER_QUAL_BUILD_IOS_$1"
}

# bi_expect <label> <RESULT> <REASON|-> <rc> [<tool rc>|-]
# Verifies the whole structured answer: operation, result, reason, return
# codes, tool status, final RESULT line last, and a closed output language.
bi_expect() {
    local label="$1"
    local result="$2"
    local reason="$3"
    local rc="$4"
    local tool_rc="${5:--}"
    local last

    [[ "$PF_RC" -eq "$rc" ]] || pf_fail "${label}_RC_EXPECTED_${rc}_GOT_${PF_RC}"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION)" == "BUILD_IOS" ]] || pf_fail "${label}_OPERATION_$(pf_kv CBS_FLUTTER_QUAL_OPERATION)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)" == "$result" ]] || pf_fail "${label}_OPERATION_RESULT_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "$result" ]] || pf_fail "${label}_RESULT_$(pf_kv CBS_FLUTTER_QUAL_RESULT)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RC)" == "$rc" ]] || pf_fail "${label}_OPERATION_RC_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RC)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_CONTRACT_VERSION)" == "1" ]] || pf_fail "${label}_CONTRACT_VERSION"

    last="$(printf '%s\n' "$PF_OUT" | tail -n 1)"
    [[ "$last" == "CBS_FLUTTER_QUAL_RESULT=$result" ]] || pf_fail "${label}_RESULT_NOT_LAST"

    if [[ "$reason" == "-" ]]; then
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_REASON)" ]] || pf_fail "${label}_UNEXPECTED_REASON"
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" ]] || pf_fail "${label}_UNEXPECTED_OPERATION_REASON"
        [[ -z "$PF_ERR" ]] || pf_fail "${label}_STDERR_ON_PASS"
    else
        [[ "$(pf_kv CBS_FLUTTER_QUAL_REASON)" == "$reason" ]] || pf_fail "${label}_REASON_EXPECTED_${reason}_GOT_$(pf_kv CBS_FLUTTER_QUAL_REASON)"
        [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" == "$reason" ]] || pf_fail "${label}_OPERATION_REASON"
        [[ "$(cbs_flutter_qual_rc_for_reason "$reason")" == "$rc" ]] || pf_fail "${label}_REASON_RC_DISAGREE"
        [[ "$(cbs_flutter_qual_result_for_reason "$reason")" == "$result" ]] || pf_fail "${label}_REASON_CLASS_DISAGREE"
        [[ "$PF_ERR" == "CBS_FLUTTER_QUAL_ERROR=$reason" ]] || pf_fail "${label}_STDERR_NOT_THE_REASON"
    fi

    if [[ "$tool_rc" == "-" ]]; then
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" ]] || pf_fail "${label}_UNEXPECTED_TOOL_RC"
    else
        [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "$tool_rc" ]] || pf_fail "${label}_TOOL_RC_EXPECTED_${tool_rc}_GOT_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)"
    fi

    # Every stdout line belongs to the CBS_FLUTTER_QUAL_ namespace, closed set.
    if printf '%s\n' "$PF_OUT" | grep -v '^CBS_FLUTTER_QUAL_[A-Z0-9_]*=[A-Za-z0-9._+-]*$' >/dev/null; then
        pf_fail "${label}_FOREIGN_OUTPUT_LINE"
    fi

    # The path of the host is never printed.
    if printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e "$TMP" -e "$SOURCE" >/dev/null; then
        pf_fail "${label}_PATH_LEAKED"
    fi
}

# Number of "flutter build" calls recorded by the shim.
bi_calls() {
    wc -l < "$BI_CALLS" | tr -d ' '
}

# The exact line recorded by the shim for the one expected "flutter build".
# Arguments: ARGC ARGV CHECKOUT_DIRECTORY
bi_call_line() {
    printf 'argc=%s argv=%s cwd=%s lc_all=C' "$1" "$2" "$3"
}

# The one command that the contract allows.
BI_COMMAND_ARGV="build ios --simulator --no-codesign"

# Number of read-only observations of the simulators ("simctl list devices").
bi_simulator_lists() {
    grep -c '^xcrun simctl list devices$' "$PF_LOG" || true
}

# Nothing was written under the evidence root for this identifier.
bi_assert_no_evidence() {
    [[ ! -e "$EVID/$2" && ! -L "$EVID/$2" ]] || pf_fail "${1}_EVIDENCE_WRITTEN"
}

# The evidence directory of an executed run holds exactly the log and the
# result file, private. Arguments: LABEL QUALIFICATION_ID
bi_assert_evidence() {
    local label="$1"
    local dir="$EVID/$2"
    local entries

    [[ -d "$dir" && ! -L "$dir" ]] || pf_fail "${label}_EVIDENCE_DIR_MISSING"
    iso_has_mode "$dir" 700 || pf_fail "${label}_DIR_MODE_NOT_700"

    entries="$(ls -A "$dir" | LC_ALL=C sort | tr '\n' ' ')"
    [[ "$entries" == "BUILD_IOS.log BUILD_IOS.result " ]] || pf_fail "${label}_EVIDENCE_ENTRIES_$(printf '%s' "$entries" | tr ' ' '_')"

    iso_has_mode "$dir/BUILD_IOS.log" 600 || pf_fail "${label}_LOG_MODE_NOT_600"
    iso_has_mode "$dir/BUILD_IOS.result" 600 || pf_fail "${label}_RESULT_MODE_NOT_600"

    # The result file holds exactly what was printed.
    [[ "$(cat "$dir/BUILD_IOS.result")" == "$PF_OUT" ]] || pf_fail "${label}_RESULT_FILE_DIFFERS"
}

bi_log() {
    cat "$EVID/$1/BUILD_IOS.log"
}

bi_log_bytes() {
    wc -c < "$EVID/$1/BUILD_IOS.log" | tr -d ' '
}

# No tool was started at all (not even a probe): a refusal of the request.
bi_assert_no_tool() {
    [[ -z "$(cat "$PF_LOG")" ]] || pf_fail "${1}_TOOL_CALLED_$(head -n 1 "$PF_LOG" | tr ' ' '_')"
    [[ "$(bi_calls)" -eq 0 ]] || pf_fail "${1}_BUILD_CALLED"
    [[ "$(pf_git_calls)" -eq 0 ]] || pf_fail "${1}_GIT_CALLED"
}

# A refusal before PREFLIGHT: nothing executed, nothing written.
# Arguments: LABEL QUALIFICATION_ID RESULT REASON RC REJECTED_KEY
bi_assert_refused() {
    bi_expect "$1" "$3" "$4" "$5"
    bi_assert_no_tool "$1"
    [[ -z "$(bi_value COMMAND)" ]] || pf_fail "${1}_COMMAND_REPORTED"
    [[ "$(bi_value EVIDENCE)" == "NOT_WRITTEN" ]] || pf_fail "${1}_EVIDENCE_FACT"
    [[ "$(bi_value REJECTED_KEY)" == "$6" ]] || pf_fail "${1}_REJECTED_KEY_$(bi_value REJECTED_KEY)"
    bi_assert_no_evidence "$1" "$2"
}

# PREFLIGHT did not pass: BUILD_IOS is NOT_RUN, nothing executed, nothing written.
# Arguments: LABEL QUALIFICATION_ID PREFLIGHT_RESULT PREFLIGHT_REASON
bi_assert_not_run() {
    bi_expect "$1" NOT_RUN PREFLIGHT_NOT_PASSED 136
    [[ "$(bi_value PREFLIGHT_RESULT)" == "$3" ]] || pf_fail "${1}_PREFLIGHT_RESULT_$(bi_value PREFLIGHT_RESULT)"
    [[ "$(bi_value PREFLIGHT_REASON)" == "$4" ]] || pf_fail "${1}_PREFLIGHT_REASON_$(bi_value PREFLIGHT_REASON)"
    [[ "$(bi_calls)" -eq 0 ]] || pf_fail "${1}_BUILD_CALLED"
    [[ -z "$(bi_value COMMAND)" ]] || pf_fail "${1}_COMMAND_REPORTED"
    [[ "$(bi_value EVIDENCE)" == "NOT_WRITTEN" ]] || pf_fail "${1}_EVIDENCE_FACT"
    bi_assert_no_evidence "$1" "$2"
}

bi_init

# ---------------------------------------------------------------- 0. structure of the operation file

# What the operation file must never contain (outside comments): another
# tool than flutter, a deletion, a network or publication word, an archive, a
# build mode, an export option, a signing option other than the one constant.
FORBIDDEN_WORDS='(^|[^A-Za-z0-9_-])(eval|xcrun|xcodebuild|simctl|git|rm|rmdir|mv|cp|ln|mkdir|touch|chmod|kill|sudo|pod|pub|dart|curl|wget|ssh|scp|open|archive|ipa|publish|upload|distribute|testflight|altool|notarytool)([^A-Za-z0-9_-]|$)'
FORBIDDEN_FLAGS='--(release|debug|profile|codesign|export|obfuscate|dart-define|flavor|target|no-pub|build-name|build-number|verbose)'

if pf_code_matches "$BUILD" "$FORBIDDEN_WORDS"; then
    pf_fail "STRUCTURE_FORBIDDEN_WORD"
fi

if pf_code_matches "$BUILD" "$FORBIDDEN_FLAGS"; then
    pf_fail "STRUCTURE_FORBIDDEN_FLAG"
fi

# One execution, one source (the engine), no deletion of any kind.
[[ "$(grep -v '^[[:space:]]*#' "$BUILD" | grep -c '_cbs_flutter_qual_ex_execute' || true)" -eq 1 ]] || pf_fail "STRUCTURE_EXECUTE_COUNT"
[[ "$(grep -v '^[[:space:]]*#' "$BUILD" | grep -c '^source ' || true)" -eq 1 ]] || pf_fail "STRUCTURE_SOURCE_COUNT"

# The four words of the command are the four constants of the file.
[[ "$(grep -c '^readonly CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_BUILD="build"$' "$BUILD" || true)" -eq 1 ]] || pf_fail "STRUCTURE_ARGUMENT_BUILD"
[[ "$(grep -c '^readonly CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_PLATFORM="ios"$' "$BUILD" || true)" -eq 1 ]] || pf_fail "STRUCTURE_ARGUMENT_PLATFORM"
[[ "$(grep -c '^readonly CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_SIMULATOR="--simulator"$' "$BUILD" || true)" -eq 1 ]] || pf_fail "STRUCTURE_ARGUMENT_SIMULATOR"
[[ "$(grep -c '^readonly CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_UNSIGNED="--no-codesign"$' "$BUILD" || true)" -eq 1 ]] || pf_fail "STRUCTURE_ARGUMENT_UNSIGNED"

# The contract itself is unchanged by this step: BUILD_IOS is a mutating
# operation of the contract and takes no parameter of its own.
cbs_flutter_qual_operation_is_mutating "$CBS_FLUTTER_QUAL_OP_BUILD_IOS" || pf_fail "CONTRACT_NOT_MUTATING"
[[ "$(cbs_flutter_qual_action_for_operation BUILD_IOS)" == "build_ios" ]] || pf_fail "CONTRACT_ACTION"

pf_pass "STRUCTURE"

# ---------------------------------------------------------------- 1. PASS: the command, in the isolation

bi_modes_reset
pf_new_isolation iso-b "$C2"
pf_new_isolation iso-w "$C2"
iso_snapshot_source
ISO_B_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/iso-b")"

bi_req iso-b qual-pass
bi_run PASS "${PF_REQ[@]}"
bi_expect PASS PASS - 0 0

# Exactly "flutter build ios --simulator --no-codesign": four arguments, run
# from the isolated checkout, never from the source repository nor from the
# directory of the caller, with the C locale. Nothing else is started.
[[ "$(bi_calls)" -eq 1 ]] || pf_fail "PASS_BUILD_CALLS_$(bi_calls)"
[[ "$(cat "$BI_CALLS")" == "$(bi_call_line 4 "$BI_COMMAND_ARGV" "$ISO_ROOT/iso-b")" ]] || pf_fail "PASS_CALL_$(cat "$BI_CALLS")"

# PREFLIGHT ran first, on the same request: its seven probes, and no more. The
# simulator was only observed (read-only), never booted, created or erased
# (any other call of the shims fails the run).
[[ "$(grep -c '^flutter --version$' "$PF_LOG")" -eq 1 ]] || pf_fail "PASS_PREFLIGHT_NOT_RUN"
[[ "$(pf_tool_calls)" -eq 7 ]] || pf_fail "PASS_PREFLIGHT_PROBES_$(pf_tool_calls)"
[[ "$(bi_simulator_lists)" -eq 1 ]] || pf_fail "PASS_SIMULATOR_LISTS_$(bi_simulator_lists)"
pf_assert_tools_allowed PASS
pf_assert_git_readonly PASS

[[ "$(bi_value PREFLIGHT_RESULT)" == "PASS" ]] || pf_fail "PASS_PREFLIGHT_RESULT"
[[ -z "$(bi_value PREFLIGHT_REASON)" ]] || pf_fail "PASS_PREFLIGHT_REASON"
[[ "$(bi_value QUALIFICATION_ID)" == "qual-pass" ]] || pf_fail "PASS_QUALIFICATION_ID"
[[ "$(bi_value COMMIT_OBSERVED)" == "$C2" ]] || pf_fail "PASS_COMMIT"
[[ "$(bi_value FLUTTER_VERSION)" == "$PF_FLUTTER_REQUIRED" ]] || pf_fail "PASS_FLUTTER_VERSION"
[[ "$(bi_value COMMAND)" == "flutter_build_ios" ]] || pf_fail "PASS_COMMAND"
[[ "$(bi_value LOG_TRUNCATED)" == "NO" ]] || pf_fail "PASS_LOG_TRUNCATED"
[[ "$(bi_value EVIDENCE)" == "WRITTEN" ]] || pf_fail "PASS_EVIDENCE"
[[ -z "$(bi_value REJECTED_KEY)" ]] || pf_fail "PASS_REJECTED_KEY"
[[ "$(bi_value DURATION_SECONDS)" =~ ^[0-9]+$ ]] || pf_fail "PASS_DURATION"

# Evidence: BUILD_IOS.log and BUILD_IOS.result, private, complete.
bi_assert_evidence PASS qual-pass
[[ "$(bi_log qual-pass)" == "Built build/ios/iphonesimulator/Runner.app" ]] || pf_fail "PASS_LOG_CONTENT"
[[ "$(bi_value LOG_BYTES)" == "$(bi_log_bytes qual-pass)" ]] || pf_fail "PASS_LOG_BYTES"

# The checkout is as created (this shim writes nothing), the source untouched,
# the isolation still verified by the manager.
[[ -z "$(git -C "$ISO_ROOT/iso-b" status --porcelain)" ]] || pf_fail "PASS_CHECKOUT_DIRTIED"
iso_assert_source_untouched "PASS_SOURCE"
iso_run verify iso-b "$SOURCE" "$ISO_ROOT"
iso_expect_pass "PASS_VERIFY"

# The structured answer is stable (only the qualification id differs).
FIRST_OUT="$(printf '%s\n' "$PF_OUT" | grep -v -e QUALIFICATION_ID -e DURATION_SECONDS)"
bi_req iso-b qual-pass-2
bi_run PASS_AGAIN "${PF_REQ[@]}"
bi_expect PASS_AGAIN PASS - 0 0
SECOND_OUT="$(printf '%s\n' "$PF_OUT" | grep -v -e QUALIFICATION_ID -e DURATION_SECONDS)"
[[ "$SECOND_OUT" == "$FIRST_OUT" ]] || pf_fail "PASS_NOT_DETERMINISTIC"

# Without a simulator in the request, the same command: no observation of
# simulators at all.
bi_req iso-b qual-pass-nosim
pf_req_unset simulator_udid
pf_req_unset simulator_policy
bi_run PASS_NO_SIMULATOR "${PF_REQ[@]}"
bi_expect PASS_NO_SIMULATOR PASS - 0 0
[[ "$(bi_simulator_lists)" -eq 0 ]] || pf_fail "PASS_NO_SIMULATOR_LISTS"
[[ "$(cat "$BI_CALLS")" == "$(bi_call_line 4 "$BI_COMMAND_ARGV" "$ISO_ROOT/iso-b")" ]] || pf_fail "PASS_NO_SIMULATOR_CALL"

# The same run with an unrelated variable of the environment is not refused.
bi_req iso-b qual-pass-env
BI_ENV_ASSIGN="CBS_BUILD_IOS_UNRELATED=1" bi_run PASS_ENV "${PF_REQ[@]}"
bi_expect PASS_ENV PASS - 0 0

pf_pass "BUILD_COMMAND"

# ---------------------------------------------------------------- 2. no implicit signature

# a. The exact command above has no "--codesign", no export option, no mode.
#    b. A signing configuration of the environment (an Xcode build setting that
#    flutter would take from FLUTTER_XCODE_*) refuses the run before anything
#    is started or written, and neither the name nor the value is printed.
for assignment in \
    "FLUTTER_XCODE_DEVELOPMENT_TEAM=ABCDE12345" \
    "FLUTTER_XCODE_CODE_SIGN_IDENTITY=Example-Identity"; do
    bi_modes_reset
    bi_req iso-b qual-env-refused
    BI_ENV_ASSIGN="$assignment" bi_run_refused ENV_REFUSED "${PF_REQ[@]}"
    bi_assert_refused ENV_REFUSED qual-env-refused BLOCKED ARGUMENT_REFUSED 123 ""

    if printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e FLUTTER_XCODE -e ABCDE12345 -e Example-Identity >/dev/null; then
        pf_fail "ENV_REFUSED_LEAKED"
    fi
done

# c. No parameter can add a build configuration, a signature or a define: the
#    contract refuses them, and flutter is never started.
check_parameter() {
    local label="$1"
    local entry="$2"
    local reason="$3"
    local rc="$4"
    local key="$5"

    bi_modes_reset
    bi_req iso-b "qual-param-$label"
    PF_REQ[${#PF_REQ[@]}]="$entry"
    bi_run_refused "PARAM_$label" "${PF_REQ[@]}"
    bi_assert_refused "PARAM_$label" "qual-param-$label" BLOCKED "$reason" "$rc" "$key"
}

check_parameter MODE "build_mode=release" ARGUMENT_REFUSED 123 build_mode
check_parameter SIGN "codesign=yes" ARGUMENT_REFUSED 123 codesign
check_parameter DEFINE "dart_define=A=B" SECRET_REFUSED 125 dart_define
check_parameter FLAG "--release" ARGUMENT_REFUSED 123 ""

# d. The action is the one of the contract, after "preflight".
bi_modes_reset
bi_req iso-b qual-not-selected
pf_req_set actions "preflight,analyze"
bi_run_refused NOT_SELECTED "${PF_REQ[@]}"
bi_assert_refused NOT_SELECTED qual-not-selected BLOCKED ACTION_NOT_ALLOWED 122 actions

bi_req iso-b qual-no-preflight
pf_req_set actions "build_ios"
bi_run_refused NO_PREFLIGHT "${PF_REQ[@]}"
bi_assert_refused NO_PREFLIGHT qual-no-preflight BLOCKED INPUT_INVALID 121 actions

pf_pass "NO_IMPLICIT_SIGNATURE"

# ---------------------------------------------------------------- 3. the exit status of flutter is kept

bi_modes_reset
export SHIM_BUILD_MODE=fail
bi_req iso-b qual-fail
bi_run FAILURE "${PF_REQ[@]}"
bi_expect FAILURE FAIL COMMAND_FAILED 130 1
bi_assert_evidence FAILURE qual-fail
[[ "$(bi_log qual-fail)" == "Xcode build failed" ]] || pf_fail "FAILURE_LOG"
[[ "$(bi_calls)" -eq 1 ]] || pf_fail "FAILURE_CALLS"
[[ "$(bi_value EVIDENCE)" == "WRITTEN" ]] || pf_fail "FAILURE_EVIDENCE"

for status in 2 64 126 255; do
    bi_modes_reset
    export SHIM_BUILD_MODE=rc
    export SHIM_BUILD_RC="$status"
    bi_req iso-b "qual-rc-$status"
    bi_run "RC_$status" "${PF_REQ[@]}"
    # The tool status is reported as is; the contract code never replaces it.
    bi_expect "RC_$status" FAIL COMMAND_FAILED 130 "$status"
    bi_assert_evidence "RC_$status" "qual-rc-$status"
    [[ "$(bi_calls)" -eq 1 ]] || pf_fail "RC_${status}_CALLS"
done

# A tool killed by a signal: the status is the shell's, reported exactly.
bi_modes_reset
export SHIM_BUILD_MODE=killed
bi_req iso-b qual-killed
bi_run KILLED "${PF_REQ[@]}"
bi_expect KILLED FAIL COMMAND_FAILED 130 137
[[ "$(bi_log qual-killed)" == "about to be killed" ]] || pf_fail "KILLED_LOG"

pf_pass "TOOL_STATUS"

# ---------------------------------------------------------------- 4. in the isolation, nothing cleaned

# The build of the shim writes in its working directory: it must land in the
# checkout of the isolation, not in the source repository and not in the
# directory of the caller. The other isolation is not touched at all.
bi_modes_reset
export SHIM_BUILD_MODE=write
bi_req iso-w qual-write
BI_ISO_CHANGES=1 bi_run WRITE "${PF_REQ[@]}"
bi_expect WRITE PASS - 0 0
[[ "$(cat "$BI_CALLS")" == "$(bi_call_line 4 "$BI_COMMAND_ARGV" "$ISO_ROOT/iso-w")" ]] || pf_fail "WRITE_CALL"
[[ "$(cat "$ISO_ROOT/iso-w/build/ios/iphonesimulator/marker")" == "built" ]] || pf_fail "WRITE_NOT_IN_ISOLATION"
[[ ! -e "$SOURCE/build" ]] || pf_fail "WRITE_IN_SOURCE"
[[ ! -e "$TMP/build" ]] || pf_fail "WRITE_IN_CALLER_DIRECTORY"
iso_assert_source_untouched "WRITE_SOURCE"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/iso-b")" == "$ISO_B_BEFORE" ]] || pf_fail "WRITE_OTHER_ISOLATION_TOUCHED"
bi_assert_evidence WRITE qual-write

# Nothing is cleaned afterwards: the build output stays, and the dirty checkout
# is refused by the next PREFLIGHT (a new isolation is needed).
bi_modes_reset
bi_req iso-w qual-write-again
bi_run_refused WRITE_AGAIN "${PF_REQ[@]}"
bi_assert_not_run WRITE_AGAIN qual-write-again BLOCKED ISOLATION_REJECTED
[[ "$(cat "$ISO_ROOT/iso-w/build/ios/iphonesimulator/marker")" == "built" ]] || pf_fail "WRITE_CLEANED"

pf_pass "ISOLATION"

# ---------------------------------------------------------------- 5. the gates stop the run before flutter

# PREFLIGHT must be PASS: another version of flutter, an isolation unknown to
# CBS. Nothing is executed, nothing is written.
bi_modes_reset
export SHIM_FLUTTER_VERSION="0.0.1"
bi_req iso-b qual-gate-version
bi_run_refused GATE_VERSION "${PF_REQ[@]}"
bi_assert_not_run GATE_VERSION qual-gate-version BLOCKED TOOLCHAIN_INCOMPATIBLE
unset SHIM_FLUTTER_VERSION

bi_req iso-unknown qual-gate-unknown
bi_run_refused GATE_UNKNOWN "${PF_REQ[@]}"
bi_assert_not_run GATE_UNKNOWN qual-gate-unknown BLOCKED ISOLATION_REJECTED

# Flutter that vanished after PREFLIGHT: the tool is looked up again. PREFLIGHT
# is replaced by the coherent answer of a PASS, as the engine reads it.
cat > "$TMP/stub-driver.sh" <<'EOF'
set -u
source "$1"
shift
cbs_flutter_qual_preflight() {
    printf '%s\n' "$STUB_OUT"
    return 0
}
cbs_flutter_qual_build_ios "$@"
exit $?
EOF
STUB_DRIVER="$TMP/stub-driver.sh"

export STUB_OUT="CBS_FLUTTER_QUAL_PREFLIGHT_COMMIT_OBSERVED=$C2
CBS_FLUTTER_QUAL_PREFLIGHT_FLUTTER_VERSION=$PF_FLUTTER_REQUIRED
CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT
CBS_FLUTTER_QUAL_OPERATION_RESULT=PASS
CBS_FLUTTER_QUAL_OPERATION_RC=0
CBS_FLUTTER_QUAL_CONTRACT_VERSION=1
CBS_FLUTTER_QUAL_RESULT=PASS"

bi_modes_reset
bi_req iso-b qual-vanished
PF_MISSING="flutter"
BI_SCRIPT_UNDER_TEST="$STUB_DRIVER" bi_run_refused VANISHED "$BUILD" "${PF_REQ[@]}"
unset PF_MISSING
bi_expect VANISHED BLOCKED TOOL_UNAVAILABLE 127
[[ "$(bi_calls)" -eq 0 ]] || pf_fail "VANISHED_CALLED"
bi_assert_no_evidence VANISHED qual-vanished

# Links in the checkout: the build writes in "build", ".dart_tool", "ios" and
# "ios/Flutter", and would write through a link. These checkouts are plain
# directories of the isolation root (the isolation manager is not the subject
# here, the guard is); PREFLIGHT is the stub above.
mkdir -p "$TMP/outside-build"
mkdir -p "$ISO_ROOT/iso-lk1" "$ISO_ROOT/iso-lk2/ios" "$ISO_ROOT/iso-lk3" "$ISO_ROOT/iso-lk4" "$ISO_ROOT/iso-lk5/ios/Flutter"
ln -s "$TMP/outside-build" "$ISO_ROOT/iso-lk1/build"
ln -s "$TMP/outside-build" "$ISO_ROOT/iso-lk2/ios/Flutter"
ln -s "$TMP/outside-build" "$ISO_ROOT/iso-lk3/.dart_tool"
ln -s "$TMP/outside-build" "$ISO_ROOT/iso-lk4/ios"

for case_id in lk1 lk2 lk3 lk4; do
    bi_modes_reset
    bi_req "iso-$case_id" "qual-link-$case_id"
    BI_SCRIPT_UNDER_TEST="$STUB_DRIVER" bi_run_refused "LINK_$case_id" "$BUILD" "${PF_REQ[@]}"
    bi_expect "LINK_$case_id" BLOCKED PATH_NOT_ALLOWED 124
    [[ "$(bi_calls)" -eq 0 ]] || pf_fail "LINK_${case_id}_CALLED"
    [[ -z "$(bi_value COMMAND)" ]] || pf_fail "LINK_${case_id}_COMMAND_REPORTED"
    [[ "$(bi_value EVIDENCE)" == "NOT_WRITTEN" ]] || pf_fail "LINK_${case_id}_EVIDENCE_FACT"
    [[ "$(bi_value REJECTED_KEY)" == "isolation_id" ]] || pf_fail "LINK_${case_id}_REJECTED_KEY"
    bi_assert_no_evidence "LINK_$case_id" "qual-link-$case_id"
done

# What the links point at was neither read nor written.
[[ -z "$(ls -A "$TMP/outside-build")" ]] || pf_fail "LINK_TARGET_WRITTEN"

# Reference: the same stubbed flow on a checkout without link runs the command.
bi_modes_reset
bi_req iso-lk5 qual-link-clean
BI_SCRIPT_UNDER_TEST="$STUB_DRIVER" bi_run LINK_CLEAN "$BUILD" "${PF_REQ[@]}"
bi_expect LINK_CLEAN PASS - 0 0
[[ "$(cat "$BI_CALLS")" == "$(bi_call_line 4 "$BI_COMMAND_ARGV" "$ISO_ROOT/iso-lk5")" ]] || pf_fail "LINK_CLEAN_CALL"
unset STUB_OUT

pf_pass "GATES"

# ---------------------------------------------------------------- 6. evidence: never overwritten, bounded, redacted

bi_modes_reset

# A second run with the same qualification id is refused; the first evidence
# stays exactly as it was.
bi_req iso-b qual-pass
SUM_BEFORE="$(cd "$EVID/qual-pass" && cksum BUILD_IOS.log BUILD_IOS.result)"
bi_run_refused EVIDENCE_REUSE "${PF_REQ[@]}"
bi_expect EVIDENCE_REUSE BLOCKED PATH_NOT_ALLOWED 124
bi_assert_no_tool EVIDENCE_REUSE
[[ "$(cd "$EVID/qual-pass" && cksum BUILD_IOS.log BUILD_IOS.result)" == "$SUM_BEFORE" ]] || pf_fail "EVIDENCE_REUSE_OVERWRITTEN"

# An evidence file of the operation that already exists refuses the run, and
# stays as it was.
for name in BUILD_IOS.log BUILD_IOS.result; do
    id="qual-exists-${name//./-}"
    mkdir -m 700 "$EVID/$id"
    printf '%s\n' "earlier evidence" > "$EVID/$id/$name"
    bi_req iso-b "$id"
    bi_run_refused "EVIDENCE_EXISTS_$name" "${PF_REQ[@]}"
    bi_expect "EVIDENCE_EXISTS_$name" BLOCKED PATH_NOT_ALLOWED 124
    bi_assert_no_tool "EVIDENCE_EXISTS_$name"
    [[ "$(cat "$EVID/$id/$name")" == "earlier evidence" ]] || pf_fail "EVIDENCE_EXISTS_${name}_TOUCHED"
done

# The evidence of another operation of the same qualification is kept as it is:
# BUILD_IOS adds its own files next to it.
mkdir -m 700 "$EVID/qual-both"
printf '%s\n' "analyze evidence" > "$EVID/qual-both/ANALYZE.log"
printf '%s\n' "analyze result" > "$EVID/qual-both/ANALYZE.result"
chmod 600 "$EVID/qual-both/ANALYZE.log" "$EVID/qual-both/ANALYZE.result"
bi_req iso-b qual-both
bi_run BOTH "${PF_REQ[@]}"
bi_expect BOTH PASS - 0 0
[[ "$(cat "$EVID/qual-both/ANALYZE.log")" == "analyze evidence" ]] || pf_fail "BOTH_ANALYZE_LOG_TOUCHED"
[[ "$(cat "$EVID/qual-both/ANALYZE.result")" == "analyze result" ]] || pf_fail "BOTH_ANALYZE_RESULT_TOUCHED"
[[ "$(ls -A "$EVID/qual-both" | LC_ALL=C sort | tr '\n' ' ')" == "ANALYZE.log ANALYZE.result BUILD_IOS.log BUILD_IOS.result " ]] || pf_fail "BOTH_ENTRIES"
iso_has_mode "$EVID/qual-both/BUILD_IOS.log" 600 || pf_fail "BOTH_LOG_MODE"
iso_has_mode "$EVID/qual-both/BUILD_IOS.result" 600 || pf_fail "BOTH_RESULT_MODE"

# The log is bounded (wiring of the engine: the limit is exact).
bi_modes_reset
export SHIM_BUILD_MODE=big
export SHIM_BUILD_LINES=3000
bi_req iso-b qual-big
pf_req_set log_max_bytes 2048
bi_run LIMIT "${PF_REQ[@]}"
bi_expect LIMIT FAIL LOG_LIMIT_EXCEEDED 133
bi_assert_evidence LIMIT qual-big
[[ "$(bi_log_bytes qual-big)" -eq 2048 ]] || pf_fail "LIMIT_BYTES_$(bi_log_bytes qual-big)"
[[ "$(bi_value LOG_TRUNCATED)" == "YES" ]] || pf_fail "LIMIT_TRUNCATED_FACT"

# The log is redacted before it is written, and the build line that carries a
# define is not kept (wiring of the engine).
bi_modes_reset
export SHIM_BUILD_MODE=secret
bi_req iso-b qual-secret
bi_run SECRET "${PF_REQ[@]}"
bi_expect SECRET FAIL COMMAND_FAILED 130 1
bi_assert_evidence SECRET qual-secret

LOG="$(bi_log qual-secret)"
for leaked in ghp_abcdefghijklmnopqrstuvwxyz0123456789 abcdef.ghijkl.mnopqr supersecretvalue123; do
    case "$LOG" in
        *"$leaked"*) pf_fail "SECRET_LOG_LEAK_$leaked" ;;
    esac
    printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e "$leaked" >/dev/null && pf_fail "SECRET_ANSWER_LEAK_$leaked"
done

[[ "$LOG" == *"[REDACTED]"* ]] || pf_fail "SECRET_NOT_REDACTED"
[[ "$LOG" == *"ordinary line kept"* ]] || pf_fail "SECRET_OVERREDACTED"
[[ -z "$(grep -rl -e supersecretvalue123 "$EVID" 2>/dev/null || true)" ]] || pf_fail "SECRET_ON_DISK"

pf_pass "EVIDENCE"

# ---------------------------------------------------------------- 7. sourcing runs nothing

bi_modes_reset
: > "$PF_LOG"
: > "$PF_GITLOG"
: > "$BI_CALLS"
pf_make_view
set +e
SOURCED_OUT="$(cd "$TMP" && env PATH="$PF_VIEW:$PF_TOOLS" "$BASH" -c 'source "$1"; declare -F cbs_flutter_qual_build_ios >/dev/null' x "$BUILD" 2>&1)"
SOURCED_RC=$?
set -e
[[ "$SOURCED_RC" -eq 0 && -z "$SOURCED_OUT" ]] || pf_fail "SOURCE_RUNS_$SOURCED_RC"
bi_assert_no_tool SOURCE

pf_pass "SOURCE_ONLY"

# ---------------------------------------------------------------- 8. final state

iso_assert_source_untouched "FINAL_SOURCE"
# The source repository and the two isolations created by CBS.
[[ "$(git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ')" -eq 3 ]] || pf_fail "FINAL_WORKTREE_COUNT"

pf_pass "NO_SIDE_EFFECT"

# ---------------------------------------------------------------- 9. Bash 3.2

# Native Bash 3.2 (macOS): a PASS, a tool failure and a refusal run under it
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
    bi_modes_reset
    BI_BASH="$BASH32"
    bi_req iso-b qual-bash32-pass
    bi_run BASH32_PASS "${PF_REQ[@]}"
    bi_expect BASH32_PASS PASS - 0 0
    [[ "$(cat "$BI_CALLS")" == "$(bi_call_line 4 "$BI_COMMAND_ARGV" "$ISO_ROOT/iso-b")" ]] || pf_fail "BASH32_CALL"

    export SHIM_BUILD_MODE=rc
    export SHIM_BUILD_RC=2
    bi_req iso-b qual-bash32-rc
    bi_run BASH32_RC "${PF_REQ[@]}"
    bi_expect BASH32_RC FAIL COMMAND_FAILED 130 2

    bi_modes_reset
    BI_BASH="$BASH32"
    bi_req iso-b qual-bash32-env
    BI_ENV_ASSIGN="FLUTTER_XCODE_DEVELOPMENT_TEAM=ABCDE12345" bi_run_refused BASH32_ENV "${PF_REQ[@]}"
    bi_assert_refused BASH32_ENV qual-bash32-env BLOCKED ARGUMENT_REFUSED 123 ""

    echo "${TEST_PREFIX}_BASH32=PASS"
else
    echo "${TEST_PREFIX}_BASH32=NOT_RUN"
fi

bi_modes_reset

echo "${TEST_PREFIX}_RESULT=PASS"
