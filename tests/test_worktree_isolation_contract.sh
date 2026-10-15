#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/worktree/isolation_contract.sh"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_CONTRACT"

fail() {
    echo "${TEST_PREFIX}_RESULT=FAIL" >&2
    echo "${TEST_PREFIX}_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/worktree/contract.sh"
source "$CONTRACT"

[[ "$CBS_ISOLATION_CONTRACT_VERSION" == "1" ]] ||
    fail "VERSION"

echo "${TEST_PREFIX}_VERSION=PASS"

# Results: PASS, FAIL, BLOCKED, NOT_RUN are valid; SKIPPED is not a runtime result.
for result in PASS FAIL BLOCKED NOT_RUN; do
    cbs_isolation_result_is_valid "$result" || fail "RESULT_$result"
done

for result in SKIPPED pass "" UNKNOWN; do
    if cbs_isolation_result_is_valid "$result"; then
        fail "RESULT_INVALID_ACCEPTED_$result"
    fi
done

echo "${TEST_PREFIX}_RESULTS=PASS"

# Return codes: new codes do not collide with the existing worktree contract.
[[ "$CBS_RC_ISOLATION_COMMIT_INVALID" -eq 65 ]] || fail "RC_65"
[[ "$CBS_RC_ISOLATION_ORIGIN_MISMATCH" -eq 66 ]] || fail "RC_66"
[[ "$CBS_RC_ISOLATION_OWNERSHIP" -eq 67 ]] || fail "RC_67"
[[ "$CBS_RC_ISOLATION_STATE_CONFLICT" -eq 68 ]] || fail "RC_68"
[[ "$CBS_RC_ISOLATION_FAILED" -eq 69 ]] || fail "RC_69"

[[ "$CBS_RC_WORKTREE_BRANCH_CONFLICT" -eq 60 ]] || fail "WORKTREE_RC_60"
[[ "$CBS_RC_WORKTREE_PATH_CONFLICT" -eq 61 ]] || fail "WORKTREE_RC_61"
[[ "$CBS_RC_WORKTREE_INVALID_REPOSITORY" -eq 62 ]] || fail "WORKTREE_RC_62"
[[ "$CBS_RC_WORKTREE_UNKNOWN" -eq 63 ]] || fail "WORKTREE_RC_63"
[[ "$CBS_RC_WORKTREE_USAGE" -eq 64 ]] || fail "WORKTREE_RC_64"

echo "${TEST_PREFIX}_RETURN_CODES=PASS"

# Lock and evidence locations are part of the contract.
[[ "$CBS_ISOLATION_LOCK_DIR" == ".cbs-isolation.lock" ]] || fail "LOCK_DIR"
[[ "$CBS_ISOLATION_PROOF_DIR" == ".cbs-isolation" ]] || fail "PROOF_DIR"

echo "${TEST_PREFIX}_LOCATIONS=PASS"

# Identifier validation.
for id in a A1 qual-1 qual_1 q.1 ios-qualification-2026-10-15 \
    "$(printf 'a%.0s' $(seq 1 64))"
do
    cbs_isolation_id_valid "$id" || fail "ID_VALID_$id"
done

for id in "" ".hidden" "-lead" "_lead" "a/b" "../x" ".." "a b" "a;b" \
    'a$b' 'a`b' "a.lock" 'a
b' "$(printf 'a%.0s' $(seq 1 65))"
do
    if cbs_isolation_id_valid "$id"; then
        fail "ID_INVALID_ACCEPTED"
    fi
done

echo "${TEST_PREFIX}_ID=PASS"

# Commit format validation: full lowercase object name only.
SHA1="0123456789abcdef0123456789abcdef01234567"
SHA256="${SHA1}0123456789abcdef01234567"

[[ "${#SHA1}" -eq 40 && "${#SHA256}" -eq 64 ]] || fail "FIXTURE_LENGTHS"

cbs_isolation_commit_format_valid "$SHA1" || fail "COMMIT_SHA1"
cbs_isolation_commit_format_valid "$SHA256" || fail "COMMIT_SHA256"

for commit in "" "0123456" "${SHA1:0:39}" "${SHA1}0" "HEAD" "main" \
    "0123456789ABCDEF0123456789ABCDEF01234567" \
    "${SHA1:0:39}g" "$SHA1 " "${SHA1}^{commit}"
do
    if cbs_isolation_commit_format_valid "$commit"; then
        fail "COMMIT_INVALID_ACCEPTED_$commit"
    fi
done

echo "${TEST_PREFIX}_COMMIT_FORMAT=PASS"

# Text-as-data validation.
cbs_isolation_valid_text "/some/path" || fail "TEXT_VALID"

for text in "" "a
b" "$(printf 'a\tb')" "$(printf 'a\rb')"; do
    if cbs_isolation_valid_text "$text"; then
        fail "TEXT_INVALID_ACCEPTED"
    fi
done

echo "${TEST_PREFIX}_TEXT=PASS"

# Credentials never survive redaction.
REDACTED="$(cbs_isolation_redact "https://user:s3cr3t-token@example.invalid/x.git")"

[[ "$REDACTED" == "https://[REDACTED]@example.invalid/x.git" ]] ||
    fail "REDACT_FORMAT"

if grep -Fq "s3cr3t" <<<"$REDACTED"; then
    fail "REDACT_LEAK"
fi

[[ "$(cbs_isolation_redact "git@example.invalid:org/x.git")" == "git@example.invalid:org/x.git" ]] ||
    fail "REDACT_SCP_UNCHANGED"

echo "${TEST_PREFIX}_REDACTION=PASS"

# The existing worktree contract is unchanged (non-regression).
[[ "$CBS_WORKTREE_CONTRACT_VERSION" == "1" ]] || fail "WORKTREE_CONTRACT_VERSION"
[[ "$(cbs_worktree_action_for_state READY)" == "REUSE" ]] || fail "WORKTREE_READY_ACTION"
[[ "$(cbs_worktree_action_for_state MISSING)" == "CREATE" ]] || fail "WORKTREE_MISSING_ACTION"

echo "${TEST_PREFIX}_EXISTING_CONTRACT_UNCHANGED=PASS"

# Static scan: forbidden destructive operations and Bash > 3.2 constructs.
ISOLATION_FILES="$ROOT/cbs/worktree/isolation_contract.sh $ROOT/cbs/worktree/isolation_manager.sh"

for file in $ISOLATION_FILES; do
    [[ -f "$file" ]] || fail "STATIC_FILE_MISSING_$file"

    if grep -En 'reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f|rm[[:space:]]+-[a-zA-Z]*r|worktree[[:space:]]+prune|push|fetch|pull|clone|ssh|curl|wget' "$file" |
        grep -Ev '^[0-9]+:[[:space:]]*#' |
        grep -Eq .
    then
        fail "STATIC_FORBIDDEN_OPERATION_$file"
    fi

    # No forced Git operation, whatever the sub-command or the spelling.
    if grep -En -e '--force' -e 'worktree[[:space:]]+[a-z]+[^#]*[[:space:]]-f+([[:space:]]|$)' -e '[[:space:]]-ff([[:space:]]|$)' "$file" |
        grep -Ev '^[0-9]+:[[:space:]]*#' |
        grep -Eq .
    then
        fail "STATIC_FORCED_OPERATION_$file"
    fi

    # No recursive or unbounded deletion, no flock (absent on macOS).
    if grep -En 'rm[[:space:]]+-[a-zA-Z]*[rR]|find[^|]*-delete|flock|xargs[[:space:]]+rm|rmdir[[:space:]]+-p' "$file" |
        grep -Ev '^[0-9]+:[[:space:]]*#' |
        grep -Eq .
    then
        fail "STATIC_UNBOUNDED_DELETION_OR_FLOCK_$file"
    fi

    if grep -En 'mapfile|readarray|declare[[:space:]]+-A|local[[:space:]]+-n|\$\{[A-Za-z_]+(,,|\^\^)\}|;;&|;&|\|&|coproc|\[\[[[:space:]]+-v[[:space:]]|printf[[:space:]]+.*%\(|readlink[[:space:]]+-f|realpath|sed[[:space:]]+-i|stat[[:space:]]+-[cf]|date[[:space:]]+-d' "$file" |
        grep -Ev '^[0-9]+:[[:space:]]*#' |
        grep -Eq .
    then
        fail "STATIC_BASH32_INCOMPATIBLE_$file"
    fi
done

echo "${TEST_PREFIX}_STATIC_SAFETY=PASS"
echo "${TEST_PREFIX}_RESULT=PASS"
