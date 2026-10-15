#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/tests/fixtures/remote/lib.sh"
source "$ROOT/cbs/remote/contract.sh"
source "$ROOT/cbs/workspace/repository_contract.sh"

REMOTE_TEST_PREFIX="TEST_REMOTE_CHECK"

# Runs "cbs remote check" on the current scenario and verifies that the
# simulated remote repository was left untouched.
check() {
    local before
    local after

    remote_test_write_manifest "$MANIFEST"

    before="$(remote_test_remote_state)"
    remote_test_run "$CBS" remote check "$MANIFEST"
    after="$(remote_test_remote_state)"

    [[ "$before" == "$after" ]] ||
        remote_test_fail "$1:REMOTE_REPOSITORY_WAS_MODIFIED"
}

expect_blocked() {
    local label="$1"
    local reason="$2"
    local rc="$3"

    remote_test_expect_rc "$rc" "$label"
    remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "$label"
    remote_test_expect_out "CBS_REMOTE_REASON=$reason" "$label"
    remote_test_expect_err "CBS_REMOTE_ERROR=$reason" "$label"
    remote_test_expect_no_out "CBS_REMOTE_RESULT=PASS" "$label"
}

# --- PASS

remote_test_scenario
check "PASS_LOCAL_HEAD"
remote_test_expect_rc 0 "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_OPERATION=check" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_CONNECTION=OK" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_REPOSITORY_STATE=READY" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_EXPECTED_BRANCH=main" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_OBSERVED_BRANCH=main" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_EXPECTED_COMMIT=$REMOTE_TEST_HEAD" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_OBSERVED_COMMIT=$REMOTE_TEST_HEAD" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_COMMIT_RELATION=EQUAL" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_WORKTREE_STATE=CLEAN" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_ENTRYPOINT_STATE=PRESENT" "PASS_LOCAL_HEAD"
remote_test_expect_out "CBS_REMOTE_RESULT=PASS" "PASS_LOCAL_HEAD"
remote_test_expect_ssh_count 1 "PASS_LOCAL_HEAD"

[[ "$(tail -n 1 <<<"$OUT")" == "CBS_REMOTE_RESULT=PASS" ]] ||
    remote_test_fail "PASS_RESULT_IS_LAST_LINE"

echo "TEST_REMOTE_CHECK_PASS_LOCAL_HEAD=PASS"

remote_test_scenario
M_COMMIT="$REMOTE_TEST_HEAD"
check "PASS_PINNED_COMMIT"
remote_test_expect_rc 0 "PASS_PINNED_COMMIT"
remote_test_expect_out "CBS_REMOTE_RESULT=PASS" "PASS_PINNED_COMMIT"

echo "TEST_REMOTE_CHECK_PASS_PINNED_COMMIT=PASS"

# The remote path may be a symbolic link to the repository.
remote_test_scenario
ln -s "$REMOTE_TEST_REMOTE" "$SCN/link to repo"
M_REPOSITORY="$SCN/link to repo"
check "PASS_SYMLINKED_PATH"
remote_test_expect_rc 0 "PASS_SYMLINKED_PATH"

echo "TEST_REMOTE_CHECK_PASS_SYMLINKED_PATH=PASS"

# --- host unavailable

remote_test_scenario
export FAKE_SSH_MODE=unreachable
check "HOST_UNREACHABLE"
expect_blocked "HOST_UNREACHABLE" "HOST_UNREACHABLE" "$CBS_RC_REMOTE_HOST_UNREACHABLE"
remote_test_expect_out "CBS_REMOTE_CONNECTION=UNREACHABLE" "HOST_UNREACHABLE"
remote_test_expect_out "CBS_REMOTE_SSH_RC=255" "HOST_UNREACHABLE"
remote_test_expect_err "Connection refused" "HOST_UNREACHABLE_DIAGNOSTIC_PRESERVED"
remote_test_expect_ssh_count 1 "HOST_UNREACHABLE"

echo "TEST_REMOTE_CHECK_HOST_UNREACHABLE=PASS"

remote_test_scenario
export FAKE_SSH_MODE=hostkey
check "HOST_KEY_REFUSED"
expect_blocked "HOST_KEY_REFUSED" "HOST_UNREACHABLE" "$CBS_RC_REMOTE_HOST_UNREACHABLE"
remote_test_expect_err "Host key verification failed." "HOST_KEY_DIAGNOSTIC_PRESERVED"

echo "TEST_REMOTE_CHECK_HOST_KEY_REFUSED=PASS"

remote_test_scenario
export FAKE_SSH_EXPECT_DESTINATION="another-host"
check "UNKNOWN_DESTINATION"
expect_blocked "UNKNOWN_DESTINATION" "HOST_UNREACHABLE" "$CBS_RC_REMOTE_HOST_UNREACHABLE"

echo "TEST_REMOTE_CHECK_UNKNOWN_DESTINATION=PASS"

# --- wrong commit: every relation is detected and refused

remote_test_scenario
remote_test_commit "$REMOTE_TEST_LOCAL" "local-only"
check "COMMIT_UNKNOWN_OBJECT"
expect_blocked "COMMIT_UNKNOWN_OBJECT" "COMMIT_MISMATCH" "$CBS_RC_REMOTE_COMMIT_MISMATCH"
remote_test_expect_out "CBS_REMOTE_COMMIT_RELATION=UNKNOWN_OBJECT" "COMMIT_UNKNOWN_OBJECT"
remote_test_expect_out "CBS_REMOTE_OBSERVED_COMMIT=$REMOTE_TEST_HEAD" "COMMIT_UNKNOWN_OBJECT"

echo "TEST_REMOTE_CHECK_COMMIT_UNKNOWN_OBJECT=PASS"

remote_test_scenario
remote_test_commit "$REMOTE_TEST_LOCAL" "local-only"
remote_test_git -C "$REMOTE_TEST_REMOTE" fetch -q "$REMOTE_TEST_LOCAL" main
check "COMMIT_BEHIND"
expect_blocked "COMMIT_BEHIND" "COMMIT_MISMATCH" "$CBS_RC_REMOTE_COMMIT_MISMATCH"
remote_test_expect_out "CBS_REMOTE_COMMIT_RELATION=BEHIND" "COMMIT_BEHIND"

echo "TEST_REMOTE_CHECK_COMMIT_BEHIND=PASS"

remote_test_scenario
remote_test_commit "$REMOTE_TEST_REMOTE" "remote-only"
check "COMMIT_AHEAD"
expect_blocked "COMMIT_AHEAD" "COMMIT_MISMATCH" "$CBS_RC_REMOTE_COMMIT_MISMATCH"
remote_test_expect_out "CBS_REMOTE_COMMIT_RELATION=AHEAD" "COMMIT_AHEAD"

echo "TEST_REMOTE_CHECK_COMMIT_AHEAD=PASS"

remote_test_scenario
remote_test_commit "$REMOTE_TEST_LOCAL" "local-side"
remote_test_commit "$REMOTE_TEST_REMOTE" "remote-side"
remote_test_git -C "$REMOTE_TEST_REMOTE" fetch -q "$REMOTE_TEST_LOCAL" main
check "COMMIT_DIVERGED"
expect_blocked "COMMIT_DIVERGED" "COMMIT_MISMATCH" "$CBS_RC_REMOTE_COMMIT_MISMATCH"
remote_test_expect_out "CBS_REMOTE_COMMIT_RELATION=DIVERGED" "COMMIT_DIVERGED"

echo "TEST_REMOTE_CHECK_COMMIT_DIVERGED=PASS"

remote_test_scenario
M_COMMIT="0123456789abcdef0123456789abcdef01234567"
check "COMMIT_PINNED_WRONG"
expect_blocked "COMMIT_PINNED_WRONG" "COMMIT_MISMATCH" "$CBS_RC_REMOTE_COMMIT_MISMATCH"
remote_test_expect_out "CBS_REMOTE_EXPECTED_COMMIT=0123456789abcdef0123456789abcdef01234567" "COMMIT_PINNED_WRONG"

echo "TEST_REMOTE_CHECK_COMMIT_PINNED_WRONG=PASS"

remote_test_scenario
M_LOCAL_REPOSITORY="$SCN/no-such-local-repository"
check "LOCAL_REFERENCE_UNAVAILABLE"
expect_blocked "LOCAL_REFERENCE_UNAVAILABLE" "LOCAL_REFERENCE_UNAVAILABLE" "$CBS_RC_REMOTE_LOCAL_REFERENCE_UNAVAILABLE"
remote_test_expect_ssh_count 0 "LOCAL_REFERENCE_UNAVAILABLE_NO_NETWORK"

echo "TEST_REMOTE_CHECK_LOCAL_REFERENCE_UNAVAILABLE=PASS"

# --- wrong branch

remote_test_scenario
remote_test_git -C "$REMOTE_TEST_REMOTE" checkout -q -b feature
check "BRANCH_MISMATCH"
expect_blocked "BRANCH_MISMATCH" "BRANCH_MISMATCH" "$CBS_RC_REMOTE_BRANCH_MISMATCH"
remote_test_expect_out "CBS_REMOTE_OBSERVED_BRANCH=feature" "BRANCH_MISMATCH"
remote_test_expect_out "CBS_REMOTE_COMMIT_RELATION=EQUAL" "BRANCH_MISMATCH"

echo "TEST_REMOTE_CHECK_BRANCH_MISMATCH=PASS"

remote_test_scenario
remote_test_git -C "$REMOTE_TEST_REMOTE" checkout -q --detach
check "DETACHED_HEAD"
expect_blocked "DETACHED_HEAD" "BRANCH_MISMATCH" "$CBS_RC_REMOTE_BRANCH_MISMATCH"
remote_test_expect_out "CBS_REMOTE_OBSERVED_BRANCH=DETACHED" "DETACHED_HEAD"

echo "TEST_REMOTE_CHECK_DETACHED_HEAD=PASS"

# --- dirty repository (nothing is cleaned or reset)

remote_test_scenario
printf 'scratch\n' > "$REMOTE_TEST_REMOTE/untracked.txt"
check "DIRTY_UNTRACKED"
expect_blocked "DIRTY_UNTRACKED" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
remote_test_expect_out "CBS_REMOTE_WORKTREE_STATE=DIRTY" "DIRTY_UNTRACKED"
[[ -f "$REMOTE_TEST_REMOTE/untracked.txt" ]] ||
    remote_test_fail "DIRTY_UNTRACKED_FILE_WAS_REMOVED"

echo "TEST_REMOTE_CHECK_DIRTY_UNTRACKED=PASS"

remote_test_scenario
printf 'changed\n' >> "$REMOTE_TEST_REMOTE/bin/cbs"
check "DIRTY_MODIFIED"
expect_blocked "DIRTY_MODIFIED" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
grep -Fxq 'changed' "$REMOTE_TEST_REMOTE/bin/cbs" ||
    remote_test_fail "DIRTY_MODIFICATION_WAS_REVERTED"

echo "TEST_REMOTE_CHECK_DIRTY_MODIFIED=PASS"

remote_test_scenario
printf 'staged\n' > "$REMOTE_TEST_REMOTE/staged.txt"
remote_test_git -C "$REMOTE_TEST_REMOTE" add staged.txt
check "DIRTY_STAGED"
expect_blocked "DIRTY_STAGED" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"

echo "TEST_REMOTE_CHECK_DIRTY_STAGED=PASS"

# Simulated Git whose status fails: the worktree must not be assumed clean.
remote_test_scenario
M_EXTRA="CBS_REMOTE_PATH_PREPEND=$REMOTE_TEST_LIB_DIR/git-status-fails"
check "WORKTREE_UNKNOWN"
expect_blocked "WORKTREE_UNKNOWN" "WORKTREE_UNKNOWN" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
remote_test_expect_out "CBS_REMOTE_WORKTREE_STATE=UNKNOWN" "WORKTREE_UNKNOWN"

echo "TEST_REMOTE_CHECK_WORKTREE_UNKNOWN_SIMULATED_GIT=PASS"

# --- repository identity

remote_test_scenario
remote_test_git -C "$REMOTE_TEST_REMOTE" remote set-url origin "git@example.invalid:someone/else.git"
check "ORIGIN_MISMATCH"
expect_blocked "ORIGIN_MISMATCH" "REPOSITORY_ORIGIN_MISMATCH" "$CBS_REPOSITORY_RC_REMOTE_MISMATCH"
remote_test_expect_out "CBS_REMOTE_REPOSITORY_STATE=REMOTE_MISMATCH" "ORIGIN_MISMATCH"

echo "TEST_REMOTE_CHECK_ORIGIN_MISMATCH=PASS"

remote_test_scenario
remote_test_git -C "$REMOTE_TEST_REMOTE" remote remove origin
check "ORIGIN_ABSENT"
expect_blocked "ORIGIN_ABSENT" "REPOSITORY_ORIGIN_MISMATCH" "$CBS_REPOSITORY_RC_REMOTE_MISMATCH"

echo "TEST_REMOTE_CHECK_ORIGIN_ABSENT=PASS"

# An origin carrying credentials must never be displayed.
remote_test_scenario
remote_test_git -C "$REMOTE_TEST_REMOTE" remote set-url origin "https://deploy:s3cr3t-token@example.invalid/cbs/remote-fixture.git"
check "ORIGIN_CREDENTIALS_REDACTED"
expect_blocked "ORIGIN_CREDENTIALS_REDACTED" "REPOSITORY_ORIGIN_MISMATCH" "$CBS_REPOSITORY_RC_REMOTE_MISMATCH"

if grep -Fq 's3cr3t' <<<"$OUT$ERR"; then
    remote_test_fail "CREDENTIALS_DISPLAYED"
fi

remote_test_expect_out "CBS_REMOTE_REPOSITORY_OBSERVED_ORIGIN=https://***@example.invalid/cbs/remote-fixture.git" "ORIGIN_CREDENTIALS_REDACTED"

echo "TEST_REMOTE_CHECK_CREDENTIALS_REDACTED=PASS"

remote_test_scenario
M_REPOSITORY="$REMOTE_TEST_REMOTE_FS/does not exist"
check "REPOSITORY_MISSING"
expect_blocked "REPOSITORY_MISSING" "REPOSITORY_MISSING" "$CBS_REPOSITORY_RC_MISSING"
remote_test_expect_out "CBS_REMOTE_REPOSITORY_STATE=MISSING" "REPOSITORY_MISSING"
[[ ! -e "$REMOTE_TEST_REMOTE_FS/does not exist" ]] ||
    remote_test_fail "MISSING_REPOSITORY_WAS_CREATED"

echo "TEST_REMOTE_CHECK_REPOSITORY_MISSING=PASS"

remote_test_scenario
mkdir -p "$REMOTE_TEST_REMOTE_FS/plain directory"
M_REPOSITORY="$REMOTE_TEST_REMOTE_FS/plain directory"
check "REPOSITORY_NOT_GIT"
expect_blocked "REPOSITORY_NOT_GIT" "REPOSITORY_NOT_GIT" "$CBS_REPOSITORY_RC_NOT_GIT"
remote_test_expect_out "CBS_REMOTE_REPOSITORY_STATE=NOT_GIT" "REPOSITORY_NOT_GIT"

echo "TEST_REMOTE_CHECK_REPOSITORY_NOT_GIT=PASS"

remote_test_scenario
printf 'x\n' > "$REMOTE_TEST_REMOTE_FS/a file"
M_REPOSITORY="$REMOTE_TEST_REMOTE_FS/a file"
check "REPOSITORY_IS_A_FILE"
expect_blocked "REPOSITORY_IS_A_FILE" "REPOSITORY_NOT_GIT" "$CBS_REPOSITORY_RC_NOT_GIT"

echo "TEST_REMOTE_CHECK_REPOSITORY_IS_A_FILE=PASS"

# A subdirectory of the right repository is not the repository.
remote_test_scenario
mkdir -p "$REMOTE_TEST_REMOTE/bin/nested"
M_REPOSITORY="$REMOTE_TEST_REMOTE/bin"
check "REPOSITORY_SUBDIRECTORY"
expect_blocked "REPOSITORY_SUBDIRECTORY" "REPOSITORY_NOT_GIT" "$CBS_REPOSITORY_RC_NOT_GIT"

echo "TEST_REMOTE_CHECK_REPOSITORY_SUBDIRECTORY=PASS"

# --- remote tooling

remote_test_scenario
export FAKE_SSH_MODE=nogit
check "REMOTE_GIT_UNAVAILABLE"
expect_blocked "REMOTE_GIT_UNAVAILABLE" "REMOTE_GIT_UNAVAILABLE" "$CBS_RC_REMOTE_REMOTE_GIT_UNAVAILABLE"

echo "TEST_REMOTE_CHECK_REMOTE_GIT_UNAVAILABLE=PASS"

remote_test_scenario
M_EXTRA="CBS_REMOTE_CBS_ENTRYPOINT=bin/missing"
check "ENTRYPOINT_MISSING"
expect_blocked "ENTRYPOINT_MISSING" "ENTRYPOINT_UNAVAILABLE" "$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE"
remote_test_expect_out "CBS_REMOTE_ENTRYPOINT_STATE=MISSING" "ENTRYPOINT_MISSING"

echo "TEST_REMOTE_CHECK_ENTRYPOINT_MISSING=PASS"

remote_test_scenario
remote_test_git -C "$REMOTE_TEST_REMOTE" config core.fileMode false
chmod 0644 "$REMOTE_TEST_REMOTE/bin/cbs"
check "ENTRYPOINT_NOT_EXECUTABLE"
expect_blocked "ENTRYPOINT_NOT_EXECUTABLE" "ENTRYPOINT_UNAVAILABLE" "$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE"
remote_test_expect_out "CBS_REMOTE_ENTRYPOINT_STATE=NOT_EXECUTABLE" "ENTRYPOINT_NOT_EXECUTABLE"

echo "TEST_REMOTE_CHECK_ENTRYPOINT_NOT_EXECUTABLE=PASS"

# --- probe malfunctions are FAIL, not PASS and not silently BLOCKED

remote_test_scenario
export FAKE_SSH_MODE=garbage
check "PROBE_GARBAGE"
remote_test_expect_rc "$CBS_RC_REMOTE_PROBE_FAILED" "PROBE_GARBAGE"
remote_test_expect_out "CBS_REMOTE_RESULT=FAIL" "PROBE_GARBAGE"
remote_test_expect_out "CBS_REMOTE_REASON=PROBE_FAILED" "PROBE_GARBAGE"

echo "TEST_REMOTE_CHECK_PROBE_GARBAGE=PASS"

remote_test_scenario
export FAKE_SSH_MODE=probe-fail
check "PROBE_FAILURE"
remote_test_expect_rc "$CBS_RC_REMOTE_PROBE_FAILED" "PROBE_FAILURE"
remote_test_expect_out "CBS_REMOTE_RESULT=FAIL" "PROBE_FAILURE"
remote_test_expect_out "CBS_REMOTE_SSH_RC=3" "PROBE_FAILURE"
remote_test_expect_err "FAKE_SSH_REMOTE_DIAGNOSTIC=probe exploded" "PROBE_FAILURE_DIAGNOSTIC_PRESERVED"

echo "TEST_REMOTE_CHECK_PROBE_FAILURE=PASS"

# --- local prerequisites

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
MINIMAL_PATH="$SCN/minimal-path"
mkdir -p "$MINIMAL_PATH"
for tool in bash env dirname cat rm mktemp git; do
    ln -s "$(command -v "$tool")" "$MINIMAL_PATH/$tool"
done
remote_test_run env PATH="$MINIMAL_PATH" "$CBS" remote check "$MANIFEST"
expect_blocked "LOCAL_SSH_UNAVAILABLE" "LOCAL_SSH_UNAVAILABLE" "$CBS_RC_REMOTE_LOCAL_SSH_UNAVAILABLE"

echo "TEST_REMOTE_CHECK_LOCAL_SSH_UNAVAILABLE=PASS"

# --- manifest and usage errors never reach the network

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
printf 'CBS_REMOTE_UNKNOWN=1\n' >> "$MANIFEST"
remote_test_run "$CBS" remote check "$MANIFEST"
expect_blocked "MANIFEST_INVALID" "MANIFEST_INVALID" "$CBS_RC_REMOTE_MANIFEST_INVALID"
remote_test_expect_err "CBS_REMOTE_MANIFEST_ERROR=UNKNOWN_KEY" "MANIFEST_INVALID"
remote_test_expect_ssh_count 0 "MANIFEST_INVALID"

remote_test_run "$CBS" remote check "$SCN/missing.env"
expect_blocked "MANIFEST_MISSING" "MANIFEST_INVALID" "$CBS_RC_REMOTE_MANIFEST_INVALID"
remote_test_expect_ssh_count 0 "MANIFEST_MISSING"

remote_test_run "$CBS" remote check
expect_blocked "USAGE_NO_MANIFEST" "USAGE" "$CBS_RC_REMOTE_USAGE"
remote_test_expect_ssh_count 0 "USAGE_NO_MANIFEST"

remote_test_run "$CBS" remote check "$MANIFEST" extra
expect_blocked "USAGE_EXTRA_ARGUMENT" "USAGE" "$CBS_RC_REMOTE_USAGE"
remote_test_expect_ssh_count 0 "USAGE_EXTRA_ARGUMENT"

echo "TEST_REMOTE_CHECK_MANIFEST_AND_USAGE_ERRORS=PASS"

# --- check never executes anything and never uses the launcher

remote_test_scenario
remote_test_arm_marker
check "CHECK_EXECUTES_NOTHING"
remote_test_expect_rc 0 "CHECK_EXECUTES_NOTHING"
remote_test_expect_ssh_count 1 "CHECK_EXECUTES_NOTHING"
remote_test_expect_no_out "CBS_REMOTE_ACTION_EXECUTION=START" "CHECK_EXECUTES_NOTHING"
if remote_test_marker_present; then
    remote_test_fail "CHECK_STARTED_THE_ENTRYPOINT"
fi
if grep -Fq 'exec ' "$FAKE_SSH_STATE/command.1" ||
    grep -Fq 'CBS_REMOTE_LAUNCH' "$FAKE_SSH_STATE/command.1"
then
    remote_test_fail "CHECK_SENT_THE_LAUNCHER"
fi
if grep -Fq 'CBS_REMOTE_LAUNCH_' <<<"$OUT"; then
    remote_test_fail "CHECK_REPORTED_A_LAUNCH_VERDICT"
fi

echo "TEST_REMOTE_CHECK_EXECUTES_NOTHING=PASS"

# --- the state is observed at each call: a change after a PASS is detected

for change in dirty branch commit origin; do
    remote_test_scenario
    check "SEQUENCE_FIRST:$change"
    remote_test_expect_rc 0 "SEQUENCE_FIRST:$change"

    case "$change" in
        dirty)
            printf 'x\n' > "$REMOTE_TEST_REMOTE/after.txt"
            reason="WORKTREE_DIRTY"
            code="$CBS_RC_REMOTE_WORKTREE_DIRTY"
            ;;
        branch)
            remote_test_git -C "$REMOTE_TEST_REMOTE" checkout -q -b after
            reason="BRANCH_MISMATCH"
            code="$CBS_RC_REMOTE_BRANCH_MISMATCH"
            ;;
        commit)
            remote_test_commit "$REMOTE_TEST_REMOTE" "after"
            reason="COMMIT_MISMATCH"
            code="$CBS_RC_REMOTE_COMMIT_MISMATCH"
            ;;
        origin)
            remote_test_git -C "$REMOTE_TEST_REMOTE" remote set-url origin "git@example.invalid:other/repo.git"
            reason="REPOSITORY_ORIGIN_MISMATCH"
            code="$CBS_REPOSITORY_RC_REMOTE_MISMATCH"
            ;;
    esac

    check "SEQUENCE_SECOND:$change"
    expect_blocked "SEQUENCE_SECOND:$change" "$reason" "$code"
done

echo "TEST_REMOTE_CHECK_CHANGE_AFTER_PASS=PASS"

# --- PASS and BLOCKED are exclusive: a PASS is only emitted with rc 0

remote_test_scenario
check "FINAL_PASS_COHERENCE"
remote_test_expect_rc 0 "FINAL_PASS_COHERENCE"
[[ "$(grep -c '^CBS_REMOTE_RESULT=' <<<"$OUT")" -eq 1 ]] ||
    remote_test_fail "EXACTLY_ONE_RESULT_LINE"

echo "TEST_REMOTE_CHECK_SINGLE_RESULT_LINE=PASS"

echo "TEST_REMOTE_CHECK_RESULT=PASS"
