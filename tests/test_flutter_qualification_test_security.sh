#!/usr/bin/env bash

# D04b-C.2f: security test of the Flutter/iOS qualification TEST.
#
# Proves that nothing but "flutter test", with the files of the request and, for
# an integration run, the simulator of the request, can ever be run; that every
# value of the request is data; that the environment, the PATH and the links are
# not trusted; that the source repository and the existing isolations are never
# a place to run, to write or to clean; that no simulator is ever started,
# created or deleted; that secrets do not reach the evidence; and (static scan)
# that the operation file holds no other way to run, write or delete.
#
# Same hermetic setup as test_flutter_qualification_test.sh: real Git
# repositories and CBS isolations, shims for Flutter, Dart, Xcode and simctl.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTOP="$ROOT/cbs/qualification/flutter/test.sh"
EXECUTION="$ROOT/cbs/qualification/flutter/execution.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_TEST_SECURITY"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/test_lib.sh"
source "$CONTRACT"

[[ -f "$TESTOP" ]] || pf_fail "TEST_OPERATION_MISSING"
bash -n "$TESTOP" || pf_fail "TEST_OPERATION_SYNTAX"
[[ -f "$EXECUTION" ]] || pf_fail "EXECUTION_MISSING"
bash -n "$EXECUTION" || pf_fail "EXECUTION_SYNTAX"

iso_fixture_init
pf_init
tt_init
tt_make_commit

# A second commit with files whose names look like options or are unusual, and
# a file that exists in the working tree of the source repository only.
printf '%s\n' "void main() {}" > "$SOURCE/test/--machine_test.dart"
printf '%s\n' "void main() {}" > "$SOURCE/test/name.with.dots-and_under_test.dart"
git -C "$SOURCE" add test
git -C "$SOURCE" commit -qm "unusual file names"
TT_COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
printf '%s\n' "void main() {}" > "$SOURCE/test/only_in_source_test.dart"

PWNED="$TMP/pwned"

shim_mode() {
    export SHIM_TEST_MODE="$1"
}

# Nothing started, nothing written, nothing created by an injected value.
assert_inert() {
    [[ ! -e "$PWNED" ]] || pf_fail "${1}_INJECTION_EXECUTED"
    [[ -z "$(cat "$PF_LOG")" ]] || pf_fail "${1}_TOOL_CALLED_$(head -n 1 "$PF_LOG" | tr ' ' '_')"
    [[ "$(tt_calls)" -eq 0 ]] || pf_fail "${1}_TEST_CALLED"
}

assert_inert_after_preflight() {
    [[ ! -e "$PWNED" ]] || pf_fail "${1}_INJECTION_EXECUTED"
    [[ "$(tt_calls)" -eq 0 ]] || pf_fail "${1}_TEST_CALLED"
}

# Every recorded "flutter test" starts with the word "test", then only words of
# the form of a test file or "-d <simulator>", from the isolated checkout.
assert_calls_fixed() {
    local label="$1"
    local line
    local argv
    local word

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" == "argc="*" argv=test"*" cwd=$ISO_ROOT/"* ]] || pf_fail "${label}_CALL_$line"
        case "$line" in
            *"cwd=$SOURCE"*) pf_fail "${label}_RAN_IN_SOURCE" ;;
        esac

        argv="${line#* argv=}"
        argv="${argv%% cwd=*}"

        set -f
        for word in $argv; do
            case "$word" in
                test) ;;
                test/*_test.dart|integration_test/*_test.dart) ;;
                -d) ;;
                ????????-????-????-????-????????????) ;;
                *) set +f; pf_fail "${label}_UNEXPECTED_WORD_$word" ;;
            esac
        done
        set +f
    done < "$TT_CALLS"
}

tt_modes_reset
pf_new_isolation iso-sec "$TT_COMMIT"
iso_snapshot_source

# Reference: a plain PASS, to be sure that the refusals below are not caused by
# a broken fixture.
tt_req iso-sec qual-sec-reference
tt_run REFERENCE "${PF_REQ[@]}"
tt_expect REFERENCE PASS - 0 0
assert_calls_fixed REFERENCE

# ---------------------------------------------------------------- 1. injection: every value is data

INJECTIONS=(
    '$(touch '"$PWNED"')'
    '`touch '"$PWNED"'`'
    ';touch '"$PWNED"
    '&& touch '"$PWNED"
    '| touch '"$PWNED"
    '> '"$PWNED"
    "'; touch $PWNED; '"
    '"; touch '"$PWNED"'; "'
    '${IFS}touch${IFS}'"$PWNED"
    '../../../../etc/passwd'
    '-rf'
)

# Every key of the request takes a hostile value in turn.
for key in contract_version qualification_id isolation_id source_repository expected_origin commit isolation_root evidence_root target actions timeout_seconds log_max_bytes evidence_retention cleanup_policy test_scope test_targets simulator_udid simulator_policy; do
    for value in "${INJECTIONS[@]}"; do
        tt_req iso-sec qual-sec-inject
        pf_req_set "$key" "$value"
        tt_run_refused "INJECT_${key}" "${PF_REQ[@]}"
        [[ "$PF_RC" -ge 120 && "$PF_RC" -le 125 ]] || pf_fail "INJECT_${key}_RC_${PF_RC}"
        [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "BLOCKED" ]] || pf_fail "INJECT_${key}_NOT_BLOCKED"
        assert_inert "INJECT_${key}"
        # The hostile value is never echoed.
        printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'touch' -e '/etc/passwd' >/dev/null && pf_fail "INJECT_${key}_ECHOED"
    done
done

# The same values as a test file of an integration run, and as the simulator.
for value in "${INJECTIONS[@]}"; do
    tt_req_integration iso-sec qual-sec-inject
    pf_req_set test_targets "$value"
    tt_run_refused "INJECT_INTEGRATION_TARGET" "${PF_REQ[@]}"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "BLOCKED" ]] || pf_fail "INJECT_INTEGRATION_TARGET_NOT_BLOCKED"
    assert_inert "INJECT_INTEGRATION_TARGET"

    tt_req_integration iso-sec qual-sec-inject
    pf_req_set simulator_udid "$value"
    tt_run_refused "INJECT_INTEGRATION_UDID" "${PF_REQ[@]}"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "BLOCKED" ]] || pf_fail "INJECT_INTEGRATION_UDID_NOT_BLOCKED"
    assert_inert "INJECT_INTEGRATION_UDID"
done

# Values with a newline: one entry, still data, refused.
tt_req iso-sec qual-sec-newline
pf_req_set qualification_id "qual-a
touch $PWNED"
tt_run_refused NEWLINE "${PF_REQ[@]}"
tt_expect NEWLINE BLOCKED INPUT_INVALID 121
assert_inert NEWLINE

tt_req iso-sec qual-sec-newline-target
pf_req_set test_targets "test/a_test.dart
touch $PWNED"
tt_run_refused NEWLINE_TARGET "${PF_REQ[@]}"
tt_expect NEWLINE_TARGET BLOCKED INPUT_INVALID 121
assert_inert NEWLINE_TARGET

pf_pass "INJECTION"

# ---------------------------------------------------------------- 2. no arbitrary command, no arbitrary argument

# A word that is not a well-formed KEY=VALUE is an argument: refused.
for word in --no-pub --machine --coverage --update-goldens --name=x --tags=x --reporter=json -d test flutter "flutter test" analyze -v ';id' 'rm -rf /' '--dart-define=A=b' '--dart-define-from-file=env.json' 'KEY' '=value' 'Key=value' '1key=value'; do
    tt_req iso-sec qual-sec-args
    tt_run_refused "ARG" "${PF_REQ[@]}" "$word"
    tt_expect ARG BLOCKED ARGUMENT_REFUSED 123
    assert_inert ARG
done

# Keys that would carry an option, a command, a device or a path are not in the
# contract.
for key in flutter_args test_args args command cmd flutter dart_args pub no_pub device device_id d coverage machine name plain_name tags reporter concurrency extra working_directory cwd project_path path env shell script; do
    tt_req iso-sec qual-sec-keys
    tt_run_refused "KEY_$key" "${PF_REQ[@]}" "$key=--coverage"
    tt_expect "KEY_$key" BLOCKED ARGUMENT_REFUSED 123
    assert_inert "KEY_$key"
    [[ "$(tt_value REJECTED_KEY)" == "$key" ]] || pf_fail "KEY_${key}_NOT_REPORTED"
done

# Keys that look sensitive are refused as secrets, whatever they carry, and the
# value is never printed.
for key in token secret password passwd credential api_key apikey private_key auth authorization dart_define dart_define_from_file github_token; do
    tt_req iso-sec qual-sec-secret-keys
    tt_run_refused "SECRET_$key" "${PF_REQ[@]}" "$key=hunter2-value"
    tt_expect "SECRET_$key" BLOCKED SECRET_REFUSED 125
    assert_inert "SECRET_$key"
    printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'hunter2-value' >/dev/null && pf_fail "SECRET_${key}_ECHOED"
done

# A secret in an allowed key is refused too, a dart-define as a test file too.
tt_req iso-sec qual-sec-secret-value
pf_req_set expected_origin "https://builder:hunter2secret@example.invalid/org/app.git"
tt_run_refused SECRET_ORIGIN "${PF_REQ[@]}"
tt_expect SECRET_ORIGIN BLOCKED SECRET_REFUSED 125
assert_inert SECRET_ORIGIN
printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'hunter2secret' >/dev/null && pf_fail "SECRET_ORIGIN_ECHOED"

tt_req iso-sec qual-sec-secret-target
pf_req_set test_targets "test/a_test.dart --dart-define=API_KEY=supersecretvalue123"
tt_run_refused SECRET_TARGET "${PF_REQ[@]}"
[[ "$PF_RC" -ge 120 && "$PF_RC" -le 125 ]] || pf_fail "SECRET_TARGET_RC_${PF_RC}"
assert_inert SECRET_TARGET
printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'supersecretvalue123' >/dev/null && pf_fail "SECRET_TARGET_ECHOED"

# A duplicate key never overrides an earlier one (the second evidence root would
# otherwise win).
tt_req iso-sec qual-sec-duplicate
tt_run_refused DUPLICATE "${PF_REQ[@]}" "evidence_root=$TMP/elsewhere"
tt_expect DUPLICATE BLOCKED INPUT_INVALID 121
assert_inert DUPLICATE
[[ ! -e "$TMP/elsewhere" ]] || pf_fail "DUPLICATE_WRITTEN"

# The other actions of the request are not executed by TEST: still exactly one
# "flutter test", and no analysis, build or report (the shim refuses any other
# word, which fails the run).
tt_req iso-sec qual-sec-actions
pf_req_set actions "preflight,analyze,test,build_ios,report"
pf_req_set cleanup_policy explicit
tt_run ACTIONS_ALL "${PF_REQ[@]}"
tt_expect ACTIONS_ALL PASS - 0 0
[[ "$(tt_calls)" -eq 1 ]] || pf_fail "ACTIONS_ALL_CALLS_$(tt_calls)"
assert_calls_fixed ACTIONS_ALL
[[ "$(grep -c '^flutter --version$' "$PF_LOG")" -eq 1 ]] || pf_fail "ACTIONS_ALL_PREFLIGHT"
[[ "$(grep -c -v -e '^flutter --version$' -e '^dart --version$' -e '^xcodebuild -version$' -e '^xcrun ' "$PF_LOG" || true)" -eq 0 ]] || pf_fail "ACTIONS_ALL_OTHER_TOOL"
[[ ! -d "$ISO_ROOT/iso-sec/build" ]] || pf_fail "ACTIONS_ALL_BUILD"

# The cleanup policy is not an action: "explicit" removes nothing.
[[ -d "$ISO_ROOT/iso-sec" ]] || pf_fail "ACTIONS_ALL_CLEANUP"

# A test file whose name looks like an option, or has dots, is a path (it always
# starts with "test/"): one word of the command, never an option.
tt_req iso-sec qual-sec-optionlike
pf_req_set test_targets "test/--machine_test.dart,test/name.with.dots-and_under_test.dart"
tt_run OPTION_LIKE "${PF_REQ[@]}"
tt_expect OPTION_LIKE PASS - 0 0
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 3 "test test/--machine_test.dart test/name.with.dots-and_under_test.dart" "$ISO_ROOT/iso-sec")" ]] || pf_fail "OPTION_LIKE_CALL_$(cat "$TT_CALLS")"
assert_calls_fixed OPTION_LIKE

# A simulator is given to an integration run only, and as "-d <udid>" only.
tt_req iso-sec qual-sec-device-unit
pf_req_set simulator_udid "$PF_UDID_BOOTED"
tt_run DEVICE_UNIT "${PF_REQ[@]}"
tt_expect DEVICE_UNIT PASS - 0 0
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 1 test "$ISO_ROOT/iso-sec")" ]] || pf_fail "DEVICE_UNIT_CALL"

tt_req_integration iso-sec qual-sec-device-int
tt_run DEVICE_INTEGRATION "${PF_REQ[@]}"
tt_expect DEVICE_INTEGRATION PASS - 0 0
assert_calls_fixed DEVICE_INTEGRATION
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 4 "test integration_test/app_test.dart -d $PF_UDID_BOOTED" "$ISO_ROOT/iso-sec")" ]] || pf_fail "DEVICE_INTEGRATION_CALL"

pf_pass "NO_ARBITRARY_COMMAND"

# ---------------------------------------------------------------- 3. paths and links

# Evidence root and isolation root inside the checkout, the source or each other.
tt_req iso-sec qual-sec-paths
pf_req_set evidence_root "$ISO_ROOT/iso-sec/evidence"
tt_run_refused PATH_IN_CHECKOUT "${PF_REQ[@]}"
tt_expect PATH_IN_CHECKOUT BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_IN_CHECKOUT
[[ ! -e "$ISO_ROOT/iso-sec/evidence" ]] || pf_fail "PATH_IN_CHECKOUT_CREATED"

tt_req iso-sec qual-sec-paths
pf_req_set evidence_root "$SOURCE/evidence"
tt_run_refused PATH_IN_SOURCE "${PF_REQ[@]}"
tt_expect PATH_IN_SOURCE BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_IN_SOURCE
[[ ! -e "$SOURCE/evidence" ]] || pf_fail "PATH_IN_SOURCE_CREATED"

tt_req iso-sec qual-sec-paths
pf_req_set evidence_root "$SOURCE"
tt_run_refused PATH_IS_SOURCE "${PF_REQ[@]}"
tt_expect PATH_IS_SOURCE BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_IS_SOURCE

tt_req iso-sec qual-sec-paths
pf_req_set evidence_root "$ISO_ROOT"
tt_run_refused PATH_IS_ISOLATION_ROOT "${PF_REQ[@]}"
tt_expect PATH_IS_ISOLATION_ROOT BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_IS_ISOLATION_ROOT

tt_req iso-sec qual-sec-paths
pf_req_set isolation_root "$SOURCE"
tt_run_refused ISOLATION_ROOT_IS_SOURCE "${PF_REQ[@]}"
tt_expect ISOLATION_ROOT_IS_SOURCE BLOCKED PATH_NOT_ALLOWED 124
assert_inert ISOLATION_ROOT_IS_SOURCE

tt_req iso-sec qual-sec-paths
pf_req_set evidence_root "$EVID/../evidence"
tt_run_refused PATH_DOTDOT "${PF_REQ[@]}"
tt_expect PATH_DOTDOT BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_DOTDOT

tt_req iso-sec qual-sec-paths
pf_req_set evidence_root "$SOURCE/.local/evidence"
tt_run_refused PATH_LOCAL "${PF_REQ[@]}"
tt_expect PATH_LOCAL BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_LOCAL

# A test file that exists in the source repository only is not a test file of
# the checkout: the selection is read in the isolated checkout, never in the
# source.
tt_req iso-sec qual-sec-source-only
pf_req_set test_targets "test/only_in_source_test.dart"
tt_run_refused TARGET_IN_SOURCE_ONLY "${PF_REQ[@]}"
tt_expect TARGET_IN_SOURCE_ONLY BLOCKED INPUT_INVALID 121
[[ "$(tt_calls)" -eq 0 ]] || pf_fail "TARGET_IN_SOURCE_ONLY_CALLED"
[[ "$(tt_value REJECTED_KEY)" == "test_targets" ]] || pf_fail "TARGET_IN_SOURCE_ONLY_KEY"
[[ "$(cat "$SOURCE/test/only_in_source_test.dart")" == "void main() {}" ]] || pf_fail "TARGET_IN_SOURCE_ONLY_TOUCHED"

# An isolation id that is a link to a real isolation, or to the source, is not
# a checkout owned by CBS.
ln -s "$ISO_ROOT/iso-sec" "$ISO_ROOT/iso-link"
tt_req iso-link qual-sec-link
tt_run_refused ISOLATION_LINK "${PF_REQ[@]}"
tt_expect ISOLATION_LINK NOT_RUN PREFLIGHT_NOT_PASSED 136
assert_inert_after_preflight ISOLATION_LINK
[[ "$(tt_value PREFLIGHT_RESULT)" == "BLOCKED" ]] || pf_fail "ISOLATION_LINK_PREFLIGHT_RESULT"

ln -s "$SOURCE" "$ISO_ROOT/iso-source-link"
tt_req iso-source-link qual-sec-source-link
tt_run_refused ISOLATION_SOURCE_LINK "${PF_REQ[@]}"
tt_expect ISOLATION_SOURCE_LINK NOT_RUN PREFLIGHT_NOT_PASSED 136
assert_inert_after_preflight ISOLATION_SOURCE_LINK

# A checkout replaced by a link after its creation is refused before flutter.
pf_new_isolation iso-swap "$TT_COMMIT"
mv "$ISO_ROOT/iso-swap" "$ISO_ROOT/iso-swap-real"
ln -s "$ISO_ROOT/iso-swap-real" "$ISO_ROOT/iso-swap"
tt_req iso-swap qual-sec-swap
tt_run_refused ISOLATION_SWAPPED "${PF_REQ[@]}"
tt_expect ISOLATION_SWAPPED NOT_RUN PREFLIGHT_NOT_PASSED 136
assert_inert_after_preflight ISOLATION_SWAPPED
rm "$ISO_ROOT/iso-swap"
mv "$ISO_ROOT/iso-swap-real" "$ISO_ROOT/iso-swap"

# The evidence file names cannot be redirected by a link left in place.
mkdir -m 700 "$EVID/qual-sec-link-log"
printf '%s\n' "outside" > "$TMP/outside-file"
ln -s "$TMP/outside-file" "$EVID/qual-sec-link-log/TEST.log"
tt_req iso-sec qual-sec-link-log
tt_run_refused EVIDENCE_LINK_LOG "${PF_REQ[@]}"
tt_expect EVIDENCE_LINK_LOG BLOCKED PATH_NOT_ALLOWED 124
[[ "$(cat "$TMP/outside-file")" == "outside" ]] || pf_fail "EVIDENCE_LINK_LOG_FOLLOWED"

pf_pass "PATHS_AND_LINKS"

# ---------------------------------------------------------------- 4. the environment is not trusted

tt_modes_reset

# Guards of the contracts cannot be pre-set from the environment: the runner,
# a fresh bash, must still load the contract and redact.
TT_ENV_ASSIGN="CBS_FLUTTER_QUAL_CONTRACT_LOADED=1 CBS_ISOLATION_CONTRACT_LOADED=1 CBS_WORKTREE_CONTRACT_LOADED=1"
shim_mode secret
tt_req iso-sec qual-sec-env-guards
tt_run ENV_GUARDS "${PF_REQ[@]}"
tt_expect ENV_GUARDS FAIL COMMAND_FAILED 130 1
[[ "$(tt_log qual-sec-env-guards)" == *"[REDACTED]"* ]] || pf_fail "ENV_GUARDS_NOT_REDACTED"
grep -F -e hunter2secret "$EVID/qual-sec-env-guards/TEST.log" >/dev/null && pf_fail "ENV_GUARDS_LEAK"
tt_modes_reset

# Bounds and patterns of the contract cannot be pre-set from the environment.
TT_ENV_ASSIGN="CBS_FLUTTER_QUAL_TIMEOUT_MAX=999999 CBS_FLUTTER_QUAL_PATTERN_PATH=.* CBS_FLUTTER_QUAL_PATTERN_TEST_TARGET=.* CBS_FLUTTER_QUAL_TEST_TARGETS_MAX=999 CBS_FLUTTER_QUAL_REQUIRED_KEYS="
tt_req iso-sec qual-sec-env-bounds
pf_req_set timeout_seconds 5000
tt_run_refused ENV_BOUNDS "${PF_REQ[@]}"
tt_expect ENV_BOUNDS BLOCKED INPUT_INVALID 121
assert_inert ENV_BOUNDS
tt_modes_reset

TT_ENV_ASSIGN="CBS_FLUTTER_QUAL_PATTERN_TEST_TARGET=.* CBS_FLUTTER_QUAL_TEST_TARGETS_MAX=999"
tt_req iso-sec qual-sec-env-pattern
pf_req_set test_targets "lib/evil.sh"
tt_run_refused ENV_PATTERN "${PF_REQ[@]}"
tt_expect ENV_PATTERN BLOCKED PATH_NOT_ALLOWED 124
assert_inert ENV_PATTERN
tt_modes_reset

# Fixed locations, constants of this operation and internal state are not taken
# from the environment: a selection, a scope, a device and a command given
# through the variables of the operation are ignored.
cat > "$TMP/evil-contract.sh" <<EOF
touch "$PWNED"
EOF
TT_ENV_ASSIGN="CBS_FLUTTER_QUAL_TESTOP_DIR=$TMP CBS_FLUTTER_QUAL_TESTOP_ARGUMENT=--no-pub CBS_FLUTTER_QUAL_TESTOP_DEVICE_OPTION=--evil TST_SCOPE=integration TST_TARGETS=test/evil_test.dart TST_UDID=$PF_UDID_BOOTED TST_COMMAND=evil CBS_FLUTTER_QUAL_EXEC_CONTRACT=$TMP/evil-contract.sh CBS_FLUTTER_QUAL_EXEC_DIR=$TMP CBS_FLUTTER_QUAL_EXEC_SUPERVISOR=true CBS_FLUTTER_QUAL_EXEC_RUNNER=true EX_OPERATION=ANALYZE EX_COMMAND_NAME=evil EX_RESULT=PASS EX_REASON= EX_PARTIAL=$TMP/evil-partial EX_QDIR=$TMP EX_LOG=$TMP/evil-log EX_RESULT_FILE=$TMP/evil-result EX_EVIDENCE=WRITTEN EX_STARTED=1 EX_CHECKOUT=$TMP EX_EVIDENCE_ROOT=$TMP EX_ISOLATION_ROOT=$TMP EX_TIMEOUT=1 EX_CAP=1"
tt_req iso-sec qual-sec-env-state
tt_run ENV_STATE "${PF_REQ[@]}"
tt_expect ENV_STATE PASS - 0 0
[[ ! -e "$PWNED" ]] || pf_fail "ENV_STATE_EXECUTED"
[[ ! -e "$TMP/evil-partial" ]] || pf_fail "ENV_STATE_PARTIAL"
[[ "$(cat "$TT_CALLS")" == "$(tt_call_line 1 test "$ISO_ROOT/iso-sec")" ]] || pf_fail "ENV_STATE_CALL_$(cat "$TT_CALLS")"
tt_assert_evidence ENV_STATE qual-sec-env-state
tt_modes_reset

# Git redirection variables do not reach the checks nor the tool's directory.
mkdir "$TMP/decoy"
git -C "$TMP/decoy" init -q
DECOY_BEFORE="$(iso_tree_fingerprint "$TMP/decoy")"
TT_ENV_ASSIGN="GIT_DIR=$TMP/decoy/.git GIT_WORK_TREE=$TMP/decoy GIT_INDEX_FILE=$TMP/decoy/.git/index GIT_COMMON_DIR=$TMP/decoy/.git GIT_CEILING_DIRECTORIES=$TMP CDPATH=$TMP:/tmp"
tt_req iso-sec qual-sec-env-git
tt_run ENV_GIT "${PF_REQ[@]}"
tt_expect ENV_GIT PASS - 0 0
[[ "$(iso_tree_fingerprint "$TMP/decoy")" == "$DECOY_BEFORE" ]] || pf_fail "ENV_GIT_DECOY_TOUCHED"
[[ "$(tt_value COMMIT_OBSERVED)" == "$TT_COMMIT" ]] || pf_fail "ENV_GIT_COMMIT"
assert_calls_fixed ENV_GIT
tt_modes_reset

# A startup file named by the caller is read by the first shell only, never by
# the shells of the executor: PREFLIGHT, the isolation manager, the supervisor
# and the runner.
printf 'echo "$$ $0" >> "%s"\n' "$TMP/bash-env.log" > "$TMP/bash-env.sh"
: > "$TMP/bash-env.log"
TT_ENV_ASSIGN="BASH_ENV=$TMP/bash-env.sh"
tt_req iso-sec qual-sec-bash-env
tt_run BASH_ENV "${PF_REQ[@]}"
tt_expect BASH_ENV PASS - 0 0
[[ "$(wc -l < "$TMP/bash-env.log" | tr -d ' ')" -eq 1 ]] || pf_fail "BASH_ENV_READ_BY_CHILDREN_$(tr '\n' ' ' < "$TMP/bash-env.log")"
tt_modes_reset

# noclobber inherited through SHELLOPTS must not disturb the supervisor and the
# runner, nor lose the evidence.
TT_ENV_ASSIGN="SHELLOPTS=noclobber"
tt_req iso-sec qual-sec-noclobber
tt_run NOCLOBBER "${PF_REQ[@]}"
tt_expect NOCLOBBER PASS - 0 0
tt_assert_evidence NOCLOBBER qual-sec-noclobber
tt_modes_reset

# A permissive umask of the caller does not make the evidence readable.
OLD_UMASK="$(umask)"
umask 000
tt_req iso-sec qual-sec-umask
tt_run UMASK "${PF_REQ[@]}"
umask "$OLD_UMASK"
tt_expect UMASK PASS - 0 0
tt_assert_evidence UMASK qual-sec-umask

pf_pass "ENVIRONMENT_NOT_TRUSTED"

# ---------------------------------------------------------------- 5. PATH: relative entries are never used

mkdir "$TMP/evil-cwd"
for tool in flutter dart xcodebuild xcrun git; do
    printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWNED" > "$TMP/evil-cwd/$tool"
    chmod 755 "$TMP/evil-cwd/$tool"
done

# "." and empty entries come first, and the current directory holds the fakes.
TT_CWD="$TMP/evil-cwd"
PF_PATH_PREFIX=".::relative:"
tt_req iso-sec qual-sec-path-relative
tt_run PATH_RELATIVE "${PF_REQ[@]}"
tt_expect PATH_RELATIVE PASS - 0 0
unset PF_PATH_PREFIX TT_CWD
[[ ! -e "$PWNED" ]] || pf_fail "PATH_RELATIVE_EXECUTED"
assert_calls_fixed PATH_RELATIVE

# Without any flutter in an absolute entry, the fake of the current directory is
# not a substitute.
TT_CWD="$TMP/evil-cwd"
PF_PATH_PREFIX=".::"
PF_MISSING="flutter"
tt_req iso-sec qual-sec-path-missing
tt_run_refused PATH_ONLY_RELATIVE "${PF_REQ[@]}"
unset PF_PATH_PREFIX TT_CWD PF_MISSING
tt_expect PATH_ONLY_RELATIVE NOT_RUN PREFLIGHT_NOT_PASSED 136
[[ ! -e "$PWNED" ]] || pf_fail "PATH_ONLY_RELATIVE_EXECUTED"
[[ "$(tt_calls)" -eq 0 ]] || pf_fail "PATH_ONLY_RELATIVE_TEST_CALLED"

# The same for the simulator tool of an integration run.
TT_CWD="$TMP/evil-cwd"
PF_PATH_PREFIX=".::"
tt_req_integration iso-sec qual-sec-path-xcrun
tt_run PATH_XCRUN "${PF_REQ[@]}"
unset PF_PATH_PREFIX TT_CWD
tt_expect PATH_XCRUN PASS - 0 0
[[ ! -e "$PWNED" ]] || pf_fail "PATH_XCRUN_EXECUTED"

pf_pass "PATH_RELATIVE"

# ---------------------------------------------------------------- 6. the source repository and the isolations are preserved

tt_modes_reset

# Success, failure, timeout, limit: whatever the outcome, the source repository
# (HEAD, branches, status, untracked files, .local) is exactly as it was, and no
# call was ever made from it. The isolations are neither cleaned nor reset.
for mode in ok fail hang big; do
    tt_modes_reset
    shim_mode "$mode"
    export SHIM_TEST_LINES=3000
    tt_req iso-sec "qual-sec-preserve-$mode"
    pf_req_set timeout_seconds 3
    pf_req_set log_max_bytes 4096
    tt_run "PRESERVE_$mode" "${PF_REQ[@]}"
    iso_assert_source_untouched "PRESERVE_${mode}_SOURCE"
    [[ "$(cat "$SOURCE/.local/note.txt")" == "local-dev-state" ]] || pf_fail "PRESERVE_${mode}_LOCAL"
    [[ "$(cat "$SOURCE/test/only_in_source_test.dart")" == "void main() {}" ]] || pf_fail "PRESERVE_${mode}_UNTRACKED"
    assert_calls_fixed "PRESERVE_$mode"
    [[ -z "$(git -C "$ISO_ROOT/iso-sec" status --porcelain)" ]] || pf_fail "PRESERVE_${mode}_CHECKOUT"
done

# An existing isolation that is not the one requested is never read, written or
# cleaned: iso-swap and the others keep the exact state they had.
iso_run verify iso-sec "$SOURCE" "$ISO_ROOT"
iso_expect_pass "PRESERVE_VERIFY_SEC"
iso_run verify iso-swap "$SOURCE" "$ISO_ROOT"
iso_expect_pass "PRESERVE_VERIFY_SWAP"
[[ -f "$ISO_ROOT/.cbs-isolation/iso-sec.proof" && -f "$ISO_ROOT/.cbs-isolation/iso-swap.proof" ]] || pf_fail "PRESERVE_PROOF_LOST"
iso_is_registered "$ISO_ROOT/iso-sec" || pf_fail "PRESERVE_UNREGISTERED_SEC"
iso_is_registered "$ISO_ROOT/iso-swap" || pf_fail "PRESERVE_UNREGISTERED_SWAP"

pf_pass "SOURCES_AND_ISOLATIONS_PRESERVED"

# ---------------------------------------------------------------- 7. no simulator is ever started, created or deleted

tt_modes_reset

# The simulator tool is the PREFLIGHT shim: it answers the listing only, and
# refuses (exit 99, logged) any other call, which fails the run. An integration
# run on a BOOTED simulator, and every refusal of a simulator that is not,
# asked simctl nothing but the listing.
tt_req_integration iso-sec qual-sec-sim-booted
tt_run SIM_BOOTED "${PF_REQ[@]}"
tt_expect SIM_BOOTED PASS - 0 0
pf_assert_tools_allowed SIM_BOOTED
[[ "$(grep -c '^xcrun simctl ' "$PF_LOG")" -eq "$(tt_simulator_lists)" ]] || pf_fail "SIM_BOOTED_OTHER_SIMCTL"

for udid in "$PF_UDID_SHUTDOWN" "$TT_UDID_BOOTING"; do
    tt_req_integration iso-sec "qual-sec-sim-$udid" "$udid"
    tt_run_refused "SIM_NOT_BOOTED_$udid" "${PF_REQ[@]}"
    tt_expect "SIM_NOT_BOOTED_$udid" BLOCKED SIMULATOR_UNAVAILABLE 129
    [[ "$(tt_calls)" -eq 0 ]] || pf_fail "SIM_NOT_BOOTED_${udid}_CALLED"
    pf_assert_tools_allowed "SIM_NOT_BOOTED_$udid"
    [[ "$(grep -c '^xcrun simctl ' "$PF_LOG")" -eq "$(tt_simulator_lists)" ]] || pf_fail "SIM_NOT_BOOTED_${udid}_OTHER_SIMCTL"
    # The listing says what it said: nothing changed the state of the device.
    grep -F "($udid)" "$PF_LIST" >/dev/null || pf_fail "SIM_NOT_BOOTED_${udid}_LIST_CHANGED"
done

[[ "$(grep -c -F -e '(Shutdown)' "$PF_LIST")" -ge 2 ]] || pf_fail "SIM_LIST_CHANGED"
grep -F "($TT_UDID_BOOTING) (Booting)" "$PF_LIST" >/dev/null || pf_fail "SIM_BOOTING_CHANGED"

pf_pass "NO_SIMULATOR_CHANGE"

# ---------------------------------------------------------------- 8. what the tool prints cannot become a command or a path

tt_modes_reset

# The tool prints shell syntax: it is data in the log, never executed, never in
# the answer.
shim_mode syntax
export SHIM_PWNED="$PWNED"
tt_req iso-sec qual-sec-tool-text
tt_run TOOL_TEXT "${PF_REQ[@]}"
tt_expect TOOL_TEXT FAIL COMMAND_FAILED 130 1
[[ ! -e "$PWNED" ]] || pf_fail "TOOL_TEXT_EXECUTED"
[[ "$(tt_log qual-sec-tool-text)" == *'$(touch '* ]] || pf_fail "TOOL_TEXT_NOT_IN_LOG"
printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'touch' >/dev/null && pf_fail "TOOL_TEXT_IN_ANSWER"
unset SHIM_PWNED

pf_pass "TOOL_TEXT_IS_DATA"

# ---------------------------------------------------------------- 9. static scan of the operation file

[[ -f "$TESTOP" ]] || pf_fail "STATIC_MISSING"

# The operation file is read as a whole: it holds no fixed text run by a fresh
# bash (the supervisor and the runner belong to the engine), so every rule
# applies to all of it.
ALL="$TESTOP"

if pf_code_matches "$ALL" '(^|[;&|({[:space:]])eval([[:space:]]|$)'; then
    pf_fail "STATIC_EVAL"
fi

# One sourced file, at a path derived from the file itself.
SOURCED="$(grep -En '^[[:space:]]*(source|\.)[[:space:]]' "$ALL" |
    grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$SOURCED" == 'source "$CBS_FLUTTER_QUAL_TESTOP_DIR/execution.sh"' ]] || pf_fail "STATIC_SOURCED_FILES_$SOURCED"

# No command that moves, copies, links, changes a mode or an owner, truncates,
# makes a temporary file, uses the network, a privilege or an interpreter, and
# no deletion or creation at all (the engine alone creates the evidence).
STATIC_FORBIDDEN='(^|[;&|({]|\$\()[[:space:]]*(mv|cp|touch|chmod|chown|ln|tee|dd|install|mktemp|truncate|sync|sudo|su|ssh|scp|sftp|rsync|curl|wget|nc|open|python|python3|perl|ruby|node|osascript|brew|nohup|xargs|awk|tar|unzip|git|sed|rmdir|rm|mkdir|kill|sleep|xcrun|simctl|xcodebuild|dart|flutter)[[:space:]]'
if pf_code_matches "$ALL" "$STATIC_FORBIDDEN"; then
    pf_fail "STATIC_EXTERNAL_COMMAND"
fi

# "find" only lists the symbolic links of the "test" directory, nothing else.
FINDS="$(grep -En '(^|[;&|({[:space:]])find[[:space:]]' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$FINDS" == 'found="$(find "$dir" -type l 2>/dev/null)" || return 1' ]] || pf_fail "STATIC_FIND_LIST_$FINDS"

# The operation file writes nothing: no redirection to a file, no here-document.
WRITES="$(awk '
    /^[[:space:]]*#/ { next }
    {
        probe = $0
        gsub(/[0-9]*>\/dev\/null|[0-9]*>&[0-9]|>&2|<\/dev\/null|\$\(\(/, "", probe)
        if (probe ~ /(^|[^<>])>[^&>=]|>>|>$/) { sub(/^[[:space:]]+/, ""); print }
    }' "$ALL" || true)"
[[ -z "$WRITES" ]] || pf_fail "STATIC_WRITE_LIST_$WRITES"
if pf_code_matches "$ALL" '<<'; then
    pf_fail "STATIC_HEREDOC"
fi

# Git is never run by this file, and no mutation, clean or reset is spelled.
if pf_code_matches "$ALL" 'git[[:space:]]+(clean|reset|checkout|switch|restore|add|commit|fetch|pull|push|clone|worktree|stash|gc|prune|config|remote)|-fdx|--hard|rm[[:space:]]+-|--force|cleanup|isolation_manager'; then
    pf_fail "STATIC_GIT_MUTATION"
fi

# No simulator action: nothing that boots, shuts down, creates, erases, deletes,
# installs or launches anything.
if pf_code_matches "$ALL" 'boot|shutdown|erase|delete|install|launch|spawn|simctl[[:space:]]+(create|clone|rename|upgrade|uninstall|terminate|openurl)|xcrun'; then
    pf_fail "STATIC_SIMULATOR_ACTION"
fi

# No Flutter option or action is spelled anywhere: the only words of the command
# are the two constants below, the tool found by the lookup of PREFLIGHT and
# the values of the validated request.
if pf_code_matches "$ALL" 'flutter[[:space:]]+(pub|analyze|build|clean|upgrade|doctor|config|create|run|precache|devices|emulators|install|--)|--no-pub|--machine|--coverage|--update-goldens|--dart-define|--name|--plain-name|--tags|--reporter|--concurrency|--device-id|--fatal|pub[[:space:]]+get|dart[[:space:]]+(pub|run|analyze|test|compile|fix|format)|ENSURE|--version'; then
    pf_fail "STATIC_TOOL_ACTION"
fi

[[ "$(grep -c '^readonly CBS_FLUTTER_QUAL_TESTOP_ARGUMENT="test"$' "$ALL")" -eq 1 ]] || pf_fail "STATIC_ARGUMENT_CONSTANT"
[[ "$(grep -c '^readonly CBS_FLUTTER_QUAL_TESTOP_DEVICE_OPTION="-d"$' "$ALL")" -eq 1 ]] || pf_fail "STATIC_DEVICE_CONSTANT"

ARGUMENT_USES="$(grep -n 'CBS_FLUTTER_QUAL_TESTOP_ARGUMENT' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#|^[0-9]+:readonly ' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$ARGUMENT_USES" == 'TST_COMMAND=("$1" "$CBS_FLUTTER_QUAL_TESTOP_ARGUMENT")' ]] || pf_fail "STATIC_ARGUMENT_USES_$ARGUMENT_USES"

DEVICE_USES="$(grep -n 'CBS_FLUTTER_QUAL_TESTOP_DEVICE_OPTION' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#|^[0-9]+:readonly ' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$DEVICE_USES" == 'TST_COMMAND[${#TST_COMMAND[@]}]="$CBS_FLUTTER_QUAL_TESTOP_DEVICE_OPTION"' ]] || pf_fail "STATIC_DEVICE_USES_$DEVICE_USES"

# The command is built in one place and run in one place.
COMMAND_ASSIGNS="$(grep -En 'TST_COMMAND(\[.*\])?=' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
EXPECTED_COMMAND_ASSIGNS='TST_COMMAND=("")
TST_COMMAND=("$1" "$CBS_FLUTTER_QUAL_TESTOP_ARGUMENT")
TST_COMMAND[${#TST_COMMAND[@]}]="$target"
TST_COMMAND[${#TST_COMMAND[@]}]="$CBS_FLUTTER_QUAL_TESTOP_DEVICE_OPTION"
TST_COMMAND[${#TST_COMMAND[@]}]="$TST_UDID"'
[[ "$COMMAND_ASSIGNS" == "$EXPECTED_COMMAND_ASSIGNS" ]] || pf_fail "STATIC_COMMAND_ASSIGNS_$COMMAND_ASSIGNS"

EXECUTES="$(grep -En '_cbs_flutter_qual_ex_execute' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$EXECUTES" == '_cbs_flutter_qual_ex_execute "${TST_COMMAND[@]}"' ]] || pf_fail "STATIC_EXECUTE_$EXECUTES"

# The tool comes from the lookup of PREFLIGHT, and only from there.
[[ "$(grep -c '_cbs_flutter_qual_pf_find_tool' "$ALL")" -eq 1 ]] || pf_fail "STATIC_FIND_TOOL"
pf_code_matches "$ALL" '_cbs_flutter_qual_pf_find_tool flutter\)' || pf_fail "STATIC_FIND_TOOL_ARGUMENT"

# The simulator is observed with the two read-only checks of PREFLIGHT, and
# nothing else of it.
PF_USES="$(grep -Eo '_cbs_flutter_qual_pf_[a-z_]+' "$ALL" | LC_ALL=C sort -u | tr '\n' ' ')"
[[ "$PF_USES" == "_cbs_flutter_qual_pf_check_simctl _cbs_flutter_qual_pf_check_simulator _cbs_flutter_qual_pf_find_tool _cbs_flutter_qual_pf_reset _cbs_flutter_qual_pf_result " ]] || pf_fail "STATIC_PF_USES_$PF_USES"

# No bash process is started here (the engine starts the supervisor and the
# runner), no exec, no signal.
if pf_code_matches "$ALL" '"\$\{BASH:-bash\}"|(^|[;&|({[:space:]])exec[[:space:]]|trap[[:space:]]'; then
    pf_fail "STATIC_PROCESS"
fi

# No backtick substitution, no application, no network tool named, no state outside.
if grep -F '`' "$ALL" | grep -Ev '^[[:space:]]*#' >/dev/null; then
    pf_fail "STATIC_BACKTICK"
fi
if pf_code_matches "$ALL" '[Aa][Mm][Hh]|[Uu][Ss][Rr]-|core-platform|apps/|packages/|/tmp|\$HOME|~/'; then
    pf_fail "STATIC_APPLICATION_DEPENDENCY"
fi
if pf_code_matches "$ALL" 'cbs/remote|remote_|ssh|bin/cbs'; then
    pf_fail "STATIC_COMPONENT_COUPLING"
fi

# The operation file does not change the shell state of a caller that sources
# it: "set -u" only inside the guarded main.
SET_LINES="$(grep -En '^[[:space:]]*set[[:space:]]+[-+]' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$SET_LINES" == "set -u" ]] || pf_fail "STATIC_SHELL_STATE_$SET_LINES"

# The engine and the contract are not duplicated here: no supervisor, no runner,
# no redaction, no evidence file name.
if pf_code_matches "$ALL" 'SUPERVISOR|RUNNER|redact|cksum|\.log|\.result|\.partial|CBS_ANALYZE'; then
    pf_fail "STATIC_ENGINE_DUPLICATED"
fi

echo "${TEST_PREFIX}_STATIC_SCAN=PASS"

tt_modes_reset
echo "${TEST_PREFIX}_RESULT=PASS"
