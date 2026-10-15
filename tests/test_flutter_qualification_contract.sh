#!/usr/bin/env bash

# D04b-C.2b step 1: hermetic test of the Flutter/iOS qualification contract.
#
# Never runs Flutter, Dart, Xcode, simctl, Git or SSH: forbidden-tool shims
# are placed first in PATH and must remain uncalled. No worktree is created.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_CONTRACT"

source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"

fq_init
fq_shims_install
export PATH="$FQ_SHIM_BIN:$PATH"

# The contract is loaded together with the other CBS contracts: no readonly
# name may collide with an existing component.
for existing in \
    "$ROOT/cbs/worktree/contract.sh" \
    "$ROOT/cbs/worktree/isolation_contract.sh" \
    "$ROOT/cbs/remote/contract.sh" \
    "$ROOT/cbs/workspace/contract.sh" \
    "$ROOT/cbs/stack/contract.sh" \
    "$ROOT/cbs/toolchain/contract.sh" \
    "$ROOT/cbs/instance/contract.sh" \
    "$ROOT/cbs/platform/contract.sh" \
    "$ROOT/cbs/workstation/contract.sh"
do
    [[ -f "$existing" ]] || fq_fail "EXISTING_CONTRACT_MISSING_$existing"
    source "$existing"
done

source "$CONTRACT"

echo "${TEST_PREFIX}_COEXISTENCE=PASS"

# Loading twice is harmless.
source "$CONTRACT"
[[ "$CBS_FLUTTER_QUAL_CONTRACT_LOADED" == "1" ]] || fq_fail "LOADED_FLAG"

# Loading alone (without any other contract) works: the isolation contract is
# resolved from the contract's own location.
(
    cd "$FQ_TMP"
    env -i PATH="$PATH" bash -c \
        'source "$1" && cbs_flutter_qual_id_valid qual-1 && cbs_flutter_qual_commit_valid "$2"' \
        _ "$CONTRACT" "$FQ_COMMIT"
) || fq_fail "STANDALONE_LOAD"

echo "${TEST_PREFIX}_LOAD=PASS"

# ---------------------------------------------------------------- version

[[ "$CBS_FLUTTER_QUAL_CONTRACT_VERSION" == "1" ]] || fq_fail "VERSION"
[[ "$CBS_REMOTE_CONTRACT_VERSION" == "1" ]] || fq_fail "REMOTE_VERSION_CHANGED"
[[ "$CBS_ISOLATION_CONTRACT_VERSION" == "1" ]] || fq_fail "ISOLATION_VERSION_CHANGED"

echo "${TEST_PREFIX}_VERSION=PASS"

# ---------------------------------------------------------------- results

for result in PASS FAIL BLOCKED SKIPPED NOT_RUN; do
    cbs_flutter_qual_result_is_valid "$result" || fq_fail "RESULT_$result"
done

for result in pass Pass "" UNKNOWN SUCCESS OK "PASS " "PASS
FAIL"; do
    if cbs_flutter_qual_result_is_valid "$result"; then
        fq_fail "RESULT_INVALID_ACCEPTED"
    fi
done

[[ "$CBS_FLUTTER_QUAL_RESULT_SKIPPED" != "$CBS_FLUTTER_QUAL_RESULT_NOT_RUN" ]] ||
    fq_fail "SKIPPED_EQUALS_NOT_RUN"

echo "${TEST_PREFIX}_RESULTS=PASS"

# ---------------------------------------------------------------- operations and actions

for operation in PREFLIGHT ANALYZE TEST BUILD_IOS REPORT; do
    cbs_flutter_qual_operation_is_valid "$operation" || fq_fail "OPERATION_$operation"
done

for operation in preflight FLUTTER BUILD "" "TEST BUILD_IOS" RUN; do
    if cbs_flutter_qual_operation_is_valid "$operation"; then
        fq_fail "OPERATION_INVALID_ACCEPTED"
    fi
done

for action in preflight analyze test build_ios report; do
    cbs_flutter_qual_action_is_valid "$action" || fq_fail "ACTION_$action"
    operation="$(cbs_flutter_qual_operation_for_action "$action")" ||
        fq_fail "OPERATION_FOR_ACTION_$action"
    [[ "$(cbs_flutter_qual_action_for_operation "$operation")" == "$action" ]] ||
        fq_fail "ACTION_ROUNDTRIP_$action"
done

[[ "$(cbs_flutter_qual_operation_for_action preflight)" == "PREFLIGHT" ]] || fq_fail "MAP_PREFLIGHT"
[[ "$(cbs_flutter_qual_operation_for_action analyze)" == "ANALYZE" ]] || fq_fail "MAP_ANALYZE"
[[ "$(cbs_flutter_qual_operation_for_action test)" == "TEST" ]] || fq_fail "MAP_TEST"
[[ "$(cbs_flutter_qual_operation_for_action build_ios)" == "BUILD_IOS" ]] || fq_fail "MAP_BUILD_IOS"
[[ "$(cbs_flutter_qual_operation_for_action report)" == "REPORT" ]] || fq_fail "MAP_REPORT"

for action in PREFLIGHT Analyze build-ios build_android run shell exec "" "analyze test" \
    'analyze;id' 'analyze$(id)' "../analyze"; do
    if cbs_flutter_qual_action_is_valid "$action"; then
        fq_fail "ACTION_INVALID_ACCEPTED"
    fi

    fq_expect_rc 122 "VALIDATE_ACTION" cbs_flutter_qual_validate_action "$action"
done

fq_expect_rc 0 "VALIDATE_ACTION_OK" cbs_flutter_qual_validate_action analyze

# Mutating classification and preflight gate.
for operation in ANALYZE TEST BUILD_IOS; do
    cbs_flutter_qual_operation_is_mutating "$operation" || fq_fail "MUTATING_$operation"
done

for operation in PREFLIGHT REPORT; do
    if cbs_flutter_qual_operation_is_mutating "$operation"; then
        fq_fail "NOT_MUTATING_$operation"
    fi
done

for operation in ANALYZE TEST BUILD_IOS; do
    cbs_flutter_qual_gate_allows "$operation" PASS || fq_fail "GATE_PASS_$operation"

    for result in FAIL BLOCKED SKIPPED NOT_RUN "" pass UNKNOWN; do
        if cbs_flutter_qual_gate_allows "$operation" "$result"; then
            fq_fail "GATE_OPENED_${operation}_${result}"
        fi
    done
done

for result in PASS FAIL BLOCKED SKIPPED NOT_RUN; do
    cbs_flutter_qual_gate_allows PREFLIGHT "$result" || fq_fail "GATE_PREFLIGHT_$result"
    cbs_flutter_qual_gate_allows REPORT "$result" || fq_fail "GATE_REPORT_$result"
done

if cbs_flutter_qual_gate_allows FLUTTER PASS; then
    fq_fail "GATE_UNKNOWN_OPERATION"
fi

echo "${TEST_PREFIX}_OPERATIONS=PASS"

# ---------------------------------------------------------------- aggregation

expect_aggregate() {
    local expected="$1"
    local actual

    shift
    actual="$(cbs_flutter_qual_aggregate "$@")" || fq_fail "AGGREGATE_FAILED_$*"
    [[ "$actual" == "$expected" ]] || fq_fail "AGGREGATE_$*_EXPECTED_${expected}_GOT_$actual"
}

expect_aggregate PASS PASS PASS PASS
expect_aggregate PASS PASS SKIPPED
expect_aggregate PASS SKIPPED PASS SKIPPED
expect_aggregate FAIL PASS FAIL
expect_aggregate FAIL BLOCKED FAIL NOT_RUN
expect_aggregate BLOCKED PASS BLOCKED NOT_RUN
expect_aggregate NOT_RUN PASS NOT_RUN
expect_aggregate NOT_RUN SKIPPED SKIPPED
expect_aggregate NOT_RUN NOT_RUN

fq_expect_rc 1 "AGGREGATE_EMPTY" cbs_flutter_qual_aggregate
fq_expect_rc 1 "AGGREGATE_INVALID" cbs_flutter_qual_aggregate PASS bogus
fq_expect_rc 1 "AGGREGATE_LOWERCASE" cbs_flutter_qual_aggregate pass

echo "${TEST_PREFIX}_AGGREGATE=PASS"

# ---------------------------------------------------------------- reasons and return codes

EXPECTED_TABLE="
USAGE 64 BLOCKED
CONTRACT_VERSION_UNSUPPORTED 120 BLOCKED
INPUT_INVALID 121 BLOCKED
ACTION_NOT_ALLOWED 122 BLOCKED
ARGUMENT_REFUSED 123 BLOCKED
PATH_NOT_ALLOWED 124 BLOCKED
SECRET_REFUSED 125 BLOCKED
ISOLATION_REJECTED 126 BLOCKED
TOOL_UNAVAILABLE 127 BLOCKED
TOOLCHAIN_INCOMPATIBLE 128 BLOCKED
SIMULATOR_UNAVAILABLE 129 BLOCKED
COMMAND_FAILED 130 FAIL
TIMEOUT 131 FAIL
NETWORK_FAILURE 132 FAIL
LOG_LIMIT_EXCEEDED 133 FAIL
EVIDENCE_FAILURE 134 FAIL
NOT_EXECUTED 135 NOT_RUN
PREFLIGHT_NOT_PASSED 136 NOT_RUN
NOT_SELECTED 137 SKIPPED
"

SEEN_CODES=" "
REASON_COUNT=0

while read -r reason code class; do
    [[ -n "$reason" ]] || continue

    cbs_flutter_qual_reason_is_valid "$reason" || fq_fail "REASON_INVALID_$reason"
    [[ "$(cbs_flutter_qual_rc_for_reason "$reason")" == "$code" ]] || fq_fail "RC_$reason"
    [[ "$(cbs_flutter_qual_result_for_reason "$reason")" == "$class" ]] || fq_fail "CLASS_$reason"

    case "$SEEN_CODES" in
        *" $code "*) fq_fail "RC_DUPLICATE_$code" ;;
    esac

    SEEN_CODES="$SEEN_CODES$code "
    REASON_COUNT=$((REASON_COUNT + 1))
done <<< "$EXPECTED_TABLE"

[[ "$REASON_COUNT" -eq 19 ]] || fq_fail "REASON_COUNT_$REASON_COUNT"
[[ "$(cbs_flutter_qual_rc_for_reason "")" == "0" ]] || fq_fail "RC_SUCCESS"

for reason in "" bogus usage "USAGE " Input_Invalid; do
    if [[ -n "$reason" ]] && cbs_flutter_qual_reason_is_valid "$reason"; then
        fq_fail "REASON_INVALID_ACCEPTED"
    fi
done

# The constants carry the same values as the table.
[[ "$CBS_RC_FLUTTER_QUAL_USAGE" -eq 64 ]] || fq_fail "CONST_USAGE"
[[ "$CBS_RC_FLUTTER_QUAL_CONTRACT_VERSION_UNSUPPORTED" -eq 120 ]] || fq_fail "CONST_120"
[[ "$CBS_RC_FLUTTER_QUAL_INPUT_INVALID" -eq 121 ]] || fq_fail "CONST_121"
[[ "$CBS_RC_FLUTTER_QUAL_ACTION_NOT_ALLOWED" -eq 122 ]] || fq_fail "CONST_122"
[[ "$CBS_RC_FLUTTER_QUAL_ARGUMENT_REFUSED" -eq 123 ]] || fq_fail "CONST_123"
[[ "$CBS_RC_FLUTTER_QUAL_PATH_NOT_ALLOWED" -eq 124 ]] || fq_fail "CONST_124"
[[ "$CBS_RC_FLUTTER_QUAL_SECRET_REFUSED" -eq 125 ]] || fq_fail "CONST_125"
[[ "$CBS_RC_FLUTTER_QUAL_ISOLATION_REJECTED" -eq 126 ]] || fq_fail "CONST_126"
[[ "$CBS_RC_FLUTTER_QUAL_TOOL_UNAVAILABLE" -eq 127 ]] || fq_fail "CONST_127"
[[ "$CBS_RC_FLUTTER_QUAL_TOOLCHAIN_INCOMPATIBLE" -eq 128 ]] || fq_fail "CONST_128"
[[ "$CBS_RC_FLUTTER_QUAL_SIMULATOR_UNAVAILABLE" -eq 129 ]] || fq_fail "CONST_129"
[[ "$CBS_RC_FLUTTER_QUAL_COMMAND_FAILED" -eq 130 ]] || fq_fail "CONST_130"
[[ "$CBS_RC_FLUTTER_QUAL_TIMEOUT" -eq 131 ]] || fq_fail "CONST_131"
[[ "$CBS_RC_FLUTTER_QUAL_NETWORK_FAILURE" -eq 132 ]] || fq_fail "CONST_132"
[[ "$CBS_RC_FLUTTER_QUAL_LOG_LIMIT_EXCEEDED" -eq 133 ]] || fq_fail "CONST_133"
[[ "$CBS_RC_FLUTTER_QUAL_EVIDENCE_FAILURE" -eq 134 ]] || fq_fail "CONST_134"
[[ "$CBS_RC_FLUTTER_QUAL_NOT_EXECUTED" -eq 135 ]] || fq_fail "CONST_135"
[[ "$CBS_RC_FLUTTER_QUAL_PREFLIGHT_NOT_PASSED" -eq 136 ]] || fq_fail "CONST_136"
[[ "$CBS_RC_FLUTTER_QUAL_NOT_SELECTED" -eq 137 ]] || fq_fail "CONST_137"

# No collision with the return codes already used by CBS components. Only the
# shared usage code (64) is common by design.
for code in 10 20 30 40 41 42 50 51 52 53 60 61 62 63 65 66 67 68 69 70 71 72 \
    80 81 82 90 91 92 93 94 100 101 102 103 104 105 106 107 108 109 110 255; do
    case "$SEEN_CODES" in
        *" $code "*) fq_fail "RC_COLLIDES_WITH_EXISTING_$code" ;;
    esac
done

echo "${TEST_PREFIX}_RETURN_CODES=PASS"

# Result and reason must agree.
cbs_flutter_qual_result_reason_consistent PASS "" || fq_fail "CONSISTENT_PASS"
cbs_flutter_qual_result_reason_consistent FAIL COMMAND_FAILED || fq_fail "CONSISTENT_FAIL"
cbs_flutter_qual_result_reason_consistent BLOCKED INPUT_INVALID || fq_fail "CONSISTENT_BLOCKED"
cbs_flutter_qual_result_reason_consistent SKIPPED NOT_SELECTED || fq_fail "CONSISTENT_SKIPPED"
cbs_flutter_qual_result_reason_consistent NOT_RUN PREFLIGHT_NOT_PASSED || fq_fail "CONSISTENT_NOT_RUN"
cbs_flutter_qual_result_reason_consistent NOT_RUN NOT_EXECUTED || fq_fail "CONSISTENT_NOT_RUN_2"

for pair in "PASS COMMAND_FAILED" "FAIL " "FAIL INPUT_INVALID" "BLOCKED " \
    "BLOCKED COMMAND_FAILED" "SKIPPED NOT_EXECUTED" "NOT_RUN NOT_SELECTED" \
    "NOT_RUN INPUT_INVALID" "PASS NOT_SELECTED" "BOGUS INPUT_INVALID" "FAIL bogus"; do
    # shellcheck disable=SC2086
    if cbs_flutter_qual_result_reason_consistent $pair; then
        fq_fail "INCONSISTENT_ACCEPTED_$pair"
    fi
done

echo "${TEST_PREFIX}_RESULT_REASON=PASS"

# ---------------------------------------------------------------- identifiers and formats

for id in a A1 qual-1 qual_1 q.1 "$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64)"; do
    cbs_flutter_qual_id_valid "$id" || fq_fail "ID_VALID"
done

for id in "" ".hidden" "-lead" "_lead" "a/b" "../x" ".." "a b" "a;b" 'a$b' 'a`b' "a.lock" \
    'a
b' "$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65)"; do
    if cbs_flutter_qual_id_valid "$id"; then
        fq_fail "ID_INVALID_ACCEPTED"
    fi
done

cbs_flutter_qual_commit_valid "$FQ_COMMIT" || fq_fail "COMMIT_SHA1"
cbs_flutter_qual_commit_valid "${FQ_COMMIT}0123456789abcdef01234567" || fq_fail "COMMIT_SHA256"

for commit in "" HEAD main "${FQ_COMMIT:0:39}" "${FQ_COMMIT}0" "0123456789ABCDEF0123456789ABCDEF01234567" \
    "${FQ_COMMIT} " "${FQ_COMMIT}^{commit}" "refs/heads/main"; do
    if cbs_flutter_qual_commit_valid "$commit"; then
        fq_fail "COMMIT_INVALID_ACCEPTED"
    fi
done

echo "${TEST_PREFIX}_IDENTIFIERS=PASS"

# ---------------------------------------------------------------- valid request

fq_request_reset
fq_validate_request
[[ "$FQ_RC" -eq 0 ]] || fq_fail "REQUEST_VALID_RC_$FQ_RC"
[[ -z "$CBS_FLUTTER_QUAL_VALIDATION_REASON" ]] || fq_fail "REQUEST_VALID_REASON"

# Minimal valid requests: optional keys absent.
fq_request_reset
fq_request_set actions "preflight,analyze"
fq_request_unset test_scope
fq_request_unset test_targets
fq_validate_request
[[ "$FQ_RC" -eq 0 ]] || fq_fail "REQUEST_ANALYZE_ONLY_RC_$FQ_RC"

for actions in preflight "preflight,report" report "preflight,build_ios" "preflight,analyze,build_ios,report"; do
    fq_request_reset
    fq_request_set actions "$actions"
    fq_request_unset test_scope
    fq_request_unset test_targets
    fq_validate_request
    [[ "$FQ_RC" -eq 0 ]] || fq_fail "REQUEST_ACTIONS_${actions}_RC_$FQ_RC"
done

# test without explicit targets (declarative scope only)
fq_request_reset
fq_request_set actions "preflight,test"
fq_request_unset test_targets
fq_validate_request
[[ "$FQ_RC" -eq 0 ]] || fq_fail "REQUEST_TEST_SCOPE_ONLY_RC_$FQ_RC"

# integration scope: explicit existing simulator required
fq_request_reset
fq_request_set actions "preflight,test"
fq_request_set test_scope "integration"
fq_request_set test_targets "integration_test/app_test.dart"
fq_request_set simulator_udid "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
fq_request_set simulator_policy "existing_only"
fq_validate_request
[[ "$FQ_RC" -eq 0 ]] || fq_fail "REQUEST_INTEGRATION_RC_$FQ_RC"

# Boundary values.
expect_accepted() {
    fq_request_reset
    fq_request_set "$1" "$2"
    fq_validate_request
    [[ "$FQ_RC" -eq 0 ]] || fq_fail "REQUEST_BOUNDARY_$1_$2_RC_$FQ_RC"
}

expect_accepted timeout_seconds 1
expect_accepted timeout_seconds 3600
expect_accepted log_max_bytes 1024
expect_accepted log_max_bytes 104857600
expect_accepted cleanup_policy explicit

echo "${TEST_PREFIX}_REQUEST_VALID=PASS"

# ---------------------------------------------------------------- refused requests

# expect_refused <key> <value> <rc> <reason>
expect_refused() {
    fq_request_reset
    fq_request_set "$1" "$2"
    fq_validate_request

    [[ "$FQ_RC" -eq "$3" ]] || fq_fail "REFUSED_$1_EXPECTED_$3_GOT_${FQ_RC}"
    fq_expect_reason "$4" "REFUSED_$1"
}

# expect_refused_unset <key> : actions without test keep a coherent request.
expect_missing() {
    fq_request_reset
    fq_request_unset "$1"
    fq_validate_request

    [[ "$FQ_RC" -eq 121 ]] || fq_fail "MISSING_$1_GOT_${FQ_RC}"
    fq_expect_reason "INPUT_INVALID" "MISSING_$1"
    [[ "$CBS_FLUTTER_QUAL_VALIDATION_KEY" == "$1" ]] || fq_fail "MISSING_${1}_KEY"
}

for key in contract_version qualification_id isolation_id source_repository expected_origin \
    commit isolation_root evidence_root target actions timeout_seconds log_max_bytes \
    evidence_retention cleanup_policy test_scope; do
    expect_missing "$key"
done

# version
expect_refused contract_version 2 120 CONTRACT_VERSION_UNSUPPORTED
expect_refused contract_version 0 121 INPUT_INVALID
expect_refused contract_version 01 121 INPUT_INVALID
expect_refused contract_version abc 121 INPUT_INVALID
expect_refused contract_version "" 121 INPUT_INVALID

# identifiers
for id in "a/b" "../x" "a.lock" ".hidden" "a b" 'a;id' ""; do
    expect_refused qualification_id "$id" 121 INPUT_INVALID
    expect_refused isolation_id "$id" 121 INPUT_INVALID
done

# commit, target, enumerations
for commit in HEAD main "${FQ_COMMIT:0:39}" "0123456789ABCDEF0123456789ABCDEF01234567" "${FQ_COMMIT}^{commit}"; do
    expect_refused commit "$commit" 121 INPUT_INVALID
done

for target in android-emulator ios-device ios macos "ios-simulator " "IOS-SIMULATOR" ""; do
    expect_refused target "$target" 121 INPUT_INVALID
done

expect_refused evidence_retention purge 121 INPUT_INVALID
expect_refused evidence_retention delete 121 INPUT_INVALID
expect_refused cleanup_policy force 121 INPUT_INVALID
expect_refused cleanup_policy all 121 INPUT_INVALID
expect_refused test_scope all 121 INPUT_INVALID
expect_refused test_scope e2e 121 INPUT_INVALID

# bounds
for value in 0 -1 3601 10s 010 1.5 "" 99999999999; do
    expect_refused timeout_seconds "$value" 121 INPUT_INVALID
done

for value in 0 1023 104857601 1k 01024 -1 ""; do
    expect_refused log_max_bytes "$value" 121 INPUT_INVALID
done

# actions
for value in "" "preflight," ",preflight" "preflight,,analyze" "analyze" "test" "build_ios" \
    "analyze,preflight" "preflight,preflight" "preflight,report,analyze" "preflight,build_ios,analyze"; do
    fq_request_reset
    fq_request_set actions "$value"
    fq_request_unset test_scope
    fq_request_unset test_targets
    fq_validate_request
    [[ "$FQ_RC" -eq 121 ]] || fq_fail "ACTIONS_REFUSED_${value}_GOT_${FQ_RC}"
    fq_expect_reason "INPUT_INVALID" "ACTIONS_$value"
done

for value in "preflight,PREFLIGHT" "preflight,rm" 'preflight;id' "preflight,flutter" "preflight,build_android" \
    "preflight,run" "PREFLIGHT" "preflight analyze" 'preflight,$(id)' "preflight,analyze,deploy"; do
    fq_request_reset
    fq_request_set actions "$value"
    fq_request_unset test_scope
    fq_request_unset test_targets
    fq_validate_request
    [[ "$FQ_RC" -eq 122 ]] || fq_fail "ACTIONS_NOT_ALLOWED_${value}_GOT_${FQ_RC}"
    fq_expect_reason "ACTION_NOT_ALLOWED" "ACTIONS_$value"
done

# tests: declarative selection only
expect_refused test_targets "test/../../x_test.dart" 124 PATH_NOT_ALLOWED
expect_refused test_targets "test/a/../b_test.dart" 124 PATH_NOT_ALLOWED
expect_refused test_targets "/etc/passwd_test.dart" 124 PATH_NOT_ALLOWED
expect_refused test_targets "test/a.dart" 124 PATH_NOT_ALLOWED
expect_refused test_targets "test/a_test.dart --coverage" 124 PATH_NOT_ALLOWED
expect_refused test_targets "test/ a_test.dart" 124 PATH_NOT_ALLOWED
expect_refused test_targets 'test/$(id)_test.dart' 124 PATH_NOT_ALLOWED
expect_refused test_targets "--name=x" 124 PATH_NOT_ALLOWED
expect_refused test_targets "lib/a_test.dart" 124 PATH_NOT_ALLOWED
expect_refused test_targets "test//a_test.dart" 124 PATH_NOT_ALLOWED
expect_refused test_targets "test/a_test.dart,test/a_test.dart" 121 INPUT_INVALID
expect_refused test_targets "test/a_test.dart," 121 INPUT_INVALID
expect_refused test_targets "" 121 INPUT_INVALID
expect_refused test_targets "integration_test/a_test.dart" 121 INPUT_INVALID

targets=""
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17; do
    targets="${targets}test/t${n}_test.dart,"
done
expect_refused test_targets "${targets%,}" 121 INPUT_INVALID

targets=""
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    targets="${targets}test/t${n}_test.dart,"
done
fq_request_reset
fq_request_set test_targets "${targets%,}"
fq_validate_request
[[ "$FQ_RC" -eq 0 ]] || fq_fail "TARGETS_LIMIT_16_RC_$FQ_RC"

# tests keys without the test action
fq_request_reset
fq_request_set actions "preflight,analyze"
fq_validate_request
[[ "$FQ_RC" -eq 121 ]] || fq_fail "TEST_KEYS_WITHOUT_TEST_ACTION_RC_$FQ_RC"

# integration without simulator, integration with unit_widget directory
fq_request_reset
fq_request_set test_scope integration
fq_request_set test_targets "integration_test/a_test.dart"
fq_validate_request
[[ "$FQ_RC" -eq 121 ]] || fq_fail "INTEGRATION_WITHOUT_SIMULATOR_RC_$FQ_RC"
[[ "$CBS_FLUTTER_QUAL_VALIDATION_KEY" == "simulator_udid" ]] || fq_fail "INTEGRATION_WITHOUT_SIMULATOR_KEY"

# simulator: an explicit UDID of an existing simulator, never an alias, never created
for value in booted "iPhone 15" "" "E621E1F8-C36C-495A-93FC-0C247A3E6E5" "E621E1F8C36C495A93FC0C247A3E6E5F" 'E621E1F8-C36C-495A-93FC-0C247A3E6E5F;id'; do
    expect_refused simulator_udid "$value" 121 INPUT_INVALID
done

for value in create boot erase delete shutdown boot_if_shutdown ""; do
    expect_refused simulator_policy "$value" 121 INPUT_INVALID
done

# paths
for value in "relative/path" "./x" "../x" "/" "/tmp" "/srv/../etc" "/srv/./x" "/srv//x" \
    "/srv/cbs/source/app/" '~/x' '/srv/$HOME/x' '/srv/`id`/x' "/srv/a b/x" "/srv/a;b/x" \
    "/srv/cbs/.git/x" "/srv/cbs/.GIT/x" "/srv/cbs/.local/x" "/srv/.ssh/x" "/srv/.aws/x" \
    "/srv/.env/x" "/srv/*/x" "/srv/a?b/x"; do
    for key in source_repository isolation_root evidence_root; do
        expect_refused "$key" "$value" 124 PATH_NOT_ALLOWED
    done
done

# An empty path is not a text: INPUT_INVALID, never accepted.
for key in source_repository isolation_root evidence_root; do
    expect_refused "$key" "" 121 INPUT_INVALID
done

# roots never overlap (lexical)
expect_refused isolation_root "/srv/cbs/source/app/isolation" 124 PATH_NOT_ALLOWED
expect_refused isolation_root "/srv/cbs/source" 124 PATH_NOT_ALLOWED
expect_refused isolation_root "/srv/cbs/source/app" 124 PATH_NOT_ALLOWED
expect_refused evidence_root "/srv/cbs/source/app/evidence" 124 PATH_NOT_ALLOWED
expect_refused evidence_root "/srv/cbs/isolation/evidence" 124 PATH_NOT_ALLOWED
expect_refused evidence_root "/srv/cbs/isolation" 124 PATH_NOT_ALLOWED
expect_refused evidence_root "/srv/cbs" 124 PATH_NOT_ALLOWED

# a sibling with a common name prefix is not an overlap
fq_request_reset
fq_request_set evidence_root "/srv/cbs/isolation-evidence"
fq_validate_request
[[ "$FQ_RC" -eq 0 ]] || fq_fail "SIBLING_PREFIX_NOT_OVERLAP_RC_$FQ_RC"

# origin
for value in "-oProxyCommand=x" "ext::sh -c id" 'x;id' "a b" "" "/leading" ; do
    expect_refused expected_origin "$value" 121 INPUT_INVALID
done

expect_refused expected_origin "https://user@example.invalid/x.git" 125 SECRET_REFUSED
expect_refused expected_origin "https://user:s3cr3t@example.invalid/x.git" 125 SECRET_REFUSED
expect_refused expected_origin "ssh://git@example.invalid/x.git" 125 SECRET_REFUSED

fq_request_reset
fq_request_set expected_origin "https://example.invalid/org/app.git"
fq_validate_request
[[ "$FQ_RC" -eq 0 ]] || fq_fail "ORIGIN_HTTPS_RC_$FQ_RC"

echo "${TEST_PREFIX}_REQUEST_REFUSED=PASS"

# ---------------------------------------------------------------- arbitrary arguments

expect_argv_refused() {
    local expected_rc="$1"
    local expected_reason="$2"

    shift 2
    fq_request_reset
    set +e
    cbs_flutter_qual_validate_request "${FQ_REQUEST[@]}" "$@" >/dev/null 2>&1
    FQ_RC=$?
    set -e

    [[ "$FQ_RC" -eq "$expected_rc" ]] || fq_fail "ARGV_${1:-empty}_EXPECTED_${expected_rc}_GOT_${FQ_RC}"
    fq_expect_reason "$expected_reason" "ARGV_${1:-empty}"
}

expect_argv_refused 123 ARGUMENT_REFUSED "--flavor=prod"
expect_argv_refused 123 ARGUMENT_REFUSED "--dart-define=A=b"
expect_argv_refused 123 ARGUMENT_REFUSED "-v"
expect_argv_refused 123 ARGUMENT_REFUSED "--"
expect_argv_refused 123 ARGUMENT_REFUSED "flutter"
expect_argv_refused 123 ARGUMENT_REFUSED "rm -rf /"
expect_argv_refused 123 ARGUMENT_REFUSED '$(id)'
expect_argv_refused 123 ARGUMENT_REFUSED ""
expect_argv_refused 123 ARGUMENT_REFUSED "/etc/passwd"
expect_argv_refused 123 ARGUMENT_REFUSED "analyze"
expect_argv_refused 123 ARGUMENT_REFUSED "unknown_key=value"
expect_argv_refused 123 ARGUMENT_REFUSED "extra_args=--verbose"
expect_argv_refused 123 ARGUMENT_REFUSED "flutter_args=--verbose"
expect_argv_refused 123 ARGUMENT_REFUSED "command=ls"
expect_argv_refused 123 ARGUMENT_REFUSED "Actions=analyze"
expect_argv_refused 123 ARGUMENT_REFUSED "actions =analyze"
expect_argv_refused 123 ARGUMENT_REFUSED "=value"
expect_argv_refused 123 ARGUMENT_REFUSED 'a;b=c'
expect_argv_refused 121 INPUT_INVALID "commit=$FQ_COMMIT"
expect_argv_refused 121 INPUT_INVALID "actions=preflight"

# Too many entries.
set +e
cbs_flutter_qual_validate_request "${FQ_REQUEST[@]}" "${FQ_REQUEST[@]}" "${FQ_REQUEST[@]}" >/dev/null 2>&1
FQ_RC=$?
set -e
[[ "$FQ_RC" -eq 121 ]] || fq_fail "TOO_MANY_ENTRIES_RC_$FQ_RC"

# An action takes no argument.
fq_expect_rc 0 "ACTION_CALL_NO_ARG" cbs_flutter_qual_validate_action_call analyze

for extra in "--verbose" "-d" "--dart-define=A=b" "x" "" "; id" '$(id)'; do
    fq_expect_rc 123 "ACTION_CALL_EXTRA_ARG" cbs_flutter_qual_validate_action_call analyze "$extra"
done

fq_expect_rc 122 "ACTION_CALL_BAD_ACTION" cbs_flutter_qual_validate_action_call shell
fq_expect_rc 122 "ACTION_CALL_NO_ACTION" cbs_flutter_qual_validate_action_call
fq_expect_rc 122 "ACTION_CALL_BAD_ACTION_AND_ARG" cbs_flutter_qual_validate_action_call shell --x

echo "${TEST_PREFIX}_ARGUMENTS=PASS"

# ---------------------------------------------------------------- structured output

OUT="$(cbs_flutter_qual_emit_operation PREFLIGHT PASS)"
[[ "$OUT" == "CBS_FLUTTER_QUAL_OPERATION=PREFLIGHT
CBS_FLUTTER_QUAL_OPERATION_RESULT=PASS
CBS_FLUTTER_QUAL_OPERATION_RC=0" ]] || fq_fail "EMIT_PASS"

OUT="$(cbs_flutter_qual_emit_operation ANALYZE FAIL COMMAND_FAILED 1)"
[[ "$OUT" == "CBS_FLUTTER_QUAL_OPERATION=ANALYZE
CBS_FLUTTER_QUAL_OPERATION_RESULT=FAIL
CBS_FLUTTER_QUAL_OPERATION_REASON=COMMAND_FAILED
CBS_FLUTTER_QUAL_OPERATION_RC=130
CBS_FLUTTER_QUAL_OPERATION_TOOL_RC=1" ]] || fq_fail "EMIT_FAIL_TOOL_RC"

# The exact exit status of the tool is preserved, apart from the contract code.
for tool_rc in 1 2 64 65 124 126 127 130 137 143 255; do
    OUT="$(cbs_flutter_qual_emit_operation TEST FAIL COMMAND_FAILED "$tool_rc")"
    grep -Fxq "CBS_FLUTTER_QUAL_OPERATION_TOOL_RC=$tool_rc" <<<"$OUT" || fq_fail "EMIT_TOOL_RC_$tool_rc"
    grep -Fxq "CBS_FLUTTER_QUAL_OPERATION_RC=130" <<<"$OUT" || fq_fail "EMIT_CONTRACT_RC_$tool_rc"
done

OUT="$(cbs_flutter_qual_emit_operation BUILD_IOS PASS "" 0)"
grep -Fxq "CBS_FLUTTER_QUAL_OPERATION_TOOL_RC=0" <<<"$OUT" || fq_fail "EMIT_PASS_TOOL_RC_0"

OUT="$(cbs_flutter_qual_emit_operation TEST BLOCKED SIMULATOR_UNAVAILABLE)"
grep -Fxq "CBS_FLUTTER_QUAL_OPERATION_RC=129" <<<"$OUT" || fq_fail "EMIT_BLOCKED_RC"

OUT="$(cbs_flutter_qual_emit_operation BUILD_IOS NOT_RUN PREFLIGHT_NOT_PASSED)"
grep -Fxq "CBS_FLUTTER_QUAL_OPERATION_RESULT=NOT_RUN" <<<"$OUT" || fq_fail "EMIT_NOT_RUN_RESULT"
grep -Fxq "CBS_FLUTTER_QUAL_OPERATION_RC=136" <<<"$OUT" || fq_fail "EMIT_NOT_RUN_RC"

OUT="$(cbs_flutter_qual_emit_operation REPORT SKIPPED NOT_SELECTED)"
grep -Fxq "CBS_FLUTTER_QUAL_OPERATION_RESULT=SKIPPED" <<<"$OUT" || fq_fail "EMIT_SKIPPED_RESULT"
grep -Fxq "CBS_FLUTTER_QUAL_OPERATION_RC=137" <<<"$OUT" || fq_fail "EMIT_SKIPPED_RC"

# Invalid emissions print nothing on stdout and fail with the usage code.
expect_emit_refused() {
    local out

    set +e
    out="$("$@" 2>/dev/null)"
    FQ_RC=$?
    set -e

    [[ "$FQ_RC" -eq 64 ]] || fq_fail "EMIT_REFUSED_RC_$*_$FQ_RC"
    [[ -z "$out" ]] || fq_fail "EMIT_REFUSED_PRINTED_$*"
}

expect_emit_refused cbs_flutter_qual_emit_operation FLUTTER PASS
expect_emit_refused cbs_flutter_qual_emit_operation analyze PASS
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE pass
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE PASS COMMAND_FAILED
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE FAIL
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE FAIL INPUT_INVALID
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE BLOCKED
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE BLOCKED COMMAND_FAILED
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE FAIL bogus
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE BLOCKED INPUT_INVALID 1
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE NOT_RUN NOT_EXECUTED 1
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE SKIPPED NOT_SELECTED 0
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE PASS "" 3
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE FAIL COMMAND_FAILED 256
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE FAIL COMMAND_FAILED x
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE FAIL COMMAND_FAILED -1
expect_emit_refused cbs_flutter_qual_emit_operation ANALYZE FAIL COMMAND_FAILED "1;id"
expect_emit_refused cbs_flutter_qual_emit_result SKIPPED NOT_SELECTED
expect_emit_refused cbs_flutter_qual_emit_result PASS COMMAND_FAILED
expect_emit_refused cbs_flutter_qual_emit_result FAIL
expect_emit_refused cbs_flutter_qual_emit_result BOGUS
expect_emit_refused cbs_flutter_qual_emit_result

OUT="$(cbs_flutter_qual_emit_result PASS)"
[[ "$OUT" == "CBS_FLUTTER_QUAL_CONTRACT_VERSION=1
CBS_FLUTTER_QUAL_RESULT=PASS" ]] || fq_fail "EMIT_RESULT_PASS"

OUT="$(cbs_flutter_qual_emit_result BLOCKED INPUT_INVALID 2>/dev/null)"
[[ "$OUT" == "CBS_FLUTTER_QUAL_REASON=INPUT_INVALID
CBS_FLUTTER_QUAL_CONTRACT_VERSION=1
CBS_FLUTTER_QUAL_RESULT=BLOCKED" ]] || fq_fail "EMIT_RESULT_BLOCKED"

# The RESULT line is the last stdout line.
for pair in "FAIL COMMAND_FAILED" "NOT_RUN NOT_EXECUTED" "BLOCKED TOOL_UNAVAILABLE"; do
    # shellcheck disable=SC2086
    OUT="$(cbs_flutter_qual_emit_result $pair 2>/dev/null)"
    [[ "${OUT##*$'\n'}" == "CBS_FLUTTER_QUAL_RESULT=${pair%% *}" ]] || fq_fail "EMIT_RESULT_LAST_LINE_$pair"
done

# The reason also goes to stderr, in the same form as the other components.
ERR="$(cbs_flutter_qual_emit_result BLOCKED INPUT_INVALID 2>&1 >/dev/null)"
[[ "$ERR" == "CBS_FLUTTER_QUAL_ERROR=INPUT_INVALID" ]] || fq_fail "EMIT_RESULT_STDERR"

echo "${TEST_PREFIX}_EMISSION=PASS"

# ---------------------------------------------------------------- no tool was reached

fq_shims_assert_unused "CONTRACT"

echo "${TEST_PREFIX}_NO_TOOL_CALLED=PASS"
echo "${TEST_PREFIX}_RESULT=PASS"
