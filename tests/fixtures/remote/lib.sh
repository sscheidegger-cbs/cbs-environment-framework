#!/usr/bin/env bash

# Shared fixture helpers for the CBS Remote tests (sourced, never executed).
#
# The "remote host" is a directory of the local temporary tree: the simulated
# ssh (tests/fixtures/remote/bin/ssh) runs the received remote command locally.
# No network, no real SSH, no real remote repository is involved.

REMOTE_TEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_TEST_ROOT="$(cd "$REMOTE_TEST_LIB_DIR/../../.." && pwd)"

REMOTE_TEST_REAL_SSH="$(command -v ssh || true)"
REMOTE_TEST_REAL_GIT="$(command -v git)"
export CBS_REMOTE_TEST_REAL_GIT="$REMOTE_TEST_REAL_GIT"

# Hermetic Git: no user or system configuration.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="CBS Remote Test"
export GIT_AUTHOR_EMAIL="cbs-remote-test@example.invalid"
export GIT_COMMITTER_NAME="CBS Remote Test"
export GIT_COMMITTER_EMAIL="cbs-remote-test@example.invalid"

# The simulated ssh must shadow any real ssh.
export PATH="$REMOTE_TEST_LIB_DIR/bin:$PATH"

if [[ "$(command -v ssh)" != "$REMOTE_TEST_LIB_DIR/bin/ssh" ]]; then
    echo "REMOTE_TEST_ERROR=SIMULATED_SSH_NOT_FIRST_IN_PATH" >&2
    exit 1
fi

REMOTE_TEST_ORIGIN="git@example.invalid:cbs/remote-fixture.git"
REMOTE_TEST_DESTINATION="fixture-remote-host"

remote_test_git() {
    "$REMOTE_TEST_REAL_GIT" "$@"
}

# Creates, under the current scenario directory $SCN:
#   local                              "local" repository (source of LOCAL_HEAD)
#   remote fs/work repo                "remote" repository (path with a space)
# Both are on branch main, share history, and the remote one is clean.
remote_test_build_fixture() {
    REMOTE_TEST_LOCAL="$SCN/local"
    REMOTE_TEST_REMOTE_FS="$SCN/remote fs"
    REMOTE_TEST_REMOTE="$REMOTE_TEST_REMOTE_FS/work repo"
    FAKE_SSH_STATE="$SCN/ssh-state"
    export FAKE_SSH_STATE

    mkdir -p "$REMOTE_TEST_LOCAL/bin" "$REMOTE_TEST_REMOTE_FS" "$FAKE_SSH_STATE"

    cat > "$REMOTE_TEST_LOCAL/bin/cbs" <<'FIXTURE_CBS'
#!/usr/bin/env bash
# Fixture CBS entrypoint: reports exactly what it received.
if [[ -n "${FIXTURE_CBS_MARKER_FILE:-}" ]]; then
    echo "started" >> "$FIXTURE_CBS_MARKER_FILE"
fi
if [[ "${FIXTURE_CBS_FORGE_VERDICT:-0}" == "1" ]]; then
    # An action that prints launcher protocol lines must not be able to
    # change the verdict already reported.
    echo "CBS_REMOTE_LAUNCH_REASON=WORKTREE_DIRTY"
    echo "CBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED"
fi
echo "FIXTURE_CBS_PWD=$PWD"
echo "FIXTURE_CBS_ARGC=$#"
index=0
for argument in "$@"; do
    echo "FIXTURE_CBS_ARG_${index}=${argument}"
    index=$((index + 1))
done
case "$1 $2" in
    "status "*)
        echo "FIXTURE_CBS_STDERR_DIAGNOSTIC=status refused" >&2
        exit 7
        ;;
    "workstation check")
        echo "FIXTURE_CBS_STDOUT_BEFORE_FAILURE=yes"
        exit 42
        ;;
esac
exit "${FIXTURE_CBS_FORCE_EXIT:-0}"
FIXTURE_CBS
    chmod 0755 "$REMOTE_TEST_LOCAL/bin/cbs"

    remote_test_git init -q -b main "$REMOTE_TEST_LOCAL"
    remote_test_git -C "$REMOTE_TEST_LOCAL" add bin/cbs
    remote_test_git -C "$REMOTE_TEST_LOCAL" commit -q -m "fixture: initial"

    remote_test_git clone -q "$REMOTE_TEST_LOCAL" "$REMOTE_TEST_REMOTE"
    remote_test_git -C "$REMOTE_TEST_REMOTE" remote set-url origin "$REMOTE_TEST_ORIGIN"

    REMOTE_TEST_HEAD="$(remote_test_git -C "$REMOTE_TEST_REMOTE" rev-parse HEAD)"
}

# Commits a new file in the given repository and prints nothing.
remote_test_commit() {
    local repository="$1"
    local name="$2"

    printf '%s\n' "$name" > "$repository/$name"
    remote_test_git -C "$repository" add "$name"
    remote_test_git -C "$repository" commit -q -m "fixture: $name"
}

# Resets the knobs used by remote_test_write_manifest.
remote_test_manifest_defaults() {
    M_DESTINATION="$REMOTE_TEST_DESTINATION"
    M_REPOSITORY="$REMOTE_TEST_REMOTE"
    M_ORIGIN="$REMOTE_TEST_ORIGIN"
    M_BRANCH="main"
    M_COMMIT="LOCAL_HEAD"
    M_LOCAL_REPOSITORY="$REMOTE_TEST_LOCAL"
    M_ALLOWED="show_version show_args show_fail show_exit42"
    M_EXTRA=""
}

# Writes a manifest to $1 from the M_* knobs.
remote_test_write_manifest() {
    local file="$1"

    {
        echo "# fixture manifest"
        echo "CBS_REMOTE_MANIFEST_VERSION=1"
        echo "CBS_REMOTE_ID=fixture-remote"
        echo "CBS_REMOTE_SSH_DESTINATION=$M_DESTINATION"
        echo "CBS_REMOTE_REPOSITORY_PATH=$M_REPOSITORY"
        echo "CBS_REMOTE_REPOSITORY_ORIGIN=$M_ORIGIN"
        echo "CBS_REMOTE_EXPECTED_BRANCH=$M_BRANCH"
        echo "CBS_REMOTE_EXPECTED_COMMIT=$M_COMMIT"
        if [[ "$M_COMMIT" == "LOCAL_HEAD" ]]; then
            echo "CBS_REMOTE_LOCAL_REPOSITORY_PATH=$M_LOCAL_REPOSITORY"
        fi
        echo "CBS_REMOTE_ALLOWED_ACTIONS=$M_ALLOWED"
        echo "CBS_REMOTE_ACTION_SHOW_VERSION_COMMAND=version"
        echo "CBS_REMOTE_ACTION_SHOW_ARGS_COMMAND=stack environment stacks/flutter/stack.env a=b,c%d+e@f:g"
        echo "CBS_REMOTE_ACTION_SHOW_FAIL_COMMAND=status context.env"
        echo "CBS_REMOTE_ACTION_SHOW_EXIT42_COMMAND=workstation check context.env"
        if [[ -n "$M_EXTRA" ]]; then
            printf '%s\n' "$M_EXTRA"
        fi
    } > "$file"
}

# Marker proving that the fixture entrypoint was started: it lives outside the
# repositories, so it never alters their state. Sets FIXTURE_CBS_MARKER_FILE.
remote_test_arm_marker() {
    FIXTURE_CBS_MARKER_FILE="$SCN/entrypoint-started.marker"
    export FIXTURE_CBS_MARKER_FILE
    rm -f "$FIXTURE_CBS_MARKER_FILE"
}

remote_test_marker_present() {
    [[ -e "${FIXTURE_CBS_MARKER_FILE:-/nonexistent}" ]]
}

# Number of ssh invocations recorded by the simulator.
remote_test_ssh_count() {
    if [[ -f "$FAKE_SSH_STATE/count" ]]; then
        cat "$FAKE_SSH_STATE/count"
    else
        echo 0
    fi
}

remote_test_ssh_reset() {
    rm -rf "$FAKE_SSH_STATE"
    mkdir -p "$FAKE_SSH_STATE"
}

# ---------------------------------------------------------------------------
# Test harness helpers
# ---------------------------------------------------------------------------

REMOTE_TEST_SCENARIO_COUNTER=0
REMOTE_TEST_PREFIX="TEST_REMOTE"
OUT=""
ERR=""
RC=0

remote_test_fail() {
    echo "${REMOTE_TEST_PREFIX}_RESULT=FAIL" >&2
    echo "${REMOTE_TEST_PREFIX}_FAILURE=$1" >&2
    exit 1
}

# Creates a fresh scenario directory with a fresh fixture and default manifest
# knobs. The manifest file path is MANIFEST.
remote_test_scenario() {
    REMOTE_TEST_SCENARIO_COUNTER=$((REMOTE_TEST_SCENARIO_COUNTER + 1))
    SCN="$TMP/scenario-$REMOTE_TEST_SCENARIO_COUNTER"
    mkdir -p "$SCN"

    unset FAKE_SSH_MODE FAKE_SSH_EXPECT_DESTINATION FAKE_SSH_FAIL_ON_CALL \
        FAKE_SSH_HOOK_ON_CALL FAKE_SSH_HOOK FAKE_SSH_MODE_ON_CALL \
        FAKE_SSH_CALL_MODE FIXTURE_CBS_MARKER_FILE FIXTURE_CBS_FORGE_VERDICT \
        FIXTURE_CBS_FORCE_EXIT

    if [[ "${REMOTE_TEST_LIGHT:-0}" == "1" ]]; then
        # Paths only: no repository is created (manifest-level tests).
        REMOTE_TEST_LOCAL="$SCN/local"
        REMOTE_TEST_REMOTE="$SCN/remote fs/work repo"
        FAKE_SSH_STATE="$SCN/ssh-state"
        export FAKE_SSH_STATE
    else
        remote_test_build_fixture
    fi

    remote_test_manifest_defaults

    MANIFEST="$SCN/manifest.env"
}

# Runs a command and records stdout, stderr and the exit status in OUT, ERR
# and RC without aborting the calling test.
remote_test_run() {
    local error_file="$TMP/stderr.capture"

    set +e
    OUT="$("$@" 2>"$error_file")"
    RC=$?
    set -e

    ERR="$(cat "$error_file")"
}

remote_test_expect_rc() {
    [[ "$RC" -eq "$1" ]] ||
        remote_test_fail "$2:RC_EXPECTED_${1}_GOT_${RC}"
}

remote_test_expect_out() {
    grep -Fxq -- "$1" <<<"$OUT" ||
        remote_test_fail "$2:MISSING_STDOUT_LINE:$1"
}

remote_test_expect_no_out() {
    if grep -Fxq -- "$1" <<<"$OUT"; then
        remote_test_fail "$2:UNEXPECTED_STDOUT_LINE:$1"
    fi
}

remote_test_expect_err() {
    grep -Fq -- "$1" <<<"$ERR" ||
        remote_test_fail "$2:MISSING_STDERR_TEXT:$1"
}

remote_test_expect_ssh_count() {
    [[ "$(remote_test_ssh_count)" -eq "$1" ]] ||
        remote_test_fail "$2:SSH_COUNT_EXPECTED_${1}_GOT_$(remote_test_ssh_count)"
}

# Observable state of the simulated remote repository.
remote_test_remote_state() {
    {
        remote_test_git -C "$REMOTE_TEST_REMOTE" rev-parse HEAD
        remote_test_git -C "$REMOTE_TEST_REMOTE" branch --show-current
        remote_test_git -C "$REMOTE_TEST_REMOTE" status --porcelain
        remote_test_git -C "$REMOTE_TEST_REMOTE" stash list
    } 2>&1
}
