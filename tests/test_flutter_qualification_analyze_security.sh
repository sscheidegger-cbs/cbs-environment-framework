#!/usr/bin/env bash

# D04b-C.2b step 3: security test of the Flutter/iOS qualification ANALYZE.
#
# Proves that nothing but the fixed command "flutter analyze" can ever be run,
# that every value of the request is data, that the environment, the PATH and
# the links are not trusted, that the source repository is never a place to run
# or to write, that secrets do not reach the evidence, and (static scan) that
# the executor holds no other way to run, write or delete.
#
# Same hermetic setup as test_flutter_qualification_analyze.sh: real Git
# repositories and CBS isolations, shims for Flutter, Dart, Xcode and simctl.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANALYZE="$ROOT/cbs/qualification/flutter/analyze.sh"
EXECUTION="$ROOT/cbs/qualification/flutter/execution.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_ANALYZE_SECURITY"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/analyze_lib.sh"
source "$CONTRACT"

[[ -f "$ANALYZE" ]] || pf_fail "ANALYZE_MISSING"
bash -n "$ANALYZE" || pf_fail "ANALYZE_SYNTAX"
[[ -f "$EXECUTION" ]] || pf_fail "EXECUTION_MISSING"
bash -n "$EXECUTION" || pf_fail "EXECUTION_SYNTAX"

iso_fixture_init
pf_init
an_init

PWNED="$TMP/pwned"

an_run_refused() {
    AN_EVIDENCE_EXPECT=same an_run "$@"
}

shim_mode() {
    export SHIM_ANALYZE_MODE="$1"
}

# Nothing started, nothing written, nothing created by an injected value.
assert_inert() {
    [[ ! -e "$PWNED" ]] || pf_fail "${1}_INJECTION_EXECUTED"
    [[ -z "$(cat "$PF_LOG")" ]] || pf_fail "${1}_TOOL_CALLED_$(head -n 1 "$PF_LOG" | tr ' ' '_')"
    [[ "$(an_calls)" -eq 0 ]] || pf_fail "${1}_ANALYZE_CALLED"
}

# Every recorded "flutter analyze" is exactly that, from the isolated checkout.
assert_calls_fixed() {
    local label="$1"
    local line

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" == "argc=1 argv=analyze cwd=$ISO_ROOT/"* ]] || pf_fail "${label}_CALL_$line"
        case "$line" in
            *"cwd=$SOURCE"*) pf_fail "${label}_RAN_IN_SOURCE" ;;
        esac
    done < "$AN_CALLS"
}

an_modes_reset
pf_new_isolation iso-sec
iso_snapshot_source

# Reference: a plain PASS, to be sure that the refusals below are not caused by
# a broken fixture.
an_req iso-sec qual-sec-reference
an_run REFERENCE "${PF_REQ[@]}"
an_expect REFERENCE PASS - 0 0
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
for key in contract_version qualification_id isolation_id source_repository expected_origin commit isolation_root evidence_root target actions timeout_seconds log_max_bytes evidence_retention cleanup_policy; do
    for value in "${INJECTIONS[@]}"; do
        an_req iso-sec qual-sec-inject
        pf_req_set "$key" "$value"
        an_run_refused "INJECT_${key}" "${PF_REQ[@]}"
        [[ "$PF_RC" -ge 120 && "$PF_RC" -le 125 ]] || pf_fail "INJECT_${key}_RC_${PF_RC}"
        [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "BLOCKED" ]] || pf_fail "INJECT_${key}_NOT_BLOCKED"
        assert_inert "INJECT_${key}"
        # The hostile value is never echoed.
        printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'touch' -e '/etc/passwd' >/dev/null && pf_fail "INJECT_${key}_ECHOED"
    done
done

# The same values in the optional keys, which ANALYZE does not use.
for key in test_scope test_targets simulator_udid simulator_policy; do
    for value in "${INJECTIONS[@]:0:4}"; do
        an_req iso-sec qual-sec-inject
        pf_req_set "$key" "$value"
        an_run_refused "INJECT_OPT_${key}" "${PF_REQ[@]}"
        [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "BLOCKED" ]] || pf_fail "INJECT_OPT_${key}_NOT_BLOCKED"
        assert_inert "INJECT_OPT_${key}"
    done
done

# Values with a newline: one entry, still data, refused.
an_req iso-sec qual-sec-newline
pf_req_set qualification_id "qual-a
touch $PWNED"
an_run_refused NEWLINE "${PF_REQ[@]}"
an_expect NEWLINE BLOCKED INPUT_INVALID 121
assert_inert NEWLINE

pf_pass "INJECTION"

# ---------------------------------------------------------------- 2. no arbitrary command, no arbitrary argument

# A word that is not a well-formed KEY=VALUE is an argument: refused.
for word in --no-pub --fatal-infos analyze flutter "flutter analyze" -v ';id' 'rm -rf /' '--dart-define=A=b' '--dart-define-from-file=env.json' 'KEY' '=value' 'Key=value' '1key=value'; do
    an_req iso-sec qual-sec-args
    an_run_refused "ARG" "${PF_REQ[@]}" "$word"
    an_expect ARG BLOCKED ARGUMENT_REFUSED 123
    assert_inert ARG
done

# Keys that would carry an option, a command or a path are not in the contract.
for key in flutter_args analyze_args args command cmd flutter dart_args pub no_pub fatal_infos extra working_directory cwd project_path path env shell script; do
    an_req iso-sec qual-sec-keys
    an_run_refused "KEY_$key" "${PF_REQ[@]}" "$key=--no-pub"
    an_expect "KEY_$key" BLOCKED ARGUMENT_REFUSED 123
    assert_inert "KEY_$key"
    [[ "$(an_value REJECTED_KEY)" == "$key" ]] || pf_fail "KEY_${key}_NOT_REPORTED"
done

# Keys that look sensitive are refused as secrets, whatever they carry, and the
# value is never printed.
for key in token secret password passwd credential api_key apikey private_key auth authorization dart_define dart_define_from_file github_token; do
    an_req iso-sec qual-sec-secret-keys
    an_run_refused "SECRET_$key" "${PF_REQ[@]}" "$key=hunter2-value"
    an_expect "SECRET_$key" BLOCKED SECRET_REFUSED 125
    assert_inert "SECRET_$key"
    printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'hunter2-value' >/dev/null && pf_fail "SECRET_${key}_ECHOED"
done

# A secret in an allowed key is refused too.
an_req iso-sec qual-sec-secret-value
pf_req_set expected_origin "https://builder:hunter2secret@example.invalid/org/app.git"
an_run_refused SECRET_ORIGIN "${PF_REQ[@]}"
an_expect SECRET_ORIGIN BLOCKED SECRET_REFUSED 125
assert_inert SECRET_ORIGIN
printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'hunter2secret' >/dev/null && pf_fail "SECRET_ORIGIN_ECHOED"

# A duplicate key never overrides an earlier one (the second evidence root would
# otherwise win).
an_req iso-sec qual-sec-duplicate
an_run_refused DUPLICATE "${PF_REQ[@]}" "evidence_root=$TMP/elsewhere"
an_expect DUPLICATE BLOCKED INPUT_INVALID 121
assert_inert DUPLICATE
[[ ! -e "$TMP/elsewhere" ]] || pf_fail "DUPLICATE_WRITTEN"

# The other actions of the request are not executed by ANALYZE: still exactly
# one "flutter analyze", and no test, build or report.
an_req iso-sec qual-sec-actions
pf_req_set actions "preflight,analyze,test,build_ios,report"
pf_req_set test_scope unit_widget
pf_req_set test_targets "test/a_test.dart"
pf_req_set cleanup_policy explicit
an_run ACTIONS_ALL "${PF_REQ[@]}"
an_expect ACTIONS_ALL PASS - 0 0
[[ "$(an_calls)" -eq 1 ]] || pf_fail "ACTIONS_ALL_CALLS_$(an_calls)"
assert_calls_fixed ACTIONS_ALL
[[ "$(grep -c '^flutter --version$' "$PF_LOG")" -eq 1 ]] || pf_fail "ACTIONS_ALL_PREFLIGHT"
[[ "$(grep -c -v -e '^flutter --version$' -e '^dart --version$' -e '^xcodebuild -version$' -e '^xcrun ' "$PF_LOG" || true)" -eq 0 ]] || pf_fail "ACTIONS_ALL_OTHER_TOOL"
[[ ! -d "$ISO_ROOT/iso-sec/build" ]] || pf_fail "ACTIONS_ALL_BUILD"
assert_calls_fixed ACTIONS_ALL

pf_pass "NO_ARBITRARY_COMMAND"

# ---------------------------------------------------------------- 3. paths and links

# Evidence root and isolation root inside the checkout, the source or each other.
an_req iso-sec qual-sec-paths
pf_req_set evidence_root "$ISO_ROOT/iso-sec/evidence"
an_run_refused PATH_IN_CHECKOUT "${PF_REQ[@]}"
an_expect PATH_IN_CHECKOUT BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_IN_CHECKOUT
[[ ! -e "$ISO_ROOT/iso-sec/evidence" ]] || pf_fail "PATH_IN_CHECKOUT_CREATED"

an_req iso-sec qual-sec-paths
pf_req_set evidence_root "$SOURCE/evidence"
an_run_refused PATH_IN_SOURCE "${PF_REQ[@]}"
an_expect PATH_IN_SOURCE BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_IN_SOURCE
[[ ! -e "$SOURCE/evidence" ]] || pf_fail "PATH_IN_SOURCE_CREATED"

an_req iso-sec qual-sec-paths
pf_req_set evidence_root "$SOURCE"
an_run_refused PATH_IS_SOURCE "${PF_REQ[@]}"
an_expect PATH_IS_SOURCE BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_IS_SOURCE

an_req iso-sec qual-sec-paths
pf_req_set evidence_root "$ISO_ROOT"
an_run_refused PATH_IS_ISOLATION_ROOT "${PF_REQ[@]}"
an_expect PATH_IS_ISOLATION_ROOT BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_IS_ISOLATION_ROOT

an_req iso-sec qual-sec-paths
pf_req_set evidence_root "$EVID/../evidence"
an_run_refused PATH_DOTDOT "${PF_REQ[@]}"
an_expect PATH_DOTDOT BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_DOTDOT

an_req iso-sec qual-sec-paths
pf_req_set evidence_root "$SOURCE/.local/evidence"
an_run_refused PATH_LOCAL "${PF_REQ[@]}"
an_expect PATH_LOCAL BLOCKED PATH_NOT_ALLOWED 124
assert_inert PATH_LOCAL

# An isolation id that is a link to a real isolation, or to the source, is not
# a checkout owned by CBS.
ln -s "$ISO_ROOT/iso-sec" "$ISO_ROOT/iso-link"
an_req iso-link qual-sec-link
an_run_refused ISOLATION_LINK "${PF_REQ[@]}"
an_expect ISOLATION_LINK NOT_RUN PREFLIGHT_NOT_PASSED 136
assert_inert_after_preflight() {
    [[ ! -e "$PWNED" ]] || pf_fail "${1}_INJECTION_EXECUTED"
    [[ "$(an_calls)" -eq 0 ]] || pf_fail "${1}_ANALYZE_CALLED"
}
assert_inert_after_preflight ISOLATION_LINK
[[ "$(an_value PREFLIGHT_RESULT)" == "BLOCKED" ]] || pf_fail "ISOLATION_LINK_PREFLIGHT_RESULT"

ln -s "$SOURCE" "$ISO_ROOT/iso-source-link"
an_req iso-source-link qual-sec-source-link
an_run_refused ISOLATION_SOURCE_LINK "${PF_REQ[@]}"
an_expect ISOLATION_SOURCE_LINK NOT_RUN PREFLIGHT_NOT_PASSED 136
assert_inert_after_preflight ISOLATION_SOURCE_LINK

# A checkout replaced by a link after its creation is refused before flutter.
pf_new_isolation iso-swap
mv "$ISO_ROOT/iso-swap" "$ISO_ROOT/iso-swap-real"
ln -s "$ISO_ROOT/iso-swap-real" "$ISO_ROOT/iso-swap"
an_req iso-swap qual-sec-swap
an_run_refused ISOLATION_SWAPPED "${PF_REQ[@]}"
an_expect ISOLATION_SWAPPED NOT_RUN PREFLIGHT_NOT_PASSED 136
assert_inert_after_preflight ISOLATION_SWAPPED
rm "$ISO_ROOT/iso-swap"
mv "$ISO_ROOT/iso-swap-real" "$ISO_ROOT/iso-swap"

# The evidence file names cannot be redirected by a link left in place.
mkdir -m 700 "$EVID/qual-sec-link-log"
printf '%s\n' "outside" > "$TMP/outside-file"
ln -s "$TMP/outside-file" "$EVID/qual-sec-link-log/ANALYZE.log"
an_req iso-sec qual-sec-link-log
an_run_refused EVIDENCE_LINK_LOG "${PF_REQ[@]}"
an_expect EVIDENCE_LINK_LOG BLOCKED PATH_NOT_ALLOWED 124
[[ "$(cat "$TMP/outside-file")" == "outside" ]] || pf_fail "EVIDENCE_LINK_LOG_FOLLOWED"

pf_pass "PATHS_AND_LINKS"

# ---------------------------------------------------------------- 4. the environment is not trusted

an_modes_reset

# Guards of the contracts cannot be pre-set from the environment: the runner,
# a fresh bash, must still load the contract and redact.
AN_ENV_ASSIGN="CBS_FLUTTER_QUAL_CONTRACT_LOADED=1 CBS_ISOLATION_CONTRACT_LOADED=1 CBS_WORKTREE_CONTRACT_LOADED=1"
shim_mode secret
an_req iso-sec qual-sec-env-guards
an_run ENV_GUARDS "${PF_REQ[@]}"
an_expect ENV_GUARDS FAIL COMMAND_FAILED 130 1
[[ "$(an_log qual-sec-env-guards)" == *"[REDACTED]"* ]] || pf_fail "ENV_GUARDS_NOT_REDACTED"
grep -F -e hunter2secret "$EVID/qual-sec-env-guards/ANALYZE.log" >/dev/null && pf_fail "ENV_GUARDS_LEAK"
an_modes_reset

# Bounds and patterns of the contract cannot be pre-set from the environment.
AN_ENV_ASSIGN="CBS_FLUTTER_QUAL_TIMEOUT_MAX=999999 CBS_FLUTTER_QUAL_PATTERN_PATH=.* CBS_FLUTTER_QUAL_REQUIRED_KEYS="
an_req iso-sec qual-sec-env-bounds
pf_req_set timeout_seconds 5000
an_run_refused ENV_BOUNDS "${PF_REQ[@]}"
an_expect ENV_BOUNDS BLOCKED INPUT_INVALID 121
assert_inert ENV_BOUNDS
an_modes_reset

# Fixed locations and internal state are not taken from the environment.
cat > "$TMP/evil-contract.sh" <<EOF
touch "$PWNED"
EOF
AN_ENV_ASSIGN="CBS_FLUTTER_QUAL_ANALYZE_CONTRACT=$TMP/evil-contract.sh CBS_FLUTTER_QUAL_ANALYZE_DIR=$TMP CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT=--no-pub CBS_FLUTTER_QUAL_ANALYZE_SUPERVISOR=true CBS_FLUTTER_QUAL_ANALYZE_RUNNER=true AN_RESULT=PASS AN_PARTIAL=$TMP/evil-partial AN_QDIR=$TMP AN_EVIDENCE=WRITTEN CBS_FLUTTER_QUAL_EXEC_CONTRACT=$TMP/evil-contract.sh CBS_FLUTTER_QUAL_EXEC_DIR=$TMP CBS_FLUTTER_QUAL_EXEC_SUPERVISOR=true CBS_FLUTTER_QUAL_EXEC_RUNNER=true EX_OPERATION=TEST EX_COMMAND_NAME=evil EX_RESULT=PASS EX_REASON= EX_PARTIAL=$TMP/evil-partial EX_QDIR=$TMP EX_LOG=$TMP/evil-log EX_RESULT_FILE=$TMP/evil-result EX_EVIDENCE=WRITTEN EX_STARTED=1 EX_CHECKOUT=$TMP EX_EVIDENCE_ROOT=$TMP EX_ISOLATION_ROOT=$TMP EX_TIMEOUT=1 EX_CAP=1"
an_req iso-sec qual-sec-env-state
an_run ENV_STATE "${PF_REQ[@]}"
an_expect ENV_STATE PASS - 0 0
[[ ! -e "$PWNED" ]] || pf_fail "ENV_STATE_EXECUTED"
[[ ! -e "$TMP/evil-partial" ]] || pf_fail "ENV_STATE_PARTIAL"
assert_calls_fixed ENV_STATE
an_assert_evidence ENV_STATE qual-sec-env-state
an_modes_reset

# Git redirection variables do not reach the checks nor the tool's directory.
mkdir "$TMP/decoy"
git -C "$TMP/decoy" init -q
DECOY_BEFORE="$(iso_tree_fingerprint "$TMP/decoy")"
AN_ENV_ASSIGN="GIT_DIR=$TMP/decoy/.git GIT_WORK_TREE=$TMP/decoy GIT_INDEX_FILE=$TMP/decoy/.git/index GIT_COMMON_DIR=$TMP/decoy/.git GIT_CEILING_DIRECTORIES=$TMP CDPATH=$TMP:/tmp"
an_req iso-sec qual-sec-env-git
an_run ENV_GIT "${PF_REQ[@]}"
an_expect ENV_GIT PASS - 0 0
[[ "$(iso_tree_fingerprint "$TMP/decoy")" == "$DECOY_BEFORE" ]] || pf_fail "ENV_GIT_DECOY_TOUCHED"
[[ "$(an_value COMMIT_OBSERVED)" == "$C2" ]] || pf_fail "ENV_GIT_COMMIT"
assert_calls_fixed ENV_GIT
an_modes_reset

# A startup file named by the caller is read by the first shell only (it started
# before the executor could do anything), never by the shells of the executor:
# PREFLIGHT, the isolation manager, the supervisor and the runner.
printf 'echo "$$ $0" >> "%s"\n' "$TMP/bash-env.log" > "$TMP/bash-env.sh"
: > "$TMP/bash-env.log"
AN_ENV_ASSIGN="BASH_ENV=$TMP/bash-env.sh"
an_req iso-sec qual-sec-bash-env
an_run BASH_ENV "${PF_REQ[@]}"
an_expect BASH_ENV PASS - 0 0
[[ "$(wc -l < "$TMP/bash-env.log" | tr -d ' ')" -eq 1 ]] || pf_fail "BASH_ENV_READ_BY_CHILDREN_$(tr '\n' ' ' < "$TMP/bash-env.log")"
an_modes_reset

# noclobber and errexit inherited through SHELLOPTS must not disturb the
# supervisor and the runner (they reset them), nor lose the evidence.
AN_ENV_ASSIGN="SHELLOPTS=noclobber"
an_req iso-sec qual-sec-noclobber
an_run NOCLOBBER "${PF_REQ[@]}"
an_expect NOCLOBBER PASS - 0 0
an_assert_evidence NOCLOBBER qual-sec-noclobber
an_modes_reset

# A permissive umask of the caller does not make the evidence readable.
OLD_UMASK="$(umask)"
umask 000
an_req iso-sec qual-sec-umask
an_run UMASK "${PF_REQ[@]}"
umask "$OLD_UMASK"
an_expect UMASK PASS - 0 0
an_assert_evidence UMASK qual-sec-umask

pf_pass "ENVIRONMENT_NOT_TRUSTED"

# ---------------------------------------------------------------- 5. PATH: relative entries are never used

mkdir "$TMP/evil-cwd"
for tool in flutter dart xcodebuild xcrun git; do
    printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWNED" > "$TMP/evil-cwd/$tool"
    chmod 755 "$TMP/evil-cwd/$tool"
done

# "." and empty entries come first, and the current directory holds the fakes.
AN_CWD="$TMP/evil-cwd"
PF_PATH_PREFIX=".::relative:"
an_req iso-sec qual-sec-path-relative
an_run PATH_RELATIVE "${PF_REQ[@]}"
an_expect PATH_RELATIVE PASS - 0 0
unset PF_PATH_PREFIX AN_CWD
[[ ! -e "$PWNED" ]] || pf_fail "PATH_RELATIVE_EXECUTED"
assert_calls_fixed PATH_RELATIVE

# Without any flutter in an absolute entry, the fake of the current directory is
# not a substitute.
AN_CWD="$TMP/evil-cwd"
PF_PATH_PREFIX=".::"
PF_MISSING="flutter"
an_req iso-sec qual-sec-path-missing
an_run_refused PATH_ONLY_RELATIVE "${PF_REQ[@]}"
unset PF_PATH_PREFIX AN_CWD PF_MISSING
an_expect PATH_ONLY_RELATIVE NOT_RUN PREFLIGHT_NOT_PASSED 136
[[ ! -e "$PWNED" ]] || pf_fail "PATH_ONLY_RELATIVE_EXECUTED"
[[ "$(an_calls)" -eq 0 ]] || pf_fail "PATH_ONLY_RELATIVE_ANALYZE_CALLED"

pf_pass "PATH_RELATIVE"

# ---------------------------------------------------------------- 6. the source repository is preserved

an_modes_reset

# Success, failure, timeout, limit: whatever the outcome, the source repository
# (HEAD, branches, status, untracked files, .local) is exactly as it was, and no
# call was ever made from it.
for mode in ok issues hang big; do
    an_modes_reset
    shim_mode "$mode"
    export SHIM_ANALYZE_LINES=3000
    an_req iso-sec "qual-sec-preserve-$mode"
    pf_req_set timeout_seconds 3
    pf_req_set log_max_bytes 4096
    an_run "PRESERVE_$mode" "${PF_REQ[@]}"
    iso_assert_source_untouched "PRESERVE_${mode}_SOURCE"
    [[ "$(cat "$SOURCE/.local/note.txt")" == "local-dev-state" ]] || pf_fail "PRESERVE_${mode}_LOCAL"
    assert_calls_fixed "PRESERVE_$mode"
    [[ -z "$(git -C "$ISO_ROOT/iso-sec" status --porcelain)" ]] || pf_fail "PRESERVE_${mode}_CHECKOUT"
done

pf_pass "SOURCE_PRESERVED"

# ---------------------------------------------------------------- 7. what the tool prints cannot become a command or a path

an_modes_reset

# The tool prints shell syntax: it is data in the log, never executed, never in
# the answer.
shim_mode syntax
export SHIM_PWNED="$PWNED"
an_req iso-sec qual-sec-tool-text
an_run TOOL_TEXT "${PF_REQ[@]}"
an_expect TOOL_TEXT FAIL COMMAND_FAILED 130 1
[[ ! -e "$PWNED" ]] || pf_fail "TOOL_TEXT_EXECUTED"
[[ "$(an_log qual-sec-tool-text)" == *'$(touch '* ]] || pf_fail "TOOL_TEXT_NOT_IN_LOG"
printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e 'touch' >/dev/null && pf_fail "TOOL_TEXT_IN_ANSWER"
unset SHIM_PWNED

pf_pass "TOOL_TEXT_IS_DATA"

# ---------------------------------------------------------------- 8. static scan of the executor

[[ -f "$ANALYZE" ]] || pf_fail "STATIC_MISSING"
[[ -f "$EXECUTION" ]] || pf_fail "STATIC_EXECUTION_MISSING"

# The executor is made of two files: the operation (analyze.sh) and the common
# execution engine it sources (execution.sh, D04b-C.2e). Every rule below that
# was written for the single former file applies to the two of them together
# (ALL), so that moving code from one to the other never removes a check.
#
# The executor is read in three parts: the runner and the supervisor (fixed
# texts run by a fresh bash, with their own rules, held by the engine) and
# everything else (the strict rules).
ALL="$TMP/executor-all.sh"
OUTSIDE_ENGINE="$TMP/execution-outside.sh"
OUTSIDE="$TMP/executor-outside.sh"
SUPERVISOR="$TMP/analyze-supervisor.sh"
RUNNER="$TMP/analyze-runner.sh"
cat "$ANALYZE" "$EXECUTION" > "$ALL"
sed -e "/^CBS_FLUTTER_QUAL_EXEC_SUPERVISOR='\$/,/^'\$/d" -e "/^CBS_FLUTTER_QUAL_EXEC_RUNNER='\$/,/^'\$/d" "$EXECUTION" > "$OUTSIDE_ENGINE"
cat "$ANALYZE" "$OUTSIDE_ENGINE" > "$OUTSIDE"
sed -n -e "/^CBS_FLUTTER_QUAL_EXEC_SUPERVISOR='\$/,/^'\$/p" "$EXECUTION" | sed -e '1d' -e '$d' > "$SUPERVISOR"
sed -n -e "/^CBS_FLUTTER_QUAL_EXEC_RUNNER='\$/,/^'\$/p" "$EXECUTION" | sed -e '1d' -e '$d' > "$RUNNER"
[[ -s "$SUPERVISOR" && -s "$RUNNER" ]] || pf_fail "STATIC_TEXTS_NOT_FOUND"
[[ "$(grep -c "CBS_FLUTTER_QUAL_EXEC_SUPERVISOR='" "$ALL")" -eq 1 ]] || pf_fail "STATIC_SUPERVISOR_DEFINED_ONCE"
[[ "$(grep -c "CBS_FLUTTER_QUAL_EXEC_RUNNER='" "$ALL")" -eq 1 ]] || pf_fail "STATIC_RUNNER_DEFINED_ONCE"
! grep -q -e "SUPERVISOR='" -e "RUNNER='" "$OUTSIDE" || pf_fail "STATIC_TEXTS_SPLIT"
! grep -q -e "SUPERVISOR='" -e "RUNNER='" "$ANALYZE" || pf_fail "STATIC_TEXTS_IN_OPERATION_FILE"
bash -n "$SUPERVISOR" || pf_fail "STATIC_SUPERVISOR_SYNTAX"
bash -n "$RUNNER" || pf_fail "STATIC_RUNNER_SYNTAX"

if pf_code_matches "$ALL" '(^|[;&|({[:space:]])eval([[:space:]]|$)'; then
    pf_fail "STATIC_EVAL"
fi

if pf_code_matches "$SUPERVISOR" '(^|[;&|({[:space:]])(eval|source|alias|enable|builtin)([[:space:]]|$)|(^|[[:space:]])\.[[:space:]]'; then
    pf_fail "STATIC_SUPERVISOR_EVAL"
fi

# The runner sources the contract, once, from its argument; nothing else.
RUNNER_SOURCES="$(grep -En '(^|[;&|({[:space:]])(source|\.)[[:space:]]' "$RUNNER" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://')"
[[ "$RUNNER_SOURCES" == '. "$contract" || exit 252' ]] || pf_fail "STATIC_RUNNER_SOURCES_$RUNNER_SOURCES"

# Outside the texts, one sourced file per file, at a path derived from the file
# itself: the operation sources the engine, the engine sources PREFLIGHT.
SOURCED="$(grep -En '^[[:space:]]*(source|\.)[[:space:]]' "$ANALYZE" |
    grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$SOURCED" == 'source "$CBS_FLUTTER_QUAL_ANALYZE_DIR/execution.sh"' ]] || pf_fail "STATIC_SOURCED_FILES_OPERATION"
SOURCED="$(grep -En '^[[:space:]]*(source|\.)[[:space:]]' "$OUTSIDE_ENGINE" |
    grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$SOURCED" == 'source "$CBS_FLUTTER_QUAL_EXEC_DIR/preflight.sh"' ]] || pf_fail "STATIC_SOURCED_FILES_ENGINE"

# No command that moves, copies, links, changes a mode or an owner, truncates,
# makes a temporary file, uses the network, a privilege or an interpreter. The
# only ones left are the ones listed below.
STATIC_FORBIDDEN='(^|[;&|({]|\$\()[[:space:]]*(mv|cp|touch|chmod|chown|ln|tee|dd|install|mktemp|truncate|sync|sudo|su|ssh|scp|sftp|rsync|curl|wget|nc|open|python|python3|perl|ruby|node|osascript|brew|nohup|xargs|awk|tar|unzip|git|sed|rmdir)[[:space:]]'
for scanned in "$OUTSIDE" "$SUPERVISOR" "$RUNNER"; do
    if pf_code_matches "$scanned" "$STATIC_FORBIDDEN"; then
        pf_fail "STATIC_EXTERNAL_COMMAND_$(basename "$scanned")"
    fi
done

# Removal: exactly one "rm", of the capture of this run, forced only so that an
# already absent capture is not an error; never recursive.
RMS="$(grep -En '(^|[;&|({[:space:]])rm[[:space:]]' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$RMS" == 'rm -f -- "$EX_PARTIAL" 2>/dev/null || return 1' ]] || pf_fail "STATIC_RM_LIST_$RMS"

# Directory creation: exactly one "mkdir", without "-p": the evidence root is the
# parent and must exist.
MKDIRS="$(grep -En '(^|[;&|({[:space:]])mkdir[[:space:]]' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$MKDIRS" == '( umask 077; mkdir "$EX_QDIR" ) 2>/dev/null || return 1' ]] || pf_fail "STATIC_MKDIR_LIST_$MKDIRS"

# "find" only reads the mode of a directory.
FINDS="$(grep -En '(^|[;&|({[:space:]])find[[:space:]]' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$FINDS" == 'found="$(find "$path" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" || return 1' ]] || pf_fail "STATIC_FIND_LIST_$FINDS"

# Every file written is created exclusively (noclobber) under a private umask,
# or is the capture opened by the runner on a file this run just reserved.
WRITES="$(awk '
    /^[[:space:]]*#/ { next }
    {
        probe = $0
        gsub(/[0-9]*>\/dev\/null|[0-9]*>&[0-9]|>&2|<\/dev\/null|\$\(\(/, "", probe)
        if (probe ~ /(^|[^<>])>[^&>=]|>>|>$/) { sub(/^[[:space:]]+/, ""); print }
    }' "$OUTSIDE" || true)"
EXPECTED_WRITES='( umask 077; set -C; : > "$EX_PARTIAL" ) 2>/dev/null || return 1
( umask 077; set -C; head -c "$cap" "$EX_PARTIAL" > "$EX_LOG" ) 2>/dev/null || return 1
( umask 077; set -C; printf '"'"'%s\n'"'"' "$EX_BODY" > "$EX_RESULT_FILE" ) 2>/dev/null || return 1'
if [[ "$WRITES" != "$EXPECTED_WRITES" ]]; then
    printf '%s\n' "$WRITES" > "$TMP/static-writes.txt"
    pf_fail "STATIC_WRITE_LIST"
fi

# Git is never run by this file (it is reached through PREFLIGHT and the
# isolation manager only), and no mutation, clean or reset is spelled anywhere.
if pf_code_matches "$ALL" '(^|[;&|({]|\$\()[[:space:]]*git[[:space:]]'; then
    pf_fail "STATIC_GIT_COMMAND"
fi
if pf_code_matches "$ALL" 'git[[:space:]]+(clean|reset|checkout|switch|restore|add|commit|fetch|pull|push|clone|worktree|stash|gc|prune|config|remote)|-fdx|--hard|rm[[:space:]]+-[a-zA-Z]*[rR]|--force|rm[[:space:]]+-rf'; then
    pf_fail "STATIC_GIT_MUTATION"
fi

# Flutter is run with the constant and nothing else: the word "analyze" is the
# only action, no option is spelled, and no other tool is mentioned as command.
if pf_code_matches "$ALL" 'flutter[[:space:]]+(pub|test|build|clean|upgrade|doctor|config|create|run|precache|devices|emulators|install|--)|--no-pub|--fatal|--no-fatal|--watch|--suggestions|--write|--dart-define|pub[[:space:]]+get|dart[[:space:]]+(pub|run|analyze|test|compile|fix|format)|xcodebuild[[:space:]]+-?(build|archive|clean|test)|xcrun|simctl|ENSURE|--version'; then
    pf_fail "STATIC_TOOL_ACTION"
fi

[[ "$(grep -c '^readonly CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT="analyze"$' "$ANALYZE")" -eq 1 ]] || pf_fail "STATIC_ARGUMENT_CONSTANT"
ARGUMENT_USES="$(grep -n 'CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#|^[0-9]+:readonly ' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$ARGUMENT_USES" == '_cbs_flutter_qual_ex_execute "$flutter" "$CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT"' ]] || pf_fail "STATIC_ARGUMENT_USES_$ARGUMENT_USES"

# The command comes from the PATH lookup of PREFLIGHT, and only from there. It
# is looked up by the operation file: the engine never looks a tool up, never
# names a command and never spells the argument of an operation.
[[ "$(grep -c '_cbs_flutter_qual_pf_find_tool' "$ALL")" -eq 1 ]] || pf_fail "STATIC_FIND_TOOL"
pf_code_matches "$ANALYZE" '_cbs_flutter_qual_pf_find_tool flutter\)' || pf_fail "STATIC_FIND_TOOL_ARGUMENT"
! pf_code_matches "$EXECUTION" '_cbs_flutter_qual_pf_find_tool|CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT|"analyze"' || pf_fail "STATIC_ENGINE_NAMES_A_COMMAND"
! pf_code_matches "$EXECUTION" '(^|[^A-Za-z_./-])(flutter|dart|xcodebuild|xcrun|simctl)([^A-Za-z_]|$)' || pf_fail "STATIC_ENGINE_NAMES_A_TOOL"

# The bash processes started: the supervisor (fixed text) and, from it, the
# runner (fixed text). Nothing else is exec'd outside those texts.
BASH_STARTS="$(grep -En '"\$\{BASH:-bash\}"' "$ALL" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
EXPECTED_BASH_STARTS='( cd "$dir" && exec "${BASH:-bash}" -c "$runner" cbs-analyze-runner "$contract" "$out" "$((cap + 1))" "$@" ) </dev/null &
EX_RUN_RAW="$("${BASH:-bash}" -c "$CBS_FLUTTER_QUAL_EXEC_SUPERVISOR" cbs-analyze-supervisor \'
[[ "$BASH_STARTS" == "$EXPECTED_BASH_STARTS" ]] || pf_fail "STATIC_BASH_START_LIST"

EXECS="$(grep -En '(^|[;&|({[:space:]])exec[[:space:]]' "$OUTSIDE" | grep -Ev '^[0-9]+:[[:space:]]*#' || true)"
[[ -z "$EXECS" ]] || pf_fail "STATIC_EXEC_OUTSIDE_TEXTS"

SUP_EXECS="$(grep -En '(^|[;&|({[:space:]])exec[[:space:]]' "$SUPERVISOR" | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
EXPECTED_SUP_EXECS='exec 2>/dev/null
( cd "$dir" && exec "${BASH:-bash}" -c "$runner" cbs-analyze-runner "$contract" "$out" "$((cap + 1))" "$@" ) </dev/null &
( sleep "$limit"; kill -USR1 "$$"; exec sleep 86400 ) </dev/null >/dev/null 2>&1 &'
[[ "$SUP_EXECS" == "$EXPECTED_SUP_EXECS" ]] || pf_fail "STATIC_SUPERVISOR_EXEC_LIST"

RUNNER_EXECS="$(grep -En '(^|[;&|({[:space:]])exec[[:space:]]' "$RUNNER" | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
EXPECTED_RUNNER_EXECS='( LC_ALL=C exec "$@" ) 2>&1 | ( trap "" TERM; set -o pipefail; LC_ALL=C cbs_flutter_qual_redact_stream | head -c "$cap" >| "$out" )'
[[ "$RUNNER_EXECS" == "$EXPECTED_RUNNER_EXECS" ]] || pf_fail "STATIC_RUNNER_EXEC_LIST"

# The timer signals the supervisor only, never the command or its group.
TIMER_LINE="$(grep -F 'kill -USR1' "$SUPERVISOR")"
[[ "$TIMER_LINE" == *'kill -USR1 "$$"'* && "$TIMER_LINE" != *'$child'* ]] || pf_fail "STATIC_SUPERVISOR_TIMER_SIGNALS_COMMAND"

# The supervisor signals the group of the runner only, and only from a handler.
SUP_KILLS="$(grep -En '(^|[;&|({[:space:]])kill[[:space:]]' "$SUPERVISOR" | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
EXPECTED_SUP_KILLS='kill -KILL -- "-$timer"
kill -KILL -- "-$child"
kill -TERM -- "-$child"
kill -KILL -- "-$child"
( sleep "$limit"; kill -USR1 "$$"; exec sleep 86400 ) </dev/null >/dev/null 2>&1 &'
[[ "$SUP_KILLS" == "$EXPECTED_SUP_KILLS" ]] || pf_fail "STATIC_SUPERVISOR_KILL_LIST"

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

# Neither the executor nor its texts change the shell state of a caller that
# sources it: no "set -e" / "set -u" outside the guarded main (which belongs to
# the operation file: the engine is a library and has none).
SET_OUTSIDE="$(grep -En '^[[:space:]]*set[[:space:]]+[-+]' "$OUTSIDE" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$SET_OUTSIDE" == "set -u" ]] || pf_fail "STATIC_SHELL_STATE_$SET_OUTSIDE"
! grep -Eq '^[[:space:]]*set[[:space:]]+[-+]' "$OUTSIDE_ENGINE" || pf_fail "STATIC_ENGINE_SHELL_STATE"
! grep -Fq 'BASH_SOURCE[0]}" == "$0"' "$EXECUTION" || pf_fail "STATIC_ENGINE_HAS_MAIN"

echo "${TEST_PREFIX}_STATIC_SCAN=PASS"

pf_modes_reset
echo "${TEST_PREFIX}_RESULT=PASS"
