#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/tests/fixtures/remote/lib.sh"
source "$ROOT/cbs/remote/contract.sh"
source "$ROOT/cbs/workspace/repository_contract.sh"

REMOTE_TEST_PREFIX="TEST_REMOTE_RUN"

# Runs "cbs remote run" and verifies that the remote repository is unchanged.
run() {
    local action="$1"
    local before
    local after

    remote_test_write_manifest "$MANIFEST"

    before="$(remote_test_remote_state)"
    remote_test_run "$CBS" remote run "$MANIFEST" "$action"
    after="$(remote_test_remote_state)"

    [[ "$before" == "$after" ]] ||
        remote_test_fail "$action:REMOTE_REPOSITORY_WAS_MODIFIED"
}

expect_blocked() {
    local label="$1"
    local reason="$2"
    local rc="$3"

    remote_test_expect_rc "$rc" "$label"
    remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "$label"
    remote_test_expect_out "CBS_REMOTE_REASON=$reason" "$label"
    remote_test_expect_no_out "CBS_REMOTE_ACTION_EXECUTION=START" "$label"
}

# --- PASS

remote_test_scenario
run show_version
remote_test_expect_rc 0 "PASS"
remote_test_expect_out "CBS_REMOTE_OPERATION=run" "PASS"
remote_test_expect_out "CBS_REMOTE_ACTION=show_version" "PASS"
remote_test_expect_out "CBS_REMOTE_ACTION_COMMAND=cbs version" "PASS"
remote_test_expect_out "CBS_REMOTE_ACTION_EXECUTION=START" "PASS"
remote_test_expect_out "FIXTURE_CBS_ARGC=1" "PASS"
remote_test_expect_out "FIXTURE_CBS_ARG_0=version" "PASS"
remote_test_expect_out "CBS_REMOTE_ACTION_RC=0" "PASS"
remote_test_expect_out "CBS_REMOTE_RESULT=PASS" "PASS"
remote_test_expect_no_out "CBS_REMOTE_RESULT=BLOCKED" "PASS"
remote_test_expect_no_out "CBS_REMOTE_RESULT=FAIL" "PASS"

# One read-only probe, then one launch.
remote_test_expect_ssh_count 2 "PASS"

[[ "$(tail -n 1 <<<"$OUT")" == "CBS_REMOTE_RESULT=PASS" ]] ||
    remote_test_fail "PASS_RESULT_IS_LAST_LINE"

# The probe precedes the execution in the output.
PROBE_LINE="$(grep -n '^CBS_REMOTE_ENTRYPOINT_STATE=PRESENT$' <<<"$OUT" | cut -d: -f1)"
START_LINE="$(grep -n '^CBS_REMOTE_ACTION_EXECUTION=START$' <<<"$OUT" | cut -d: -f1)"
[[ "$PROBE_LINE" -lt "$START_LINE" ]] ||
    remote_test_fail "VERIFICATION_DOES_NOT_PRECEDE_EXECUTION"

echo "TEST_REMOTE_RUN_PASS=PASS"

# --- reliable transmission of the working directory and the arguments

remote_test_scenario
run show_args
remote_test_expect_rc 0 "ARGUMENTS"
remote_test_expect_out "FIXTURE_CBS_PWD=$REMOTE_TEST_REMOTE" "ARGUMENTS_WORKING_DIRECTORY_WITH_SPACE"
remote_test_expect_out "FIXTURE_CBS_ARGC=4" "ARGUMENTS"
remote_test_expect_out "FIXTURE_CBS_ARG_0=stack" "ARGUMENTS"
remote_test_expect_out "FIXTURE_CBS_ARG_1=environment" "ARGUMENTS"
remote_test_expect_out "FIXTURE_CBS_ARG_2=stacks/flutter/stack.env" "ARGUMENTS"
remote_test_expect_out "FIXTURE_CBS_ARG_3=a=b,c%d+e@f:g" "ARGUMENTS"

# The launch command received by ssh quotes every word individually.
LAUNCH="$(cat "$FAKE_SSH_STATE/command.2")"

[[ "$LAUNCH" == *" sh '' '$REMOTE_TEST_REMOTE' '$REMOTE_TEST_ORIGIN' 'main' '$REMOTE_TEST_HEAD' 'bin/cbs' 'stack' 'environment' 'stacks/flutter/stack.env' 'a=b,c%d+e@f:g'" ]] ||
    remote_test_fail "LAUNCH_COMMAND_NOT_FULLY_QUOTED:$LAUNCH"

echo "TEST_REMOTE_RUN_ARGUMENTS=PASS"

# Accepted characters that are special in some shells (% = @ + , :) must
# reach the remote entrypoint untouched. Glob, tilde, quote and expansion
# characters are refused at manifest level (see test_remote_manifest.sh).
remote_test_scenario
M_ALLOWED="meta"
M_EXTRA='CBS_REMOTE_ACTION_META_COMMAND=version %s%d =x,y:z @home +plus a%20b'
remote_test_write_manifest "$MANIFEST"
sed -i '/^CBS_REMOTE_ACTION_SHOW_/d' "$MANIFEST"
remote_test_run "$CBS" remote run "$MANIFEST" meta
remote_test_expect_rc 0 "META"
remote_test_expect_out "FIXTURE_CBS_ARGC=6" "META"
remote_test_expect_out "FIXTURE_CBS_ARG_1=%s%d" "META"
remote_test_expect_out "FIXTURE_CBS_ARG_2==x,y:z" "META"
remote_test_expect_out "FIXTURE_CBS_ARG_3=@home" "META"
remote_test_expect_out "FIXTURE_CBS_ARG_4=+plus" "META"
remote_test_expect_out "FIXTURE_CBS_ARG_5=a%20b" "META"

echo "TEST_REMOTE_RUN_METACHARACTER_ARGUMENTS=PASS"

# --- return codes and diagnostics are preserved

remote_test_scenario
run show_fail
remote_test_expect_rc 7 "COMMAND_FAILURE"
remote_test_expect_out "CBS_REMOTE_ACTION_RC=7" "COMMAND_FAILURE"
remote_test_expect_out "CBS_REMOTE_RESULT=FAIL" "COMMAND_FAILURE"
remote_test_expect_out "CBS_REMOTE_REASON=REMOTE_ACTION_FAILED" "COMMAND_FAILURE"
remote_test_expect_out "FIXTURE_CBS_ARG_0=status" "COMMAND_FAILURE_STDOUT_PRESERVED"
remote_test_expect_no_out "CBS_REMOTE_RESULT=PASS" "COMMAND_FAILURE"

# The remote diagnostic stays on standard error, it is not merged into stdout.
remote_test_expect_err "FIXTURE_CBS_STDERR_DIAGNOSTIC=status refused" "COMMAND_FAILURE_STDERR_PRESERVED"
remote_test_expect_err "CBS_REMOTE_ERROR=REMOTE_ACTION_FAILED" "COMMAND_FAILURE"
if grep -Fq 'FIXTURE_CBS_STDERR_DIAGNOSTIC' <<<"$OUT"; then
    remote_test_fail "COMMAND_FAILURE_STDERR_MERGED_INTO_STDOUT"
fi

echo "TEST_REMOTE_RUN_COMMAND_FAILURE_RC7=PASS"

remote_test_scenario
run show_exit42
remote_test_expect_rc 42 "COMMAND_FAILURE_42"
remote_test_expect_out "CBS_REMOTE_ACTION_RC=42" "COMMAND_FAILURE_42"
remote_test_expect_out "FIXTURE_CBS_STDOUT_BEFORE_FAILURE=yes" "COMMAND_FAILURE_42_STDOUT_PRESERVED"
remote_test_expect_out "CBS_REMOTE_RESULT=FAIL" "COMMAND_FAILURE_42"

echo "TEST_REMOTE_RUN_COMMAND_FAILURE_RC42=PASS"

# A broken connection after verification is a FAIL carrying the ssh status.
remote_test_scenario
export FAKE_SSH_FAIL_ON_CALL=2
run show_version
remote_test_expect_rc 255 "TRANSPORT_FAILURE"
remote_test_expect_out "CBS_REMOTE_ACTION_RC=255" "TRANSPORT_FAILURE"
remote_test_expect_out "CBS_REMOTE_RESULT=FAIL" "TRANSPORT_FAILURE"
remote_test_expect_out "CBS_REMOTE_REASON=TRANSPORT_FAILURE" "TRANSPORT_FAILURE"
remote_test_expect_err "Broken pipe" "TRANSPORT_FAILURE_DIAGNOSTIC_PRESERVED"
# No launcher verdict was received: nothing proves whether the action started.
remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=NOT_REPORTED" "TRANSPORT_FAILURE_NO_VERDICT"
remote_test_expect_out "CBS_REMOTE_DIAGNOSTIC=SSH_STATUS_255_NO_LAUNCHER_VERDICT" "TRANSPORT_FAILURE_NO_VERDICT"
remote_test_expect_no_out "CBS_REMOTE_ACTION_EXECUTION=START" "TRANSPORT_FAILURE_NO_VERDICT"

echo "TEST_REMOTE_RUN_TRANSPORT_FAILURE=PASS"

# --- action allow-list: refused before any network access

for forbidden in \
    deploy \
    shell \
    rm \
    show_versions \
    SHOW_VERSION \
    "show_version;touch $TMP/pwned" \
    "show_version\$(touch $TMP/pwned2)" \
    '../show_version' \
    '--help' \
    '-n' \
    'show version' \
    'show_version ' \
    'bash -c id'
do
    remote_test_scenario
    run "$forbidden"
    expect_blocked "ACTION_FORBIDDEN:$forbidden" "ACTION_NOT_ALLOWED" "$CBS_RC_REMOTE_ACTION_NOT_ALLOWED"
    remote_test_expect_ssh_count 0 "ACTION_FORBIDDEN_NO_NETWORK:$forbidden"
    remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "ACTION_FORBIDDEN:$forbidden"
done

[[ ! -e "$TMP/pwned" && ! -e "$TMP/pwned2" ]] ||
    remote_test_fail "ACTION_NAME_WAS_EXECUTED"

# A hostile action name is never echoed back.
remote_test_scenario
run 'x$(id)'
remote_test_expect_out "CBS_REMOTE_ACTION=INVALID" "HOSTILE_ACTION_NAME_NOT_ECHOED"
if grep -Fq 'x$(id)' <<<"$OUT"; then
    remote_test_fail "HOSTILE_ACTION_NAME_ECHOED"
fi

# A declared command whose action is not in the allow-list is still refused.
remote_test_scenario
M_ALLOWED="show_version"
remote_test_write_manifest "$MANIFEST"
sed -i '/^CBS_REMOTE_ACTION_SHOW_\(ARGS\|FAIL\|EXIT42\)_COMMAND=/d' "$MANIFEST"
remote_test_run "$CBS" remote run "$MANIFEST" show_exit42
expect_blocked "ACTION_NOT_IN_ALLOW_LIST" "ACTION_NOT_ALLOWED" "$CBS_RC_REMOTE_ACTION_NOT_ALLOWED"
remote_test_expect_ssh_count 0 "ACTION_NOT_IN_ALLOW_LIST"

echo "TEST_REMOTE_RUN_ACTION_NOT_ALLOWED=PASS"

# --- nothing is executed when a precondition fails

remote_test_scenario
printf 'scratch\n' > "$REMOTE_TEST_REMOTE/untracked.txt"
run show_version
expect_blocked "DIRTY" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
remote_test_expect_ssh_count 1 "DIRTY_PROBE_ONLY"
remote_test_expect_no_out "FIXTURE_CBS_ARGC=1" "DIRTY_NOT_EXECUTED"
[[ -f "$REMOTE_TEST_REMOTE/untracked.txt" ]] ||
    remote_test_fail "DIRTY_FILE_WAS_REMOVED"

echo "TEST_REMOTE_RUN_DIRTY_NOT_EXECUTED=PASS"

remote_test_scenario
remote_test_commit "$REMOTE_TEST_REMOTE" "remote-only"
run show_version
expect_blocked "WRONG_COMMIT" "COMMIT_MISMATCH" "$CBS_RC_REMOTE_COMMIT_MISMATCH"
remote_test_expect_ssh_count 1 "WRONG_COMMIT_PROBE_ONLY"
remote_test_expect_out "CBS_REMOTE_COMMIT_RELATION=AHEAD" "WRONG_COMMIT"

echo "TEST_REMOTE_RUN_WRONG_COMMIT_NOT_EXECUTED=PASS"

remote_test_scenario
remote_test_git -C "$REMOTE_TEST_REMOTE" checkout -q -b feature
run show_version
expect_blocked "WRONG_BRANCH" "BRANCH_MISMATCH" "$CBS_RC_REMOTE_BRANCH_MISMATCH"
remote_test_expect_ssh_count 1 "WRONG_BRANCH_PROBE_ONLY"

echo "TEST_REMOTE_RUN_WRONG_BRANCH_NOT_EXECUTED=PASS"

remote_test_scenario
remote_test_git -C "$REMOTE_TEST_REMOTE" remote set-url origin "git@example.invalid:someone/else.git"
run show_version
expect_blocked "WRONG_ORIGIN" "REPOSITORY_ORIGIN_MISMATCH" "$CBS_REPOSITORY_RC_REMOTE_MISMATCH"
remote_test_expect_ssh_count 1 "WRONG_ORIGIN_PROBE_ONLY"

echo "TEST_REMOTE_RUN_WRONG_ORIGIN_NOT_EXECUTED=PASS"

remote_test_scenario
export FAKE_SSH_MODE=unreachable
run show_version
expect_blocked "HOST_UNREACHABLE" "HOST_UNREACHABLE" "$CBS_RC_REMOTE_HOST_UNREACHABLE"
remote_test_expect_ssh_count 1 "HOST_UNREACHABLE_SINGLE_ATTEMPT"
remote_test_expect_err "Connection refused" "HOST_UNREACHABLE_DIAGNOSTIC_PRESERVED"

echo "TEST_REMOTE_RUN_HOST_UNREACHABLE_NOT_EXECUTED=PASS"

remote_test_scenario
M_EXTRA="CBS_REMOTE_CBS_ENTRYPOINT=bin/missing"
run show_version
expect_blocked "ENTRYPOINT_MISSING" "ENTRYPOINT_UNAVAILABLE" "$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE"
remote_test_expect_ssh_count 1 "ENTRYPOINT_MISSING_PROBE_ONLY"

echo "TEST_REMOTE_RUN_ENTRYPOINT_MISSING_NOT_EXECUTED=PASS"

# --- revalidation by the launcher, in the same SSH session, before exec
#
# The simulated ssh runs FAKE_SSH_HOOK just before the second session (the
# launch) executes its remote command, i.e. after the first probe passed. The
# remote repository is therefore modified between verification and launch.

# Runs "show_version" with a remote modification injected before the launch.
# Arguments: LABEL HOOK_SHELL_TEXT
run_with_late_change() {
    local label="$1"
    local hook="$2"

    HOOK_REPO="$REMOTE_TEST_REMOTE"
    export HOOK_REPO

    FAKE_SSH_HOOK_ON_CALL=2
    FAKE_SSH_HOOK="$hook"
    export FAKE_SSH_HOOK_ON_CALL FAKE_SSH_HOOK

    remote_test_arm_marker
    remote_test_write_manifest "$MANIFEST"
    remote_test_run "$CBS" remote run "$MANIFEST" show_version
}

# A launch refused by the launcher: BLOCKED, entrypoint never started.
expect_launch_refused() {
    local label="$1"
    local reason="$2"
    local rc="$3"

    expect_blocked "$label" "$reason" "$rc"
    remote_test_expect_err "CBS_REMOTE_ERROR=$reason" "$label"

    # The first probe passed, the launcher refused: exactly two sessions.
    remote_test_expect_ssh_count 2 "${label}_TWO_SESSIONS"
    remote_test_expect_out "CBS_REMOTE_ENTRYPOINT_STATE=PRESENT" "${label}_PROBE_PASSED"
    remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED" "$label"
    remote_test_expect_out "CBS_REMOTE_LAUNCH_REFUSAL=$reason" "$label"

    # Nothing was executed.
    remote_test_expect_no_out "CBS_REMOTE_ACTION_EXECUTION=START" "${label}_NOT_STARTED"
    remote_test_expect_no_out "CBS_REMOTE_ACTION_RC=0" "${label}_NO_ACTION_RC"
    remote_test_expect_no_out "FIXTURE_CBS_ARGC=1" "${label}_NO_FIXTURE_OUTPUT"
    remote_test_expect_no_out "CBS_REMOTE_RESULT=PASS" "${label}_NOT_PASS"
    if remote_test_marker_present; then
        remote_test_fail "${label}:ENTRYPOINT_WAS_STARTED"
    fi
    if grep -q 'FIXTURE_CBS_' <<<"$OUT$ERR"; then
        remote_test_fail "${label}:ENTRYPOINT_OUTPUT_SEEN"
    fi

    # No local resolution of the refusal into an action result.
    if grep -Fq 'CBS_REMOTE_DIAGNOSTIC=' <<<"$OUT"; then
        remote_test_fail "${label}:DIAGNOSTIC_ON_REFUSAL"
    fi
}

# Control: the hook runs but changes nothing: the launcher passes.
remote_test_scenario
run_with_late_change "LATE_NOOP" "true"
remote_test_expect_rc 0 "LATE_NOOP"
remote_test_expect_ssh_count 2 "LATE_NOOP"
remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=PASS" "LATE_NOOP"
remote_test_expect_out "CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=main" "LATE_NOOP"
remote_test_expect_out "CBS_REMOTE_LAUNCH_OBSERVED_COMMIT=$REMOTE_TEST_HEAD" "LATE_NOOP"
remote_test_expect_out "CBS_REMOTE_ACTION_EXECUTION=START" "LATE_NOOP"
remote_test_expect_out "CBS_REMOTE_RESULT=PASS" "LATE_NOOP"
remote_test_marker_present || remote_test_fail "LATE_NOOP:ENTRYPOINT_NOT_STARTED"

# The verdict precedes the action output.
VERDICT_LINE="$(grep -n '^CBS_REMOTE_LAUNCH_PREFLIGHT=PASS$' <<<"$OUT" | cut -d: -f1)"
FIXTURE_LINE="$(grep -n '^FIXTURE_CBS_ARGC=1$' <<<"$OUT" | cut -d: -f1)"
[[ "$VERDICT_LINE" -lt "$FIXTURE_LINE" ]] ||
    remote_test_fail "LATE_NOOP:VERDICT_DOES_NOT_PRECEDE_ACTION_OUTPUT"

echo "TEST_REMOTE_RUN_LAUNCHER_REVALIDATION_PASS=PASS"

# Worktree became dirty after the probe (untracked file).
remote_test_scenario
run_with_late_change "LATE_UNTRACKED" 'printf "late\n" > "$HOOK_REPO/late-untracked.txt"'
expect_launch_refused "LATE_UNTRACKED" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
[[ -f "$REMOTE_TEST_REMOTE/late-untracked.txt" ]] ||
    remote_test_fail "LATE_UNTRACKED:FILE_WAS_REMOVED"

# Worktree became dirty after the probe (tracked file modified).
remote_test_scenario
run_with_late_change "LATE_TRACKED" 'printf "# late edit\n" >> "$HOOK_REPO/bin/cbs"'
expect_launch_refused "LATE_TRACKED" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
[[ "$(tail -n 1 "$REMOTE_TEST_REMOTE/bin/cbs")" == "# late edit" ]] ||
    remote_test_fail "LATE_TRACKED:EDIT_WAS_REVERTED"

# Worktree became dirty after the probe (staged change).
remote_test_scenario
run_with_late_change "LATE_STAGED" 'printf "staged\n" > "$HOOK_REPO/staged.txt" && git -C "$HOOK_REPO" add staged.txt'
expect_launch_refused "LATE_STAGED" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
[[ -n "$(remote_test_git -C "$REMOTE_TEST_REMOTE" diff --cached --name-only)" ]] ||
    remote_test_fail "LATE_STAGED:INDEX_WAS_RESET"

# Branch changed after the probe.
remote_test_scenario
run_with_late_change "LATE_BRANCH" 'git -C "$HOOK_REPO" checkout -q -b late-feature'
expect_launch_refused "LATE_BRANCH" "BRANCH_MISMATCH" "$CBS_RC_REMOTE_BRANCH_MISMATCH"
remote_test_expect_out "CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=late-feature" "LATE_BRANCH"
[[ "$(remote_test_git -C "$REMOTE_TEST_REMOTE" branch --show-current)" == "late-feature" ]] ||
    remote_test_fail "LATE_BRANCH:BRANCH_WAS_RESTORED"

# HEAD detached after the probe: no branch.
remote_test_scenario
run_with_late_change "LATE_DETACHED" 'git -C "$HOOK_REPO" checkout -q --detach'
expect_launch_refused "LATE_DETACHED" "BRANCH_MISMATCH" "$CBS_RC_REMOTE_BRANCH_MISMATCH"
remote_test_expect_out "CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=DETACHED" "LATE_DETACHED"
[[ -z "$(remote_test_git -C "$REMOTE_TEST_REMOTE" branch --show-current)" ]] ||
    remote_test_fail "LATE_DETACHED:BRANCH_WAS_RESTORED"

# Commit changed after the probe (new commit, worktree clean afterwards).
remote_test_scenario
run_with_late_change "LATE_COMMIT" 'printf "late\n" > "$HOOK_REPO/late-commit.txt" && git -C "$HOOK_REPO" add late-commit.txt && git -C "$HOOK_REPO" commit -q -m late'
expect_launch_refused "LATE_COMMIT" "COMMIT_MISMATCH" "$CBS_RC_REMOTE_COMMIT_MISMATCH"
NEW_HEAD="$(remote_test_git -C "$REMOTE_TEST_REMOTE" rev-parse HEAD)"
[[ "$NEW_HEAD" != "$REMOTE_TEST_HEAD" ]] ||
    remote_test_fail "LATE_COMMIT:HEAD_WAS_RESET"
remote_test_expect_out "CBS_REMOTE_LAUNCH_OBSERVED_COMMIT=$NEW_HEAD" "LATE_COMMIT"
[[ -z "$(remote_test_git -C "$REMOTE_TEST_REMOTE" status --porcelain)" ]] ||
    remote_test_fail "LATE_COMMIT:WORKTREE_NOT_CLEAN"

# Commit moved backwards after the probe (HEAD reset to the parent).
remote_test_scenario
remote_test_commit "$REMOTE_TEST_LOCAL" "local-only"
remote_test_git -C "$REMOTE_TEST_REMOTE" pull -q --ff-only "$REMOTE_TEST_LOCAL" main
run_with_late_change "LATE_COMMIT_BACK" 'git -C "$HOOK_REPO" reset -q --hard HEAD~1'
expect_launch_refused "LATE_COMMIT_BACK" "COMMIT_MISMATCH" "$CBS_RC_REMOTE_COMMIT_MISMATCH"

# Origin changed after the probe.
remote_test_scenario
run_with_late_change "LATE_ORIGIN" 'git -C "$HOOK_REPO" remote set-url origin git@example.invalid:someone/else.git'
expect_launch_refused "LATE_ORIGIN" "REPOSITORY_ORIGIN_MISMATCH" "$CBS_REPOSITORY_RC_REMOTE_MISMATCH"
[[ "$(remote_test_git -C "$REMOTE_TEST_REMOTE" remote get-url origin)" == "git@example.invalid:someone/else.git" ]] ||
    remote_test_fail "LATE_ORIGIN:ORIGIN_WAS_RESTORED"
if grep -Fq 'someone/else' <<<"$OUT$ERR"; then
    remote_test_fail "LATE_ORIGIN:OBSERVED_ORIGIN_DISPLAYED"
fi

# Repository removed after the probe.
remote_test_scenario
run_with_late_change "LATE_MISSING" 'mv "$HOOK_REPO" "$HOOK_REPO.moved"'
expect_launch_refused "LATE_MISSING" "REPOSITORY_MISSING" "$CBS_REPOSITORY_RC_MISSING"
[[ -d "$REMOTE_TEST_REMOTE.moved/.git" ]] ||
    remote_test_fail "LATE_MISSING:MOVED_REPOSITORY_LOST"

# Entrypoint made unavailable after the probe (entrypoint outside the repository).
remote_test_scenario
EXTERNAL_ENTRYPOINT="$SCN/external-cbs"
cp "$REMOTE_TEST_LOCAL/bin/cbs" "$EXTERNAL_ENTRYPOINT"
chmod 0755 "$EXTERNAL_ENTRYPOINT"
M_EXTRA="CBS_REMOTE_CBS_ENTRYPOINT=$EXTERNAL_ENTRYPOINT"
EXTERNAL_ENTRYPOINT_PATH="$EXTERNAL_ENTRYPOINT"
export EXTERNAL_ENTRYPOINT_PATH
run_with_late_change "LATE_ENTRYPOINT" 'chmod 0644 "$EXTERNAL_ENTRYPOINT_PATH"'
expect_launch_refused "LATE_ENTRYPOINT" "ENTRYPOINT_UNAVAILABLE" "$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE"

# Entrypoint removed after the probe.
remote_test_scenario
EXTERNAL_ENTRYPOINT="$SCN/external-cbs"
cp "$REMOTE_TEST_LOCAL/bin/cbs" "$EXTERNAL_ENTRYPOINT"
chmod 0755 "$EXTERNAL_ENTRYPOINT"
M_EXTRA="CBS_REMOTE_CBS_ENTRYPOINT=$EXTERNAL_ENTRYPOINT"
EXTERNAL_ENTRYPOINT_PATH="$EXTERNAL_ENTRYPOINT"
export EXTERNAL_ENTRYPOINT_PATH
run_with_late_change "LATE_ENTRYPOINT_REMOVED" 'mv "$EXTERNAL_ENTRYPOINT_PATH" "$EXTERNAL_ENTRYPOINT_PATH.gone"'
expect_launch_refused "LATE_ENTRYPOINT_REMOVED" "ENTRYPOINT_UNAVAILABLE" "$CBS_RC_REMOTE_ENTRYPOINT_UNAVAILABLE"

echo "TEST_REMOTE_RUN_LAUNCHER_REVALIDATION_REFUSALS=PASS"

# The launcher never repairs: after every refusal above the remote state was
# exactly what the late change left (asserted per scenario). A refused launch
# also leaves no stash and no extra commit.
remote_test_scenario
run_with_late_change "LATE_NO_REPAIR" 'printf "late\n" > "$HOOK_REPO/late-untracked.txt"'
expect_launch_refused "LATE_NO_REPAIR" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
[[ "$(remote_test_git -C "$REMOTE_TEST_REMOTE" rev-parse HEAD)" == "$REMOTE_TEST_HEAD" ]] ||
    remote_test_fail "LATE_NO_REPAIR:HEAD_CHANGED"
[[ -z "$(remote_test_git -C "$REMOTE_TEST_REMOTE" stash list)" ]] ||
    remote_test_fail "LATE_NO_REPAIR:STASH_CREATED"
[[ "$(remote_test_git -C "$REMOTE_TEST_REMOTE" status --porcelain)" == "?? late-untracked.txt" ]] ||
    remote_test_fail "LATE_NO_REPAIR:WORKTREE_STATE_CHANGED"

echo "TEST_REMOTE_RUN_LAUNCHER_NO_REPAIR=PASS"

# --- change between "check" and "run" (two separate commands)

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
remote_test_arm_marker
remote_test_run "$CBS" remote check "$MANIFEST"
remote_test_expect_rc 0 "CHECK_THEN_RUN:CHECK"
remote_test_expect_out "CBS_REMOTE_RESULT=PASS" "CHECK_THEN_RUN:CHECK"
remote_test_expect_ssh_count 1 "CHECK_THEN_RUN:CHECK"

printf 'scratch\n' > "$REMOTE_TEST_REMOTE/after-check.txt"

remote_test_run "$CBS" remote run "$MANIFEST" show_version
expect_blocked "CHECK_THEN_RUN" "WORKTREE_DIRTY" "$CBS_RC_REMOTE_WORKTREE_DIRTY"
remote_test_expect_ssh_count 2 "CHECK_THEN_RUN:RUN_STOPPED_AT_PROBE"
if remote_test_marker_present; then
    remote_test_fail "CHECK_THEN_RUN:ENTRYPOINT_WAS_STARTED"
fi

echo "TEST_REMOTE_RUN_CHANGE_BETWEEN_CHECK_AND_RUN=PASS"

# --- a refused preflight never leads to an execution, whatever the cause

for cause in dirty branch commit origin; do
    remote_test_scenario
    remote_test_arm_marker

    case "$cause" in
        dirty)
            printf 'x\n' > "$REMOTE_TEST_REMOTE/dirty.txt"
            ;;
        branch)
            remote_test_git -C "$REMOTE_TEST_REMOTE" checkout -q -b other
            ;;
        commit)
            remote_test_commit "$REMOTE_TEST_REMOTE" "extra"
            ;;
        origin)
            remote_test_git -C "$REMOTE_TEST_REMOTE" remote set-url origin "git@example.invalid:other/repo.git"
            ;;
    esac

    run show_version
    remote_test_expect_no_out "CBS_REMOTE_ACTION_EXECUTION=START" "NO_EXECUTION_AFTER_REFUSAL:$cause"
    remote_test_expect_no_out "CBS_REMOTE_RESULT=PASS" "NO_EXECUTION_AFTER_REFUSAL:$cause"
    remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "NO_EXECUTION_AFTER_REFUSAL:$cause"
    remote_test_expect_ssh_count 1 "NO_LAUNCH_SESSION_AFTER_REFUSAL:$cause"
    if remote_test_marker_present; then
        remote_test_fail "NO_EXECUTION_AFTER_REFUSAL:$cause:ENTRYPOINT_WAS_STARTED"
    fi
    if grep -q 'FIXTURE_CBS_' <<<"$OUT$ERR"; then
        remote_test_fail "NO_EXECUTION_AFTER_REFUSAL:$cause:ENTRYPOINT_OUTPUT_SEEN"
    fi
    if grep -Fq 'LAUNCH' "$FAKE_SSH_STATE/command.1"; then
        remote_test_fail "NO_EXECUTION_AFTER_REFUSAL:$cause:LAUNCHER_SENT"
    fi
done

echo "TEST_REMOTE_RUN_NO_EXECUTION_AFTER_REFUSED_PREFLIGHT=PASS"

# --- the action cannot forge the launcher verdict

remote_test_scenario
export FIXTURE_CBS_FORGE_VERDICT=1
run show_version
remote_test_expect_rc 0 "FORGED_VERDICT"
remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=PASS" "FORGED_VERDICT"
remote_test_expect_out "CBS_REMOTE_RESULT=PASS" "FORGED_VERDICT"
# The action output is forwarded unchanged, forged lines included.
remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED" "FORGED_VERDICT_FORWARDED"
remote_test_expect_out "CBS_REMOTE_LAUNCH_REASON=WORKTREE_DIRTY" "FORGED_VERDICT_FORWARDED"
remote_test_expect_no_out "CBS_REMOTE_REASON=WORKTREE_DIRTY" "FORGED_VERDICT_NOT_APPLIED"

echo "TEST_REMOTE_RUN_VERDICT_NOT_FORGEABLE=PASS"

# --- diagnostics: transport failure, preflight refusal, action failure
#
# Three different outcomes, reported with different evidence:
#   preflight refusal : BLOCKED, launcher verdict REFUSED, entrypoint not started
#   action failure    : FAIL REMOTE_ACTION_FAILED, launcher verdict PASS, rc kept
#   ssh status 255    : FAIL TRANSPORT_FAILURE, origin never claimed as certain

# The action itself returns 255 after a passing verdict.
remote_test_scenario
export FIXTURE_CBS_FORCE_EXIT=255
run show_version
remote_test_expect_rc 255 "ACTION_RETURNS_255"
remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=PASS" "ACTION_RETURNS_255"
remote_test_expect_out "CBS_REMOTE_ACTION_EXECUTION=START" "ACTION_RETURNS_255"
remote_test_expect_out "CBS_REMOTE_ACTION_RC=255" "ACTION_RETURNS_255"
remote_test_expect_out "CBS_REMOTE_RESULT=FAIL" "ACTION_RETURNS_255"
remote_test_expect_out "CBS_REMOTE_DIAGNOSTIC=SSH_STATUS_255_ORIGIN_UNDETERMINED" "ACTION_RETURNS_255"
remote_test_expect_no_out "CBS_REMOTE_DIAGNOSTIC=SSH_STATUS_255_NO_LAUNCHER_VERDICT" "ACTION_RETURNS_255"
# An action failure other than 255 carries no 255 diagnostic.
unset FIXTURE_CBS_FORCE_EXIT

remote_test_scenario
run show_fail
remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=PASS" "ACTION_FAILS_7"
remote_test_expect_out "CBS_REMOTE_REASON=REMOTE_ACTION_FAILED" "ACTION_FAILS_7"
if grep -Fq 'CBS_REMOTE_DIAGNOSTIC=' <<<"$OUT"; then
    remote_test_fail "ACTION_FAILS_7:UNEXPECTED_DIAGNOSTIC"
fi

# A preflight refusal whose return code collides with an action return code
# is still reported as BLOCKED, never as an action failure.
remote_test_scenario
run_with_late_change "LATE_COLLISION" 'printf "x\n" > "$HOOK_REPO/c.txt"'
remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "REFUSAL_NOT_ACTION_FAILURE"
remote_test_expect_no_out "CBS_REMOTE_REASON=REMOTE_ACTION_FAILED" "REFUSAL_NOT_ACTION_FAILURE"
remote_test_expect_no_out "CBS_REMOTE_REASON=TRANSPORT_FAILURE" "REFUSAL_NOT_TRANSPORT_FAILURE"

# A session that ends without any launcher verdict and with status 0 is not a
# PASS: the launch is not confirmed.
remote_test_scenario
FAKE_SSH_MODE_ON_CALL=2
FAKE_SSH_CALL_MODE=garbage
export FAKE_SSH_MODE_ON_CALL FAKE_SSH_CALL_MODE
run show_version
remote_test_expect_rc "$CBS_RC_REMOTE_PROBE_FAILED" "NO_VERDICT_STATUS_0"
remote_test_expect_out "CBS_REMOTE_RESULT=FAIL" "NO_VERDICT_STATUS_0"
remote_test_expect_out "CBS_REMOTE_REASON=LAUNCH_NOT_CONFIRMED" "NO_VERDICT_STATUS_0"
remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=NOT_REPORTED" "NO_VERDICT_STATUS_0"
remote_test_expect_no_out "CBS_REMOTE_ACTION_EXECUTION=START" "NO_VERDICT_STATUS_0"
remote_test_expect_no_out "CBS_REMOTE_RESULT=PASS" "NO_VERDICT_STATUS_0"

# A session that ends without verdict and with another status is not reported
# as a remote action failure either.
remote_test_scenario
FAKE_SSH_MODE_ON_CALL=2
FAKE_SSH_CALL_MODE=probe-fail
export FAKE_SSH_MODE_ON_CALL FAKE_SSH_CALL_MODE
run show_version
remote_test_expect_rc "$CBS_RC_REMOTE_PROBE_FAILED" "NO_VERDICT_STATUS_3"
remote_test_expect_out "CBS_REMOTE_REASON=LAUNCH_NOT_CONFIRMED" "NO_VERDICT_STATUS_3"
remote_test_expect_out "CBS_REMOTE_ACTION_RC=3" "NO_VERDICT_STATUS_3"
remote_test_expect_err "FAKE_SSH_REMOTE_DIAGNOSTIC=probe exploded" "NO_VERDICT_STATUS_3_STDERR_PRESERVED"

echo "TEST_REMOTE_RUN_DIAGNOSTICS=PASS"

# --- usage and manifest errors never reach the network

remote_test_scenario
remote_test_write_manifest "$MANIFEST"

remote_test_run "$CBS" remote run
expect_blocked "USAGE_NOTHING" "USAGE" "$CBS_RC_REMOTE_USAGE"

remote_test_run "$CBS" remote run "$MANIFEST"
expect_blocked "USAGE_NO_ACTION" "USAGE" "$CBS_RC_REMOTE_USAGE"

remote_test_run "$CBS" remote run "$MANIFEST" show_version extra
expect_blocked "USAGE_EXTRA_ARGUMENT" "USAGE" "$CBS_RC_REMOTE_USAGE"

remote_test_run "$CBS" remote run "$MANIFEST" ""
expect_blocked "USAGE_EMPTY_ACTION" "USAGE" "$CBS_RC_REMOTE_USAGE"

remote_test_run "$CBS" remote run "$SCN/missing.env" show_version
expect_blocked "MANIFEST_MISSING" "MANIFEST_INVALID" "$CBS_RC_REMOTE_MANIFEST_INVALID"

printf 'CBS_REMOTE_UNKNOWN=1\n' >> "$MANIFEST"
remote_test_run "$CBS" remote run "$MANIFEST" show_version
expect_blocked "MANIFEST_INVALID" "MANIFEST_INVALID" "$CBS_RC_REMOTE_MANIFEST_INVALID"

remote_test_expect_ssh_count 0 "USAGE_AND_MANIFEST_NO_NETWORK"

echo "TEST_REMOTE_RUN_USAGE_AND_MANIFEST_ERRORS=PASS"

echo "TEST_REMOTE_RUN_RESULT=PASS"
