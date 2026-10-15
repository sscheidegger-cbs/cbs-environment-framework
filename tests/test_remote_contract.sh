#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "TEST_REMOTE_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_REMOTE_CONTRACT_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/remote/contract.sh"
source "$ROOT/cbs/workspace/repository_contract.sh"

[[ "$CBS_REMOTE_CONTRACT_VERSION" == "1" ]] ||
    fail "CONTRACT_VERSION"

[[ "$CBS_REMOTE_MANIFEST_VERSION" == "1" ]] ||
    fail "MANIFEST_VERSION"

echo "TEST_REMOTE_CONTRACT_VERSION=PASS"

# --- structured results
[[ "$CBS_REMOTE_RESULT_PASS" == "PASS" ]] || fail "RESULT_PASS"
[[ "$CBS_REMOTE_RESULT_FAIL" == "FAIL" ]] || fail "RESULT_FAIL"
[[ "$CBS_REMOTE_RESULT_BLOCKED" == "BLOCKED" ]] || fail "RESULT_BLOCKED"

for result in PASS FAIL BLOCKED; do
    cbs_remote_result_is_valid "$result" ||
        fail "RESULT_VALID_$result"
done

for result in pass UNKNOWN READY "" SKIPPED; do
    if cbs_remote_result_is_valid "$result"; then
        fail "RESULT_INVALID_ACCEPTED_$result"
    fi
done

for relation in EQUAL AHEAD BEHIND DIVERGED UNKNOWN_OBJECT; do
    cbs_remote_commit_relation_is_valid "$relation" ||
        fail "RELATION_VALID_$relation"
done

if cbs_remote_commit_relation_is_valid "SAME"; then
    fail "RELATION_INVALID_ACCEPTED"
fi

echo "TEST_REMOTE_CONTRACT_RESULTS=PASS"

# --- return codes are distinct and do not collide with the reused contracts
codes=(
    "$CBS_RC_REMOTE_MANIFEST_INVALID"
    "$CBS_RC_REMOTE_LOCAL_SSH_UNAVAILABLE"
    "$CBS_RC_REMOTE_HOST_UNREACHABLE"
    "$CBS_RC_REMOTE_REMOTE_GIT_UNAVAILABLE"
    "$CBS_RC_REMOTE_BRANCH_MISMATCH"
    "$CBS_RC_REMOTE_COMMIT_MISMATCH"
    "$CBS_RC_REMOTE_WORKTREE_DIRTY"
    "$CBS_RC_REMOTE_ACTION_NOT_ALLOWED"
    "$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE"
    "$CBS_RC_REMOTE_LOCAL_REFERENCE_UNAVAILABLE"
    "$CBS_RC_REMOTE_PROBE_FAILED"
    "$CBS_RC_REMOTE_TRANSPORT_FAILURE"
)

# Codes already seen, as a space-delimited list (no associative array: Bash 3.2).
seen=" "

for code in "${codes[@]}"; do
    [[ "$seen" != *" $code "* ]] || fail "RC_DUPLICATE_$code"
    seen="$seen$code "
done

for reused in \
    "$CBS_REPOSITORY_RC_MISSING" \
    "$CBS_REPOSITORY_RC_NOT_GIT" \
    "$CBS_REPOSITORY_RC_REMOTE_MISMATCH" \
    "$CBS_REPOSITORY_RC_UNKNOWN" \
    "$CBS_RC_REMOTE_USAGE" \
    0
do
    [[ "$seen" != *" $reused "* ]] || fail "RC_COLLISION_$reused"
done

[[ "$CBS_RC_REMOTE_USAGE" -eq 64 ]] || fail "RC_USAGE"
[[ "$CBS_RC_REMOTE_TRANSPORT_FAILURE" -eq 255 ]] || fail "RC_TRANSPORT"

echo "TEST_REMOTE_CONTRACT_RETURN_CODES=PASS"

# --- the catalog of CBS commands that may be bound to a remote action
#
# The allow-list is explicit: this exact list, nothing else. Extending it must
# be a deliberate change of both contract.sh and this test.
EXPECTED_ALLOW_LIST=(
    "version"
    "status"
    "workstation check"
    "workspace check"
    "worktree check"
    "instance check"
    "stack resolve"
    "stack prerequisites"
    "stack environment"
    "platform resolve"
    "runtime android list"
)

[[ "${#CBS_REMOTE_COMMAND_ALLOW_LIST[@]}" -eq "${#EXPECTED_ALLOW_LIST[@]}" ]] ||
    fail "CATALOG_SIZE_${#CBS_REMOTE_COMMAND_ALLOW_LIST[@]}"

for index in "${!EXPECTED_ALLOW_LIST[@]}"; do
    [[ "${CBS_REMOTE_COMMAND_ALLOW_LIST[$index]}" == "${EXPECTED_ALLOW_LIST[$index]}" ]] ||
        fail "CATALOG_ENTRY_$index"
done

for allowed in "${EXPECTED_ALLOW_LIST[@]}"; do
    read -r first second third <<<"$allowed"

    cbs_remote_command_prefix_is_allowed "$first" "${second:-}" "${third:-}" ||
        fail "CATALOG_ALLOWED_$allowed"
done

# Arguments after an allowed prefix do not change the decision.
cbs_remote_command_prefix_is_allowed stack environment stacks/flutter/stack.env ||
    fail "CATALOG_ALLOWED_WITH_ARGUMENT"

# No entry names a mutating operation.
for entry in "${CBS_REMOTE_COMMAND_ALLOW_LIST[@]}"; do
    for word in $entry; do
        case "$word" in
            ensure|start|stop|install|create|remove|delete|clean|reset|qualify)
                fail "CATALOG_MUTATING_WORD:$entry"
                ;;
        esac
    done
done

for forbidden in \
    "remote check" \
    "remote run" \
    "repository ensure" \
    "workspace ensure" \
    "worktree ensure" \
    "instance ensure" \
    "runtime android start" \
    "runtime android stop" \
    "runtime android ensure" \
    "runtime android" \
    "runtime" \
    "stack toolchains ensure" \
    "stack toolchains" \
    "stack" \
    "platform start" \
    "platform stop" \
    "platform check" \
    "platform status" \
    "platform qualify" \
    "platform" \
    "platform deploy" \
    "versions" \
    "stack environments" \
    "workspace" \
    "instance" \
    "rm -rf" \
    "sh" \
    "bash" \
    "help" \
    ""
do
    read -r first second third <<<"$forbidden" || true

    if cbs_remote_command_prefix_is_allowed "${first:-}" "${second:-}" "${third:-}"; then
        fail "CATALOG_FORBIDDEN_ACCEPTED_$forbidden"
    fi
done

# A word in the wrong position never matches.
for forbidden_position in \
    "ensure stack toolchains" \
    "start platform" \
    "stop platform" \
    "toolchains ensure stack"
do
    read -r first second third <<<"$forbidden_position"

    if cbs_remote_command_prefix_is_allowed "$first" "$second" "${third:-}"; then
        fail "CATALOG_FORBIDDEN_POSITION_$forbidden_position"
    fi
done

# Empty intermediate words are not skipped.
if cbs_remote_command_prefix_is_allowed "stack" "" "ensure"; then
    fail "CATALOG_EMPTY_WORD_SKIPPED"
fi

echo "TEST_REMOTE_CONTRACT_COMMAND_CATALOG=PASS"

# --- launcher verdict vocabulary
[[ "$CBS_REMOTE_REASON_LAUNCH_NOT_CONFIRMED" == "LAUNCH_NOT_CONFIRMED" ]] || fail "REASON_LAUNCH_NOT_CONFIRMED"
[[ "$CBS_REMOTE_LAUNCH_PREFLIGHT_PASS" == "PASS" ]] || fail "LAUNCH_PREFLIGHT_PASS"
[[ "$CBS_REMOTE_LAUNCH_PREFLIGHT_REFUSED" == "REFUSED" ]] || fail "LAUNCH_PREFLIGHT_REFUSED"
[[ "$CBS_REMOTE_LAUNCH_PREFLIGHT_NOT_REPORTED" == "NOT_REPORTED" ]] || fail "LAUNCH_PREFLIGHT_NOT_REPORTED"

# Existing return codes are unchanged.
[[ "$CBS_RC_REMOTE_BRANCH_MISMATCH" -eq 104 ]] || fail "RC_BRANCH_UNCHANGED"
[[ "$CBS_RC_REMOTE_COMMIT_MISMATCH" -eq 105 ]] || fail "RC_COMMIT_UNCHANGED"
[[ "$CBS_RC_REMOTE_WORKTREE_DIRTY" -eq 106 ]] || fail "RC_WORKTREE_UNCHANGED"
[[ "$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE" -eq 108 ]] || fail "RC_ENTRYPOINT_UNCHANGED"
[[ "$CBS_RC_REMOTE_PROBE_FAILED" -eq 110 ]] || fail "RC_PROBE_UNCHANGED"

echo "TEST_REMOTE_CONTRACT_LAUNCH_VOCABULARY=PASS"

# --- structured result emission
OUTPUT="$(cbs_remote_emit_result BLOCKED HOST_UNREACHABLE 2>/dev/null)"

[[ "$OUTPUT" == $'CBS_REMOTE_REASON=HOST_UNREACHABLE\nCBS_REMOTE_RESULT=BLOCKED' ]] ||
    fail "EMIT_BLOCKED"

OUTPUT="$(cbs_remote_emit_result PASS)"

[[ "$OUTPUT" == "CBS_REMOTE_RESULT=PASS" ]] ||
    fail "EMIT_PASS"

ERROR_OUTPUT="$(cbs_remote_emit_result BLOCKED HOST_UNREACHABLE 2>&1 >/dev/null)"

[[ "$ERROR_OUTPUT" == "CBS_REMOTE_ERROR=HOST_UNREACHABLE" ]] ||
    fail "EMIT_ERROR_STREAM"

echo "TEST_REMOTE_CONTRACT_EMIT=PASS"

# --- Bash 3.2 compatible lookup and case helpers

# Keyed entries: first match wins, defaults apply to absent and empty values,
# keys are compared as plain strings (glob characters are not patterns).
ENTRIES=("ALPHA=one" "BETA=" "GAMMA=a=b=c" "A*=glob" "ALPHA=shadowed")

cbs_remote_entries_has ALPHA "${ENTRIES[@]}" || fail "ENTRIES_HAS_PRESENT"
cbs_remote_entries_has BETA "${ENTRIES[@]}" || fail "ENTRIES_HAS_EMPTY_VALUE"

if cbs_remote_entries_has DELTA "${ENTRIES[@]}"; then
    fail "ENTRIES_HAS_ABSENT"
fi

if cbs_remote_entries_has "ALP" "${ENTRIES[@]}"; then
    fail "ENTRIES_HAS_PREFIX_MATCHED"
fi

if cbs_remote_entries_has "A?" "${ENTRIES[@]}"; then
    fail "ENTRIES_HAS_GLOB_MATCHED"
fi

if cbs_remote_entries_has ALPHA; then
    fail "ENTRIES_HAS_EMPTY_STORE"
fi

[[ "$(cbs_remote_entries_get ALPHA "" "${ENTRIES[@]}")" == "one" ]] ||
    fail "ENTRIES_GET_FIRST_WINS"
[[ "$(cbs_remote_entries_get GAMMA "" "${ENTRIES[@]}")" == "a=b=c" ]] ||
    fail "ENTRIES_GET_VALUE_WITH_EQUALS"
[[ "$(cbs_remote_entries_get "A*" "" "${ENTRIES[@]}")" == "glob" ]] ||
    fail "ENTRIES_GET_GLOB_KEY_IS_LITERAL"
[[ "$(cbs_remote_entries_get BETA fallback "${ENTRIES[@]}")" == "fallback" ]] ||
    fail "ENTRIES_GET_DEFAULT_ON_EMPTY"
[[ "$(cbs_remote_entries_get DELTA fallback "${ENTRIES[@]}")" == "fallback" ]] ||
    fail "ENTRIES_GET_DEFAULT_ON_ABSENT"
[[ -z "$(cbs_remote_entries_get DELTA "")" ]] ||
    fail "ENTRIES_GET_EMPTY_STORE"

cbs_remote_word_in_list show_args show_version show_args || fail "WORD_IN_LIST_PRESENT"

if cbs_remote_word_in_list show show_version show_args; then
    fail "WORD_IN_LIST_PREFIX_MATCHED"
fi

if cbs_remote_word_in_list show_args; then
    fail "WORD_IN_LIST_EMPTY"
fi

# ASCII case conversion does not depend on the locale (the Turkish locale, whose
# dotless i breaks locale-aware conversions, is exercised when it is installed).
LOCALE_NAMES=(C)

if locale -a 2>/dev/null | grep -Fxq 'tr_TR.UTF-8'; then
    LOCALE_NAMES+=(tr_TR.UTF-8)
fi

for locale_name in "${LOCALE_NAMES[@]}"; do
    [[ "$(LC_ALL="$locale_name" cbs_remote_ascii_upper "show_exit42-iI")" == "SHOW_EXIT42-II" ]] ||
        fail "ASCII_UPPER_$locale_name"
    [[ "$(LC_ALL="$locale_name" cbs_remote_ascii_lower "SHOW_EXIT42-iI")" == "show_exit42-ii" ]] ||
        fail "ASCII_LOWER_$locale_name"
done

[[ -z "$(cbs_remote_ascii_upper "")" && -z "$(cbs_remote_ascii_lower "")" ]] ||
    fail "ASCII_CASE_EMPTY"

# The allow-list stays read-only once the contract is loaded.
if (CBS_REMOTE_COMMAND_ALLOW_LIST+=("platform start")) 2>/dev/null; then
    fail "ALLOW_LIST_IS_WRITABLE"
fi

[[ "${#CBS_REMOTE_COMMAND_ALLOW_LIST[@]}" -eq "${#EXPECTED_ALLOW_LIST[@]}" ]] ||
    fail "ALLOW_LIST_WAS_MODIFIED"

echo "TEST_REMOTE_CONTRACT_PORTABLE_HELPERS=PASS"

# --- source idempotence
source "$ROOT/cbs/remote/contract.sh"
source "$ROOT/cbs/remote/contract.sh"

[[ "$CBS_REMOTE_CONTRACT_VERSION" == "1" ]] ||
    fail "SOURCE_IDEMPOTENCE"

echo "TEST_REMOTE_CONTRACT_SOURCE_IDEMPOTENCE=PASS"

echo "TEST_REMOTE_CONTRACT_RESULT=PASS"
