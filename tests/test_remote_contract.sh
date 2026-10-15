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

declare -A seen=()

for code in "${codes[@]}"; do
    [[ -z "${seen[$code]+x}" ]] || fail "RC_DUPLICATE_$code"
    seen["$code"]=1
done

for reused in \
    "$CBS_REPOSITORY_RC_MISSING" \
    "$CBS_REPOSITORY_RC_NOT_GIT" \
    "$CBS_REPOSITORY_RC_REMOTE_MISMATCH" \
    "$CBS_REPOSITORY_RC_UNKNOWN" \
    "$CBS_RC_REMOTE_USAGE" \
    0
do
    [[ -z "${seen[$reused]+x}" ]] || fail "RC_COLLISION_$reused"
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

# --- source idempotence
source "$ROOT/cbs/remote/contract.sh"
source "$ROOT/cbs/remote/contract.sh"

[[ "$CBS_REMOTE_CONTRACT_VERSION" == "1" ]] ||
    fail "SOURCE_IDEMPOTENCE"

echo "TEST_REMOTE_CONTRACT_SOURCE_IDEMPOTENCE=PASS"

echo "TEST_REMOTE_CONTRACT_RESULT=PASS"
