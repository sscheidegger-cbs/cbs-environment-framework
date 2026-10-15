#!/usr/bin/env bash

# D04b-C.2b step 2: hermetic test of the Flutter/iOS qualification PREFLIGHT.
#
# Real Git repositories and real CBS isolations in a private directory; Flutter,
# Dart, Xcode and simctl are shims generated at run time. The PATH given to the
# executor holds only those shims and links to the system tools it needs: a real
# Flutter or Xcode of the host can never be found. Every run is checked for the
# absence of mutation (source, isolation root, evidence root).
#
# Nothing here qualifies a real Mac: see the BASH32 line for the one check that
# needs a native Bash 3.2.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFLIGHT="$ROOT/cbs/qualification/flutter/preflight.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_PREFLIGHT"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$CONTRACT"

[[ -f "$PREFLIGHT" ]] || pf_fail "PREFLIGHT_MISSING"
bash -n "$PREFLIGHT" || pf_fail "PREFLIGHT_SYNTAX"

iso_fixture_init
pf_init

ALL_CHECKS="PARAMETERS EVIDENCE_ROOT GIT_CONFIG_GUARD OWNERSHIP COMMIT ORIGIN DETACHED_HEAD GIT_STATE STACK_REFERENCE FLUTTER DART XCODE SDK_IPHONEOS SDK_IPHONESIMULATOR SIMCTL SIMULATOR"

# assert_checks <label> <check>=<RESULT>... : the listed checks have exactly
# that result; every other check is expected to be reported too.
assert_checks() {
    local label="$1"
    local spec
    local name
    local value

    shift

    for spec in "$@"; do
        name="${spec%%=*}"
        value="${spec#*=}"
        [[ "$(pf_check "$name")" == "$value" ]] ||
            pf_fail "${label}_CHECK_${name}_EXPECTED_${value}_GOT_$(pf_check "$name")"
    done

    for name in $ALL_CHECKS; do
        [[ -n "$(pf_check "$name")" ]] || pf_fail "${label}_CHECK_${name}_MISSING"
    done
}

# assert_all_not_run_after <label> <check>... : every check of the list is NOT_RUN.
assert_not_run() {
    local label="$1"
    local name

    shift

    for name in "$@"; do
        [[ "$(pf_check "$name")" == "NOT_RUN" ]] || pf_fail "${label}_${name}_NOT_NOT_RUN_$(pf_check "$name")"
        [[ "$(pf_check_reason "$name")" == "NOT_EXECUTED" ]] || pf_fail "${label}_${name}_REASON"
    done
}

TOOLCHAIN_CHECKS="STACK_REFERENCE FLUTTER DART XCODE SDK_IPHONEOS SDK_IPHONESIMULATOR SIMCTL SIMULATOR"
ISOLATION_CHECKS="OWNERSHIP COMMIT ORIGIN DETACHED_HEAD GIT_STATE"

# ---------------------------------------------------------------- 1. PASS

pf_modes_reset
pf_new_isolation iso-pass
iso_snapshot_source

# A reference time: nothing under the three roots may be newer afterwards.
: > "$TMP/marker"
sleep 1

pf_req_reset iso-pass
pf_run PASS "${PF_REQ[@]}"
pf_expect PASS PASS - 0

assert_checks PASS \
    PARAMETERS=PASS EVIDENCE_ROOT=PASS GIT_CONFIG_GUARD=PASS OWNERSHIP=PASS COMMIT=PASS ORIGIN=PASS \
    DETACHED_HEAD=PASS GIT_STATE=PASS STACK_REFERENCE=PASS FLUTTER=PASS DART=PASS \
    XCODE=PASS SDK_IPHONEOS=PASS SDK_IPHONESIMULATOR=PASS SIMCTL=PASS SIMULATOR=PASS

[[ "$(pf_value COMMIT_OBSERVED)" == "$C2" ]] || pf_fail "PASS_COMMIT_OBSERVED"
[[ "$(pf_value GIT_VERSION)" == "$(git --version | sed -n 's/^git version \([0-9][0-9.]*\).*/\1/p')" ]] || pf_fail "PASS_GIT_VERSION"
[[ "$(pf_value QUALIFICATION_ID)" == "qual-pf-1" ]] || pf_fail "PASS_QUALIFICATION_ID"
[[ "$(pf_value FLUTTER_VERSION)" == "$PF_FLUTTER_REQUIRED" ]] || pf_fail "PASS_FLUTTER_VERSION"
[[ "$(pf_value FLUTTER_REQUIRED_VERSION)" == "$PF_FLUTTER_REQUIRED" ]] || pf_fail "PASS_FLUTTER_REQUIRED"
[[ "$(pf_value XCODE_MINIMUM_MAJOR)" == "$PF_XCODE_MINIMUM" ]] || pf_fail "PASS_XCODE_MINIMUM"
[[ "$(pf_value DART_VERSION)" == "3.9.0" ]] || pf_fail "PASS_DART_VERSION"
[[ "$(pf_value XCODE_VERSION)" == "15.4" ]] || pf_fail "PASS_XCODE_VERSION"
[[ "$(pf_value IPHONEOS_SDK_VERSION)" == "17.5" ]] || pf_fail "PASS_IPHONEOS_SDK"
[[ "$(pf_value IPHONESIMULATOR_SDK_VERSION)" == "17.5" ]] || pf_fail "PASS_IPHONESIMULATOR_SDK"
[[ "$(pf_value SIMULATOR_STATE)" == "SHUTDOWN" ]] || pf_fail "PASS_SIMULATOR_STATE"
[[ "$(pf_value EVIDENCE_ROOT_STATE)" == "DIRECTORY" ]] || pf_fail "PASS_EVIDENCE_STATE"

# Available is not operational: the simulator was never started, never probed.
[[ "$(pf_value SIMULATOR_OPERATIONAL)" == "NOT_OBSERVED" ]] || pf_fail "PASS_SIMULATOR_OPERATIONAL"

# Exactly the seven fixed probes, once each.
[[ "$(pf_tool_calls)" -eq 7 ]] || pf_fail "PASS_TOOL_CALL_COUNT_$(pf_tool_calls)"
pf_assert_tools_allowed PASS
[[ "$(grep -c '^flutter --version$' "$PF_LOG")" -eq 1 ]] || pf_fail "PASS_FLUTTER_ONCE"
[[ "$(pf_git_calls)" -gt 0 ]] || pf_fail "PASS_NO_GIT_OBSERVATION"
pf_assert_git_readonly PASS

# Read-only: nothing under the roots is newer than the marker.
CHANGED="$(find "$SOURCE" "$ISO_ROOT" "$EVID" -newer "$TMP/marker" -print)"
[[ -z "$CHANGED" ]] || pf_fail "PASS_ROOT_WRITTEN_$(printf '%s' "$CHANGED" | head -n 1)"
iso_assert_source_untouched "PASS_SOURCE"

# The structured answer is stable.
FIRST_OUT="$PF_OUT"
pf_run PASS_AGAIN "${PF_REQ[@]}"
[[ "$PF_OUT" == "$FIRST_OUT" ]] || pf_fail "PASS_NOT_DETERMINISTIC"

# No path of the host is ever printed.
if printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e "$TMP" -e "$SOURCE" -e "/fake/" >/dev/null; then
    pf_fail "PASS_PATH_LEAKED"
fi

# An absent evidence root is not created and does not block.
rmdir "$EVID"
pf_run PASS_EVIDENCE_ABSENT "${PF_REQ[@]}"
pf_expect PASS_EVIDENCE_ABSENT PASS - 0
[[ "$(pf_value EVIDENCE_ROOT_STATE)" == "ABSENT" ]] || pf_fail "EVIDENCE_ABSENT_STATE"
[[ ! -e "$EVID" ]] || pf_fail "EVIDENCE_ROOT_CREATED"
mkdir "$EVID"

pf_pass "PASS"

# ---------------------------------------------------------------- 2. simulator: booted, SKIPPED, case

pf_req_reset iso-pass
pf_req_set simulator_udid "$PF_UDID_BOOTED"
pf_run SIM_BOOTED "${PF_REQ[@]}"
pf_expect SIM_BOOTED PASS - 0
[[ "$(pf_value SIMULATOR_STATE)" == "BOOTED" ]] || pf_fail "SIM_BOOTED_STATE"
[[ "$(pf_value SIMULATOR_OPERATIONAL)" == "NOT_OBSERVED" ]] || pf_fail "SIM_BOOTED_OPERATIONAL"

# UDIDs compare regardless of letter case.
pf_req_set simulator_udid "$(printf '%s' "$PF_UDID_SHUTDOWN" | tr '0-9' 'a-j')"
pf_req_set simulator_udid "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
cat > "$PF_LIST" <<EOF
-- iOS 17.5 --
    iPhone Lower (AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA) (Shutdown)
EOF
pf_run SIM_CASE "${PF_REQ[@]}"
pf_expect SIM_CASE PASS - 0
pf_devices_default

# No simulator requested: the check is SKIPPED (visible, never PASS), nothing
# is listed, the executor does not look for a default simulator.
pf_req_reset iso-pass
pf_req_unset simulator_udid
pf_req_unset simulator_policy
pf_run SIM_SKIPPED "${PF_REQ[@]}"
pf_expect SIM_SKIPPED PASS - 0
[[ "$(pf_check SIMULATOR)" == "SKIPPED" ]] || pf_fail "SIM_SKIPPED_CHECK_$(pf_check SIMULATOR)"
[[ "$(pf_check_reason SIMULATOR)" == "NOT_SELECTED" ]] || pf_fail "SIM_SKIPPED_REASON"
[[ -z "$(pf_value SIMULATOR_STATE)" ]] || pf_fail "SIM_SKIPPED_STATE_PRINTED"
[[ -z "$(pf_value SIMULATOR_OPERATIONAL)" ]] || pf_fail "SIM_SKIPPED_OPERATIONAL_PRINTED"
[[ "$(pf_tool_calls)" -eq 6 ]] || pf_fail "SIM_SKIPPED_TOOL_CALLS_$(pf_tool_calls)"
! grep -q 'simctl list' "$PF_LOG" || pf_fail "SIM_SKIPPED_LISTED"

# SKIPPED alone is never a PASS: the contract aggregate agrees.
[[ "$(cbs_flutter_qual_aggregate SKIPPED)" == "NOT_RUN" ]] || pf_fail "SKIPPED_ALONE_IS_NOT_RUN"
[[ "$(cbs_flutter_qual_aggregate SKIPPED NOT_RUN PASS)" == "NOT_RUN" ]] || pf_fail "NOT_RUN_WITH_PASS"

pf_pass "SIMULATOR_PASS_AND_SKIPPED"

# ---------------------------------------------------------------- 3. request errors: nothing runs

# params_blocked <label> <reason> <rc> <argument...>
params_blocked() {
    local label="$1"
    local reason="$2"
    local rc="$3"
    local name

    shift 3

    pf_run "$label" "$@"
    pf_expect "$label" BLOCKED "$reason" "$rc"
    [[ "$(pf_check PARAMETERS)" == "BLOCKED" ]] || pf_fail "${label}_PARAMETERS_$(pf_check PARAMETERS)"
    [[ "$(pf_check_reason PARAMETERS)" == "$reason" ]] || pf_fail "${label}_PARAMETERS_REASON"

    for name in $ALL_CHECKS; do
        [[ "$name" == "PARAMETERS" ]] && continue
        [[ "$(pf_check "$name")" == "NOT_RUN" ]] || pf_fail "${label}_${name}_RAN_$(pf_check "$name")"
    done

    [[ "$(pf_tool_calls)" -eq 0 ]] || pf_fail "${label}_TOOL_CALLED"
    [[ "$(pf_git_calls)" -eq 0 ]] || pf_fail "${label}_GIT_CALLED"
    [[ -z "$(pf_value COMMIT_OBSERVED)" ]] || pf_fail "${label}_COMMIT_OBSERVED_PRINTED"
}

pf_req_reset iso-pass

params_blocked NO_ARGUMENT USAGE 64
[[ -z "$(pf_value REJECTED_KEY)" ]] || pf_fail "NO_ARGUMENT_KEY"

pf_req_reset iso-pass
pf_req_unset timeout_seconds
params_blocked MISSING_KEY INPUT_INVALID 121 "${PF_REQ[@]}"
[[ "$(pf_value REJECTED_KEY)" == "timeout_seconds" ]] || pf_fail "MISSING_KEY_NAME"

pf_req_reset iso-pass
pf_req_set contract_version 2
params_blocked VERSION CONTRACT_VERSION_UNSUPPORTED 120 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set extra_option 1
params_blocked UNKNOWN_KEY ARGUMENT_REFUSED 123 "${PF_REQ[@]}"

pf_req_reset iso-pass
params_blocked BARE_OPTION ARGUMENT_REFUSED 123 "${PF_REQ[@]}" "--dart-define=A=b"
params_blocked BARE_COMMAND ARGUMENT_REFUSED 123 "${PF_REQ[@]}" "flutter"
params_blocked BARE_PUB_GET ARGUMENT_REFUSED 123 "${PF_REQ[@]}" "pub get"

pf_req_reset iso-pass
pf_req_set api_token "abc"
params_blocked SECRET_KEY SECRET_REFUSED 125 "${PF_REQ[@]}"
[[ "$(pf_value REJECTED_KEY)" == "api_token" ]] || pf_fail "SECRET_KEY_NAME"

pf_req_reset iso-pass
pf_req_set expected_origin "https://user:s3cr3t@example.invalid/x.git"
params_blocked SECRET_ORIGIN SECRET_REFUSED 125 "${PF_REQ[@]}"
if printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F "s3cr3t" >/dev/null; then pf_fail "SECRET_ORIGIN_ECHOED"; fi

pf_req_reset iso-pass
pf_req_set source_repository "relative/path"
params_blocked PATH_RELATIVE PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set evidence_root "$ISO_ROOT"
params_blocked ROOTS_OVERLAP PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set actions "report"
params_blocked ACTIONS_WITHOUT_PREFLIGHT ACTION_NOT_ALLOWED 122 "${PF_REQ[@]}"
[[ "$(pf_value REJECTED_KEY)" == "actions" ]] || pf_fail "ACTIONS_KEY"

pf_req_reset iso-pass
pf_req_set actions "preflight,bogus"
params_blocked ACTIONS_UNKNOWN ACTION_NOT_ALLOWED 122 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set actions "PREFLIGHT"
params_blocked ACTIONS_UPPERCASE ACTION_NOT_ALLOWED 122 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set actions "analyze"
params_blocked MUTATING_WITHOUT_PREFLIGHT INPUT_INVALID 121 "${PF_REQ[@]}"

pf_req_reset iso-pass
params_blocked DUPLICATE_KEY INPUT_INVALID 121 "${PF_REQ[@]}" "commit=$C1"

pf_req_reset iso-pass
pf_req_set commit "abc123"
params_blocked COMMIT_SHORT INPUT_INVALID 121 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set commit "$(printf '%s' "$C2" | tr 'a-f' 'A-F')"
params_blocked COMMIT_UPPERCASE INPUT_INVALID 121 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set commit "HEAD"
params_blocked COMMIT_REF INPUT_INVALID 121 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set timeout_seconds 0
params_blocked TIMEOUT_ZERO INPUT_INVALID 121 "${PF_REQ[@]}"
pf_req_set timeout_seconds 3601
params_blocked TIMEOUT_TOO_LARGE INPUT_INVALID 121 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set simulator_udid "booted"
params_blocked UDID_ALIAS INPUT_INVALID 121 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set target "android"
params_blocked TARGET INPUT_INVALID 121 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set simulator_policy "create_if_missing"
params_blocked SIMULATOR_POLICY INPUT_INVALID 121 "${PF_REQ[@]}"

pf_req_reset iso-pass
pf_req_set isolation_id "../escape"
params_blocked ISOLATION_ID_TRAVERSAL INPUT_INVALID 121 "${PF_REQ[@]}"

# More than the allowed number of entries.
pf_req_reset iso-pass
MANY=("${PF_REQ[@]}")
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do MANY[${#MANY[@]}]="extra_$n=1"; done
params_blocked TOO_MANY_ENTRIES INPUT_INVALID 121 "${MANY[@]}"

pf_pass "REQUEST_ERRORS"

# ---------------------------------------------------------------- 4. isolation: ownership, commit, state

# isolation_blocked <label> <isolation reason> <failed check> <argument...>
isolation_blocked() {
    local label="$1"
    local reason="$2"
    local failed="$3"
    local name

    shift 3

    pf_run "$label" "$@"
    pf_expect "$label" BLOCKED ISOLATION_REJECTED 126

    [[ "$(pf_value ISOLATION_REASON)" == "$reason" ]] ||
        pf_fail "${label}_ISOLATION_REASON_EXPECTED_${reason}_GOT_$(pf_value ISOLATION_REASON)"
    [[ "$(pf_check "$failed")" == "BLOCKED" ]] || pf_fail "${label}_${failed}_$(pf_check "$failed")"
    [[ "$(pf_check_reason "$failed")" == "ISOLATION_REJECTED" ]] || pf_fail "${label}_${failed}_REASON"
    [[ "$(pf_check PARAMETERS)" == "PASS" ]] || pf_fail "${label}_PARAMETERS"

    # Nothing of the toolchain runs against a checkout that was refused.
    assert_not_run "$label" $TOOLCHAIN_CHECKS
    [[ "$(pf_tool_calls)" -eq 0 ]] || pf_fail "${label}_TOOL_CALLED"
    pf_assert_git_readonly "$label"

    # A refusal is never presented as a pass.
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" != "PASS" ]] || pf_fail "${label}_PASS"
}

# Another commit than the one of the checkout.
pf_req_reset iso-pass
pf_req_set commit "$C1"
isolation_blocked COMMIT_OTHER COMMIT_MISMATCH COMMIT "${PF_REQ[@]}"
[[ "$(pf_check OWNERSHIP)" == "PASS" ]] || pf_fail "COMMIT_OTHER_OWNERSHIP"
[[ "$(pf_check DETACHED_HEAD)" == "PASS" ]] || pf_fail "COMMIT_OTHER_DETACHED"
[[ "$(pf_check GIT_STATE)" == "PASS" ]] || pf_fail "COMMIT_OTHER_GIT_STATE"
[[ "$(pf_check ORIGIN)" == "NOT_RUN" ]] || pf_fail "COMMIT_OTHER_ORIGIN"
[[ "$(pf_value COMMIT_OBSERVED)" == "$C2" ]] || pf_fail "COMMIT_OTHER_OBSERVED"

pf_req_set commit "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
isolation_blocked COMMIT_UNKNOWN COMMIT_MISMATCH COMMIT "${PF_REQ[@]}"

# Another origin than the expected one.
pf_req_reset iso-pass
pf_req_set expected_origin "https://example.invalid/cbs/other.git"
isolation_blocked ORIGIN_OTHER ORIGIN_MISMATCH ORIGIN "${PF_REQ[@]}"
[[ "$(pf_check COMMIT)" == "PASS" ]] || pf_fail "ORIGIN_OTHER_COMMIT"

# Isolation id the manager never created.
pf_req_reset ghost-isolation
isolation_blocked ID_UNKNOWN PROOF_MISSING OWNERSHIP "${PF_REQ[@]}"

# A worktree made by hand: Git knows it, CBS never created it (no proof).
git -C "$SOURCE" worktree add --detach "$ISO_ROOT/manual-wt" "$C2" >/dev/null 2>&1
pf_req_reset manual-wt
isolation_blocked NOT_OWNED PROOF_MISSING OWNERSHIP "${PF_REQ[@]}"

# A root that the operator never authorized.
mkdir "$TMP/unauthorized-root"
pf_req_reset iso-pass
pf_req_set isolation_root "$TMP/unauthorized-root"
isolation_blocked ROOT_UNAUTHORIZED ROOT_NOT_AUTHORIZED OWNERSHIP "${PF_REQ[@]}"

# Tampered proof.
pf_new_isolation iso-tamper
PROOF="$ISO_ROOT/.cbs-isolation/iso-tamper.proof"
sed 's/^CBS_ISOLATION_CREATED_BY=CBS$/CBS_ISOLATION_CREATED_BY=SOMEONE/' "$PROOF" > "$PROOF.new"
mv "$PROOF.new" "$PROOF"
pf_req_reset iso-tamper
isolation_blocked PROOF_TAMPERED PROOF_MISMATCH_CREATED_BY OWNERSHIP "${PF_REQ[@]}"

# Proof writable by others.
pf_new_isolation iso-insecure
chmod 666 "$ISO_ROOT/.cbs-isolation/iso-insecure.proof"
pf_req_reset iso-insecure
isolation_blocked PROOF_INSECURE PROOF_INSECURE OWNERSHIP "${PF_REQ[@]}"

# Modified checkout (tracked file).
pf_new_isolation iso-dirty
printf '%s\n' "local change" >> "$ISO_ROOT/iso-dirty/file.txt"
pf_req_reset iso-dirty
isolation_blocked DIRTY_TRACKED WORKTREE_DIRTY GIT_STATE "${PF_REQ[@]}"

# Untracked file in the checkout.
pf_new_isolation iso-untracked
printf '%s\n' "stray" > "$ISO_ROOT/iso-untracked/stray.txt"
pf_req_reset iso-untracked
isolation_blocked DIRTY_UNTRACKED WORKTREE_DIRTY GIT_STATE "${PF_REQ[@]}"

# Attached HEAD.
pf_new_isolation iso-attached
git -C "$ISO_ROOT/iso-attached" checkout -q -b attached-branch
pf_req_reset iso-attached
isolation_blocked ATTACHED NOT_DETACHED DETACHED_HEAD "${PF_REQ[@]}"

# HEAD moved after the creation: not the exact commit any more.
pf_new_isolation iso-moved
git -C "$ISO_ROOT/iso-moved" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m moved
pf_req_reset iso-moved
isolation_blocked HEAD_MOVED HEAD_MISMATCH COMMIT "${PF_REQ[@]}"

# Origin of the source changed after the creation.
pf_new_isolation iso-origin
git -C "$SOURCE" remote set-url origin "https://example.invalid/cbs/changed.git"
pf_req_reset iso-origin
isolation_blocked SOURCE_ORIGIN_CHANGED ORIGIN_MISMATCH ORIGIN "${PF_REQ[@]}"
git -C "$SOURCE" remote set-url origin "$ISO_ORIGIN"

# Evidence root that is not a plain directory.
ln -s "$TMP" "$TMP/evidence-link"
pf_req_reset iso-pass
pf_req_set evidence_root "$TMP/evidence-link"
pf_run EVIDENCE_LINK "${PF_REQ[@]}"
pf_expect EVIDENCE_LINK BLOCKED PATH_NOT_ALLOWED 124
[[ "$(pf_check EVIDENCE_ROOT)" == "BLOCKED" ]] || pf_fail "EVIDENCE_LINK_CHECK"
assert_not_run EVIDENCE_LINK GIT_CONFIG_GUARD $ISOLATION_CHECKS $TOOLCHAIN_CHECKS
[[ "$(pf_git_calls)" -eq 0 && "$(pf_tool_calls)" -eq 0 ]] || pf_fail "EVIDENCE_LINK_RAN"

# The state the executor looked at is still the one left by the tests above.
pf_req_reset iso-pass
pf_run STILL_PASS "${PF_REQ[@]}"
pf_expect STILL_PASS PASS - 0

pf_pass "ISOLATION"

# ---------------------------------------------------------------- 5. toolchain and simulator

pf_new_isolation iso-tools
TOOLS_BASE=(iso-tools)

# tool_case <label> <RESULT> <REASON> <rc> <check> : the request of iso-tools is run.
tool_case() {
    local label="$1"

    pf_req_reset iso-tools
    pf_run "$label" "${PF_REQ[@]}"
    pf_expect "$label" "$2" "$3" "$4"
    [[ "$(pf_check PARAMETERS)" == "PASS" ]] || pf_fail "${label}_PARAMETERS"
    [[ "$(pf_check OWNERSHIP)" == "PASS" ]] || pf_fail "${label}_OWNERSHIP"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" != "PASS" ]] || pf_fail "${label}_PASSED"
    pf_assert_tools_allowed "$label"
    pf_assert_git_readonly "$label"

    # The check that carries the refusal carries the reason of the answer.
    if [[ -n "${5:-}" ]]; then
        [[ "$(pf_check "$5")" == "$(cbs_flutter_qual_result_for_reason "$3")" ]] || pf_fail "${label}_CHECK_${5}_$(pf_check "$5")"
        [[ "$(pf_check_reason "$5")" == "$3" ]] || pf_fail "${label}_CHECK_${5}_REASON_$(pf_check_reason "$5")"
    fi
}

# --- tool absent from PATH

pf_modes_reset
PF_MISSING="flutter"
tool_case FLUTTER_ABSENT BLOCKED TOOL_UNAVAILABLE 127 FLUTTER
[[ "$(pf_check DART)" == "PASS" && "$(pf_check XCODE)" == "PASS" ]] || pf_fail "FLUTTER_ABSENT_OTHERS"
! grep -q '^flutter' "$PF_LOG" || pf_fail "FLUTTER_ABSENT_CALLED"
[[ -z "$(pf_value FLUTTER_VERSION)" ]] || pf_fail "FLUTTER_ABSENT_VERSION"

pf_modes_reset
PF_MISSING="dart"
tool_case DART_ABSENT BLOCKED TOOL_UNAVAILABLE 127 DART

pf_modes_reset
PF_MISSING="xcodebuild"
tool_case XCODEBUILD_ABSENT BLOCKED TOOL_UNAVAILABLE 127 XCODE

# No xcrun: no SDK, no simctl, therefore no simulator observation.
pf_modes_reset
PF_MISSING="xcrun"
tool_case XCRUN_ABSENT BLOCKED TOOL_UNAVAILABLE 127 SDK_IPHONEOS
[[ "$(pf_check SDK_IPHONESIMULATOR)" == "BLOCKED" && "$(pf_check SIMCTL)" == "BLOCKED" ]] || pf_fail "XCRUN_ABSENT_CHECKS"
[[ "$(pf_check SIMULATOR)" == "NOT_RUN" ]] || pf_fail "XCRUN_ABSENT_SIMULATOR_$(pf_check SIMULATOR)"
[[ "$(pf_check_reason SIMULATOR)" == "NOT_EXECUTED" ]] || pf_fail "XCRUN_ABSENT_SIMULATOR_REASON"

# Everything absent.
pf_modes_reset
PF_MISSING="flutter dart xcodebuild xcrun"
tool_case ALL_ABSENT BLOCKED TOOL_UNAVAILABLE 127 FLUTTER
[[ "$(pf_tool_calls)" -eq 0 ]] || pf_fail "ALL_ABSENT_CALLS"

# --- versions

pf_modes_reset
SHIM_FLUTTER_VERSION="3.0.0"
export SHIM_FLUTTER_VERSION
tool_case FLUTTER_OTHER_VERSION BLOCKED TOOLCHAIN_INCOMPATIBLE 128 FLUTTER
[[ "$(pf_value FLUTTER_VERSION)" == "3.0.0" ]] || pf_fail "FLUTTER_OTHER_VERSION_REPORTED"

pf_modes_reset
export SHIM_FLUTTER_MODE=garbage
tool_case FLUTTER_GARBAGE BLOCKED TOOLCHAIN_INCOMPATIBLE 128 FLUTTER
[[ -z "$(pf_value FLUTTER_VERSION)" ]] || pf_fail "FLUTTER_GARBAGE_VERSION"

pf_modes_reset
export SHIM_DART_MODE=garbage
tool_case DART_GARBAGE BLOCKED TOOLCHAIN_INCOMPATIBLE 128 DART

pf_modes_reset
export SHIM_XCODE_VERSION="14.3.1"
tool_case XCODE_OLD BLOCKED TOOLCHAIN_INCOMPATIBLE 128 XCODE
[[ "$(pf_value XCODE_VERSION)" == "14.3.1" ]] || pf_fail "XCODE_OLD_REPORTED"

pf_modes_reset
export SHIM_XCODE_MODE=garbage
tool_case XCODE_GARBAGE BLOCKED TOOLCHAIN_INCOMPATIBLE 128 XCODE

# Xcode: the major version is compared, as the Xcode provider does.
pf_modes_reset
export SHIM_XCODE_VERSION="$PF_XCODE_MINIMUM.0"
pf_req_reset iso-tools
pf_run XCODE_MINIMUM "${PF_REQ[@]}"
pf_expect XCODE_MINIMUM PASS - 0
export SHIM_XCODE_VERSION="$((PF_XCODE_MINIMUM + 1)).2"
pf_run XCODE_NEWER "${PF_REQ[@]}"
pf_expect XCODE_NEWER PASS - 0

# --- SDK

pf_modes_reset
export SHIM_SDK_IPHONEOS_MODE=missing
tool_case SDK_IPHONEOS_MISSING BLOCKED TOOLCHAIN_INCOMPATIBLE 128 SDK_IPHONEOS
[[ "$(pf_check SDK_IPHONESIMULATOR)" == "PASS" ]] || pf_fail "SDK_IPHONEOS_MISSING_OTHER"

pf_modes_reset
export SHIM_SDK_IPHONEOS_MODE=garbage
tool_case SDK_IPHONEOS_GARBAGE BLOCKED TOOLCHAIN_INCOMPATIBLE 128 SDK_IPHONEOS

pf_modes_reset
export SHIM_SDK_IPHONESIMULATOR_MODE=missing
tool_case SDK_SIMULATOR_MISSING BLOCKED TOOLCHAIN_INCOMPATIBLE 128 SDK_IPHONESIMULATOR

# --- simctl

pf_modes_reset
export SHIM_SIMCTL_MODE=missing
tool_case SIMCTL_MISSING BLOCKED TOOL_UNAVAILABLE 127 SIMCTL
[[ "$(pf_check SIMULATOR)" == "NOT_RUN" ]] || pf_fail "SIMCTL_MISSING_SIMULATOR_$(pf_check SIMULATOR)"
! grep -q 'simctl list' "$PF_LOG" || pf_fail "SIMCTL_MISSING_LISTED"

# --- simulator

pf_modes_reset
pf_req_reset iso-tools
pf_req_set simulator_udid "$PF_UDID_ABSENT"
pf_run SIM_ABSENT "${PF_REQ[@]}"
pf_expect SIM_ABSENT BLOCKED SIMULATOR_UNAVAILABLE 129
[[ "$(pf_check SIMULATOR)" == "BLOCKED" && "$(pf_check SIMCTL)" == "PASS" ]] || pf_fail "SIM_ABSENT_CHECKS"
[[ -z "$(pf_value SIMULATOR_STATE)" && -z "$(pf_value SIMULATOR_OPERATIONAL)" ]] || pf_fail "SIM_ABSENT_STATE_PRINTED"

pf_req_set simulator_udid "$PF_UDID_UNAVAILABLE"
pf_run SIM_UNAVAILABLE "${PF_REQ[@]}"
pf_expect SIM_UNAVAILABLE BLOCKED SIMULATOR_UNAVAILABLE 129

pf_req_set simulator_udid "$PF_UDID_TVOS"
pf_run SIM_TVOS "${PF_REQ[@]}"
pf_expect SIM_TVOS BLOCKED SIMULATOR_UNAVAILABLE 129

# A device that exists only in the name of another one is not found.
cat > "$PF_LIST" <<EOF
-- iOS 17.5 --
    iPhone ($PF_UDID_ABSENT-extra) (Shutdown)
EOF
pf_req_set simulator_udid "$PF_UDID_ABSENT"
pf_run SIM_PREFIX "${PF_REQ[@]}"
pf_expect SIM_PREFIX BLOCKED SIMULATOR_UNAVAILABLE 129
pf_devices_default

# Transient state is observed as such.
cat > "$PF_LIST" <<EOF
-- iOS 17.5 --
    iPhone ($PF_UDID_SHUTDOWN) (Shutting Down)
EOF
pf_req_set simulator_udid "$PF_UDID_SHUTDOWN"
pf_run SIM_TRANSIENT "${PF_REQ[@]}"
pf_expect SIM_TRANSIENT PASS - 0
[[ "$(pf_value SIMULATOR_STATE)" == "TRANSITIONAL" ]] || pf_fail "SIM_TRANSIENT_STATE"
pf_devices_default

# The only simctl call is the read-only listing.
grep -q '^xcrun simctl list devices$' "$PF_LOG" || pf_fail "SIM_LIST_CALL"
! grep -Eq 'simctl (boot|create|erase|shutdown|install|delete|launch|spawn|clone|rename|upgrade)' "$PF_LOG" || pf_fail "SIM_MUTATING_CALL"

pf_pass "TOOLCHAIN_BLOCKED"

# --- FAIL: a probe ran and went wrong

pf_modes_reset
export SHIM_FLUTTER_MODE=fail SHIM_FLUTTER_RC=7
tool_case FLUTTER_FAILS FAIL COMMAND_FAILED 130 FLUTTER
[[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "7" ]] || pf_fail "FLUTTER_FAILS_TOOL_RC"

pf_modes_reset
export SHIM_DART_MODE=fail SHIM_DART_RC=4
tool_case DART_FAILS FAIL COMMAND_FAILED 130 DART
[[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "4" ]] || pf_fail "DART_FAILS_TOOL_RC"

pf_modes_reset
export SHIM_XCODE_MODE=fail
tool_case XCODE_FAILS FAIL COMMAND_FAILED 130 XCODE
[[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "1" ]] || pf_fail "XCODE_FAILS_TOOL_RC"

pf_modes_reset
export SHIM_SIMCTL_MODE=listfail
tool_case SIMCTL_LIST_FAILS FAIL COMMAND_FAILED 130 SIMULATOR
[[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "2" ]] || pf_fail "SIMCTL_LIST_FAILS_TOOL_RC"

# FAIL wins over BLOCKED: flutter absent (BLOCKED) and dart failing (FAIL).
pf_modes_reset
PF_MISSING="flutter"
export SHIM_DART_MODE=fail SHIM_DART_RC=4
tool_case FAIL_OVER_BLOCKED FAIL COMMAND_FAILED 130 DART
[[ "$(pf_check FLUTTER)" == "BLOCKED" ]] || pf_fail "FAIL_OVER_BLOCKED_FLUTTER_HIDDEN"
[[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "4" ]] || pf_fail "FAIL_OVER_BLOCKED_TOOL_RC"

# Without FAIL, the first BLOCKED reason (in check order) is the answer.
pf_modes_reset
PF_MISSING="flutter"
pf_req_reset iso-tools
pf_req_set simulator_udid "$PF_UDID_ABSENT"
pf_run FIRST_BLOCKED "${PF_REQ[@]}"
pf_expect FIRST_BLOCKED BLOCKED TOOL_UNAVAILABLE 127
[[ "$(pf_check SIMULATOR)" == "BLOCKED" ]] || pf_fail "FIRST_BLOCKED_SIMULATOR"

# TOOL_RC is never reported for a refusal.
pf_modes_reset
PF_MISSING="flutter"
tool_case NO_TOOL_RC_ON_BLOCKED BLOCKED TOOL_UNAVAILABLE 127 FLUTTER
[[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" ]] || pf_fail "TOOL_RC_ON_BLOCKED"

pf_pass "TOOLCHAIN_FAIL"

# --- timeout: the whole process group is stopped, the answer is bounded

pf_modes_reset
export SHIM_FLUTTER_MODE=hang
pf_req_reset iso-tools
pf_req_set timeout_seconds 1
START=$SECONDS
pf_run TIMEOUT "${PF_REQ[@]}"
ELAPSED=$((SECONDS - START))
pf_expect TIMEOUT FAIL TIMEOUT 131
[[ "$(pf_check FLUTTER)" == "FAIL" && "$(pf_check_reason FLUTTER)" == "TIMEOUT" ]] || pf_fail "TIMEOUT_CHECK"
[[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" ]] || pf_fail "TIMEOUT_TOOL_RC"
[[ "$ELAPSED" -lt 15 ]] || pf_fail "TIMEOUT_NOT_BOUNDED_${ELAPSED}s"
[[ -s "$PF_HANG_PID" ]] || pf_fail "TIMEOUT_NO_HANG_PID"
sleep 1
if kill -0 "$(cat "$PF_HANG_PID")" 2>/dev/null; then
    kill -KILL "$(cat "$PF_HANG_PID")" 2>/dev/null || true
    pf_fail "TIMEOUT_CHILD_SURVIVED"
fi
[[ "$(pf_check DART)" == "PASS" ]] || pf_fail "TIMEOUT_OTHERS_STILL_OBSERVED"

pf_modes_reset
export SHIM_SIMCTL_MODE=hang
pf_req_reset iso-tools
pf_req_set timeout_seconds 1
pf_run TIMEOUT_SIMCTL "${PF_REQ[@]}"
pf_expect TIMEOUT_SIMCTL FAIL TIMEOUT 131
[[ "$(pf_check SIMULATOR)" == "FAIL" ]] || pf_fail "TIMEOUT_SIMCTL_CHECK"
sleep 1
if kill -0 "$(cat "$PF_HANG_PID")" 2>/dev/null; then
    kill -KILL "$(cat "$PF_HANG_PID")" 2>/dev/null || true
    pf_fail "TIMEOUT_SIMCTL_CHILD_SURVIVED"
fi

pf_pass "TIMEOUT"

# ---------------------------------------------------------------- 5b. bounded runner (_cbs_flutter_qual_pf_run)

# The runner alone, with commands written here (no Flutter, no Xcode). Marker
# limits (733, 735) appear in the command line of every process the runner
# starts (its shell, its timer, whatever the implementation forks): any such
# process left after the call is a residue. "sleep 86400" is the timer once it
# has fired, compared with its count before the test.
RUNNER_DIR="$TMP/runner-cmds"
mkdir "$RUNNER_DIR"
RESIDUE_733='^ *[0-9]+ .*[[:space:]]733([[:space:]]|$)'
RESIDUE_735='^ *[0-9]+ .*[[:space:]]735([[:space:]]|$)'
TIMER_BASE="$(pf_ps_count 'sleep 86400$')"

RUNNER_NL="
"

write_cmd() {
    printf '#!/bin/sh\n%s\n' "$2" > "$RUNNER_DIR/$1"
    chmod 755 "$RUNNER_DIR/$1"
}

write_cmd exit0 'exit 0'
write_cmd slow 'sleep 2; echo done'
write_cmd fail 'echo out; echo err >&2; exit 7'
write_cmd hang "sleep 30 &
echo \$! > \"$RUNNER_DIR/hang.pid\"
wait"
write_cmd ignore "trap '' TERM
sleep 30 &
echo \$! > \"$RUNNER_DIR/ignore.pid\"
while :; do sleep 1; done"
write_cmd straggler "sleep 30 &
echo \$! > \"$RUNNER_DIR/straggler.pid\"
echo x
exit 0"
write_cmd late 'sleep 5; echo late'
write_cmd exit143 'exit 143'
write_cmd exit130 'exit 130'
write_cmd selfterm 'kill -TERM $$; sleep 5'
write_cmd spoof 'echo "CBS_PF_RUN 0 1"; echo "CBS_PF_RUN 0 1"; exit 3'

# runner_gone <label> <pid file>: the process of the file no longer runs.
runner_gone() {
    [[ -s "$2" ]] || pf_fail "${1}_NO_PID_FILE"
    pf_pid_gone "$(cat "$2")" 3 || {
        kill -KILL "$(cat "$2")" 2>/dev/null || true
        pf_fail "${1}_PROCESS_SURVIVED"
    }
}

# runner_clean <label> <marker regex>: neither a supervisor nor a timer is left.
runner_clean() {
    [[ "$(pf_ps_count "$2")" -eq 0 ]] || pf_fail "${1}_RESIDUAL_PROCESS"
    [[ "$(pf_ps_count 'sleep 86400$')" -le "$TIMER_BASE" ]] || pf_fail "${1}_RESIDUAL_TIMER"
}

# immediate end: the answer is immediate and nothing is left behind (the timer
# does not outlive the command, not even for the length of its next poll).
pf_modes_reset
pf_fn_run 733 "$RUNNER_DIR/exit0"
[[ "$PF_FN_RC" == "0" && "$PF_FN_TIMED_OUT" == "0" && -z "$PF_FN_OUT" ]] || pf_fail "RUNNER_IMMEDIATE_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
[[ "$PF_FN_ELAPSED" -le 3 ]] || pf_fail "RUNNER_IMMEDIATE_SLOW_${PF_FN_ELAPSED}s"
runner_clean RUNNER_IMMEDIATE "$RESIDUE_733"
sleep 2
runner_clean RUNNER_IMMEDIATE_LATER "$RESIDUE_733"

# slow command, well inside the limit: complete output, normal status.
pf_fn_run 733 "$RUNNER_DIR/slow"
[[ "$PF_FN_RC" == "0" && "$PF_FN_TIMED_OUT" == "0" && "$PF_FN_OUT" == "done" ]] || pf_fail "RUNNER_SLOW_${PF_FN_RC}_${PF_FN_TIMED_OUT}_${PF_FN_OUT}"
[[ "$PF_FN_ELAPSED" -ge 2 && "$PF_FN_ELAPSED" -le 8 ]] || pf_fail "RUNNER_SLOW_ELAPSED_${PF_FN_ELAPSED}s"
runner_clean RUNNER_SLOW "$RESIDUE_733"

# failing command: its status and its merged output are kept, no timeout.
pf_fn_run 733 "$RUNNER_DIR/fail"
[[ "$PF_FN_RC" == "7" && "$PF_FN_TIMED_OUT" == "0" ]] || pf_fail "RUNNER_FAIL_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
[[ "$PF_FN_OUT" == "out${RUNNER_NL}err" ]] || pf_fail "RUNNER_FAIL_OUTPUT"
runner_clean RUNNER_FAIL "$RESIDUE_733"

# a status that looks like a signal is not a timeout when the timer did not fire.
pf_fn_run 733 "$RUNNER_DIR/exit143"
[[ "$PF_FN_RC" == "143" && "$PF_FN_TIMED_OUT" == "0" ]] || pf_fail "RUNNER_STATUS_143_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
pf_fn_run 733 "$RUNNER_DIR/exit130"
[[ "$PF_FN_RC" == "130" && "$PF_FN_TIMED_OUT" == "0" ]] || pf_fail "RUNNER_STATUS_130_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
pf_fn_run 733 "$RUNNER_DIR/selfterm"
[[ "$PF_FN_RC" == "143" && "$PF_FN_TIMED_OUT" == "0" ]] || pf_fail "RUNNER_SELF_TERM_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
runner_clean RUNNER_STATUS "$RESIDUE_733"

# the trailer belongs to the runner: the output of the command cannot forge it.
pf_fn_run 733 "$RUNNER_DIR/spoof"
[[ "$PF_FN_RC" == "3" && "$PF_FN_TIMED_OUT" == "0" ]] || pf_fail "RUNNER_SPOOF_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
runner_clean RUNNER_SPOOF "$RESIDUE_733"

# a command that outlives its limit is stopped, the group included, and the
# answer comes after the limit, not before.
rm -f "$RUNNER_DIR/hang.pid"
pf_fn_run 1 "$RUNNER_DIR/hang"
[[ "$PF_FN_TIMED_OUT" == "1" && "$PF_FN_RC" -ge 128 ]] || pf_fail "RUNNER_TIMEOUT_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
[[ "$PF_FN_ELAPSED" -ge 1 && "$PF_FN_ELAPSED" -le 8 ]] || pf_fail "RUNNER_TIMEOUT_ELAPSED_${PF_FN_ELAPSED}s"
runner_gone RUNNER_TIMEOUT "$RUNNER_DIR/hang.pid"
runner_clean RUNNER_TIMEOUT "$RESIDUE_733"

# the limit is respected for a command that is not a hang either.
pf_fn_run 2 "$RUNNER_DIR/late"
[[ "$PF_FN_TIMED_OUT" == "1" && -z "$PF_FN_OUT" ]] || pf_fail "RUNNER_LATE_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
[[ "$PF_FN_ELAPSED" -ge 2 && "$PF_FN_ELAPSED" -le 8 ]] || pf_fail "RUNNER_LATE_ELAPSED_${PF_FN_ELAPSED}s"

# a command that ignores TERM is killed (KILL), with what it started.
rm -f "$RUNNER_DIR/ignore.pid"
pf_fn_run 1 "$RUNNER_DIR/ignore"
[[ "$PF_FN_TIMED_OUT" == "1" && "$PF_FN_RC" == "137" ]] || pf_fail "RUNNER_IGNORE_TERM_${PF_FN_RC}_${PF_FN_TIMED_OUT}"
[[ "$PF_FN_ELAPSED" -le 10 ]] || pf_fail "RUNNER_IGNORE_TERM_ELAPSED_${PF_FN_ELAPSED}s"
runner_gone RUNNER_IGNORE_TERM "$RUNNER_DIR/ignore.pid"
runner_clean RUNNER_IGNORE_TERM "$RESIDUE_733"

# a process left behind by a command that ended normally is removed, and does
# not hold the answer (it would keep the output pipe open for 30 seconds).
rm -f "$RUNNER_DIR/straggler.pid"
pf_fn_run 733 "$RUNNER_DIR/straggler"
[[ "$PF_FN_RC" == "0" && "$PF_FN_TIMED_OUT" == "0" && "$PF_FN_OUT" == "x" ]] || pf_fail "RUNNER_STRAGGLER_${PF_FN_RC}_${PF_FN_TIMED_OUT}_${PF_FN_OUT}"
[[ "$PF_FN_ELAPSED" -le 10 ]] || pf_fail "RUNNER_STRAGGLER_HELD_THE_ANSWER_${PF_FN_ELAPSED}s"
runner_gone RUNNER_STRAGGLER "$RUNNER_DIR/straggler.pid"
runner_clean RUNNER_STRAGGLER "$RESIDUE_733"

# an interrupted supervisor takes the command, its group and its timer along:
# nothing is left running, and the answer is never a PASS (no trailer: 255).
rm -f "$RUNNER_DIR/hang.pid"
pf_make_view
(
    cd "$TMP" &&
        env PATH="$PF_VIEW:$PF_TOOLS" "$BASH" -c "$PF_FN_BODY" fn "$PREFLIGHT" 735 "$RUNNER_DIR/hang" >"$TMP/runner-interrupted.out" 2>/dev/null
) &
RUNNER_BG=$!

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    [[ -s "$RUNNER_DIR/hang.pid" ]] && break
    sleep 0.2 2>/dev/null || sleep 1
done

RUNNER_SUPERVISOR="$(pf_ps_lines 'cbs-preflight-supervisor 735 ' | awk '{ print $1 }' | head -n 1)"
[[ -n "$RUNNER_SUPERVISOR" ]] || { kill "$RUNNER_BG" 2>/dev/null || true; pf_fail "RUNNER_INTERRUPT_NO_SUPERVISOR"; }
kill -TERM "$RUNNER_SUPERVISOR"
wait "$RUNNER_BG" || true

runner_gone RUNNER_INTERRUPT "$RUNNER_DIR/hang.pid"
runner_clean RUNNER_INTERRUPT "$RESIDUE_735"
[[ "$(head -n 1 "$TMP/runner-interrupted.out")" == "255" ]] || pf_fail "RUNNER_INTERRUPT_NOT_FAIL_CLOSED_$(head -n 1 "$TMP/runner-interrupted.out")"

pf_pass "RUNNER"

# ---------------------------------------------------------------- 6. nothing executed that PREFLIGHT must not execute

pf_modes_reset
pf_req_reset iso-tools
iso_snapshot_source
pf_run FINAL_PASS "${PF_REQ[@]}"
pf_expect FINAL_PASS PASS - 0
pf_assert_tools_allowed FINAL

# The only flutter invocation is "--version": no pub get, no analyze, no build.
! grep -Eq '^flutter (pub|analyze|test|build|clean|upgrade|doctor|config|create|run|precache|devices|emulators)' "$PF_LOG" ||
    pf_fail "FLUTTER_ACTION_CALLED"
! grep -Eq '^dart (pub|run|analyze|test|compile|fix|format)' "$PF_LOG" || pf_fail "DART_ACTION_CALLED"
! grep -Eq '^xcodebuild (-?(build|archive|clean|test|install)|-runFirstLaunch|-license)' "$PF_LOG" || pf_fail "XCODEBUILD_ACTION_CALLED"

# The isolated checkout and the source repository are exactly as created.
[[ "$(git -C "$ISO_ROOT/iso-tools" rev-parse HEAD)" == "$C2" ]] || pf_fail "WORKTREE_HEAD_CHANGED"
[[ -z "$(git -C "$ISO_ROOT/iso-tools" status --porcelain)" ]] || pf_fail "WORKTREE_DIRTIED"
[[ ! -e "$ISO_ROOT/iso-tools/.dart_tool" && ! -e "$ISO_ROOT/iso-tools/build" && ! -e "$ISO_ROOT/iso-tools/pubspec.lock" ]] ||
    pf_fail "FLUTTER_ARTIFACT_CREATED"
iso_assert_source_untouched "FINAL_SOURCE"
[[ -f "$SOURCE/.local/note.txt" ]] || pf_fail "FINAL_UNTRACKED_LOST"

# The isolation manager still verifies the checkout: PREFLIGHT broke nothing.
iso_run verify iso-tools "$SOURCE" "$ISO_ROOT"
iso_expect_pass "FINAL_VERIFY"

pf_pass "NO_SIDE_EFFECT"

# ---------------------------------------------------------------- 7. portability

# bash -n, and no Bash 4+ feature or GNU-only usage in the executor.
bash -n "$PREFLIGHT" || pf_fail "SYNTAX"

if pf_code_matches "$PREFLIGHT" '(declare|local|typeset)[[:space:]]+-[A-Za-z]*[AnlurcgI]|mapfile|readarray|coproc|\|&|&>>|;;&|;&|\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,|\^|,)[^}]*\}|\$\{[A-Za-z_][A-Za-z0-9_]*@[A-Za-z]\}|\[\[[[:space:]]+-v[[:space:]]|shopt|globstar|printf[[:space:]]+[^|;]*%\(|\$EPOCHSECONDS|\$EPOCHREALTIME|\$BASHPID|wait[[:space:]]+-[nf]'; then
    pf_fail "BASH4_FEATURE"
fi

# Here-strings are written to a temporary file by Bash 3.2: none is used.
if pf_code_matches "$PREFLIGHT" '<<<'; then
    pf_fail "HERE_STRING"
fi

# GNU-only options.
if pf_code_matches "$PREFLIGHT" '(sed|grep|find|date|head|tail|ls|cp|mv|stat|readlink|xargs|sort)[[:space:]]+(-[A-Za-z]*[rzEi]\b|--[a-z]+)'; then
    pf_fail "GNU_OPTION"
fi

if pf_code_matches "$PREFLIGHT" '(^|[;&|({[:space:]])(timeout|gtimeout|flock|readlink|realpath|stat|seq|mktemp)[[:space:]]'; then
    pf_fail "NON_PORTABLE_TOOL"
fi

pf_pass "PORTABILITY_STATIC"

# Native Bash 3.2 (macOS): the whole PASS and a refusal run under it when one
# is available. Otherwise NOT_RUN: this is not a claim of macOS qualification.
BASH32=""
for candidate in /bin/bash /usr/bin/bash /usr/local/bin/bash; do
    if [[ -x "$candidate" ]] && [[ "$("$candidate" -c 'printf "%s%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null)" == "32" ]]; then
        BASH32="$candidate"
        break
    fi
done

if [[ -n "$BASH32" ]]; then
    pf_modes_reset
    PF_BASH="$BASH32"
    pf_req_reset iso-tools
    pf_run BASH32_PASS "${PF_REQ[@]}"
    pf_expect BASH32_PASS PASS - 0
    PF_MISSING="flutter"
    pf_run BASH32_BLOCKED "${PF_REQ[@]}"
    pf_expect BASH32_BLOCKED BLOCKED TOOL_UNAVAILABLE 127
    echo "${TEST_PREFIX}_BASH32=PASS"
else
    echo "${TEST_PREFIX}_BASH32=NOT_RUN"
fi

pf_modes_reset

echo "${TEST_PREFIX}_RESULT=PASS"
