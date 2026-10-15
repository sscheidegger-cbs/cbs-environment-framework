#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/tests/fixtures/remote/lib.sh"
source "$ROOT/cbs/remote/remote_manifest.sh"

REMOTE_TEST_PREFIX="TEST_REMOTE_MANIFEST"
REMOTE_TEST_LIGHT=1

# Loads a manifest in a subshell. Sets OUT (stdout), ERR (stderr) and RC.
load() {
    remote_test_run bash -c '
        set -Eeuo pipefail
        source "$1/cbs/remote/remote_manifest.sh"
        cbs_remote_manifest_load "$2"
    ' load "$ROOT" "$1"
}

expect_invalid() {
    local label="$1"
    local code="$2"
    local key="${3:-}"

    load "$MANIFEST"

    [[ "$RC" -ne 0 ]] ||
        remote_test_fail "${label}:ACCEPTED_INVALID_MANIFEST"

    grep -Fxq "CBS_REMOTE_MANIFEST_ERROR=$code" <<<"$ERR" ||
        remote_test_fail "${label}:EXPECTED_ERROR_${code}_GOT_$(tr '\n' ' ' <<<"$ERR")"

    if [[ -n "$key" ]]; then
        grep -Fxq "CBS_REMOTE_MANIFEST_ERROR_KEY=$key" <<<"$ERR" ||
            remote_test_fail "${label}:EXPECTED_KEY_${key}_GOT_$(tr '\n' ' ' <<<"$ERR")"
    fi
}

expect_valid() {
    load "$MANIFEST"

    [[ "$RC" -eq 0 ]] ||
        remote_test_fail "$1:REJECTED_VALID_MANIFEST:$(tr '\n' ' ' <<<"$ERR")"
}

# --- valid manifests

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
expect_valid "VALID_LOCAL_HEAD"

remote_test_scenario
M_COMMIT="0123456789abcdef0123456789abcdef01234567"
remote_test_write_manifest "$MANIFEST"
expect_valid "VALID_PINNED_COMMIT"

remote_test_scenario
M_COMMIT="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
remote_test_write_manifest "$MANIFEST"
expect_valid "VALID_PINNED_COMMIT_SHA256"

remote_test_scenario
M_EXTRA=$'CBS_REMOTE_SSH_PORT=2222\nCBS_REMOTE_SSH_CONNECT_TIMEOUT=5\nCBS_REMOTE_SSH_IDENTITY_FILE=/home/user/.ssh/id_fixture\nCBS_REMOTE_PATH_PREPEND=/opt/fixture/bin:/usr/local/bin\nCBS_REMOTE_CBS_ENTRYPOINT=tools/run cbs'
remote_test_write_manifest "$MANIFEST"
expect_valid "VALID_OPTIONAL_KEYS"

remote_test_scenario
M_DESTINATION="fixture_user@fixture.invalid"
remote_test_write_manifest "$MANIFEST"
expect_valid "VALID_USER_AT_HOST"

echo "TEST_REMOTE_MANIFEST_VALID=PASS"

# --- the loaded configuration is exactly what was declared

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
OUT="$(
    bash -c '
        set -Eeuo pipefail
        source "$1/cbs/remote/remote_manifest.sh"
        cbs_remote_manifest_load "$2"
        printf "%s\n" "${CBS_REMOTE_ACTIONS[*]}"
        printf "%s\n" "${CBS_REMOTE_RESOLVED[ACTION_show_args]}"
        printf "%s\n" "${CBS_REMOTE_RESOLVED[ENTRYPOINT]}"
        printf "%s\n" "${CBS_REMOTE_RESOLVED[LOCAL_REPOSITORY]}"
    ' load "$ROOT" "$MANIFEST"
)"

[[ "$(sed -n 1p <<<"$OUT")" == "show_version show_args show_fail show_exit42" ]] ||
    remote_test_fail "LOADED_ACTIONS"

[[ "$(sed -n 2p <<<"$OUT")" == "stack environment stacks/flutter/stack.env a=b,c%d+e@f:g" ]] ||
    remote_test_fail "LOADED_ACTION_COMMAND"

[[ "$(sed -n 3p <<<"$OUT")" == "bin/cbs" ]] ||
    remote_test_fail "LOADED_DEFAULT_ENTRYPOINT"

[[ "$(sed -n 4p <<<"$OUT")" == "$REMOTE_TEST_LOCAL" ]] ||
    remote_test_fail "LOADED_LOCAL_REPOSITORY"

echo "TEST_REMOTE_MANIFEST_LOADED_VALUES=PASS"

# A relative local repository path is resolved from the manifest directory.
remote_test_scenario
M_LOCAL_REPOSITORY="../local"
mkdir -p "$SCN/conf"
MANIFEST="$SCN/conf/manifest.env"
remote_test_write_manifest "$MANIFEST"
OUT="$(
    bash -c '
        set -Eeuo pipefail
        source "$1/cbs/remote/remote_manifest.sh"
        cbs_remote_manifest_load "$2"
        printf "%s\n" "${CBS_REMOTE_RESOLVED[LOCAL_REPOSITORY]}"
    ' load "$ROOT" "$MANIFEST"
)"

[[ "$OUT" == "$SCN/conf/../local" ]] ||
    remote_test_fail "RELATIVE_LOCAL_REPOSITORY:$OUT"

echo "TEST_REMOTE_MANIFEST_RELATIVE_LOCAL_PATH=PASS"

# --- structural rejections

load "$TMP/does-not-exist.env"
[[ "$RC" -ne 0 ]] || remote_test_fail "MISSING_FILE_ACCEPTED"
grep -Fxq "CBS_REMOTE_MANIFEST_ERROR=FILE_NOT_FOUND" <<<"$ERR" ||
    remote_test_fail "MISSING_FILE_ERROR"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
printf 'CBS_REMOTE_ID=other\n' >> "$MANIFEST"
expect_invalid "DUPLICATE_KEY" "DUPLICATE_KEY" "CBS_REMOTE_ID"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
printf 'CBS_REMOTE_PASSWORD=hunter2\n' >> "$MANIFEST"
expect_invalid "UNKNOWN_KEY_PASSWORD" "UNKNOWN_KEY" "CBS_REMOTE_PASSWORD"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
printf 'CBS_REMOTE_SSH_PRIVATE_KEY=-----BEGIN\n' >> "$MANIFEST"
expect_invalid "UNKNOWN_KEY_PRIVATE_KEY" "UNKNOWN_KEY" "CBS_REMOTE_SSH_PRIVATE_KEY"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
printf 'AMH_USR_TOKEN=abc\n' >> "$MANIFEST"
expect_invalid "FOREIGN_KEY" "INVALID_LINE"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
printf 'CBS_REMOTE_SSH_PORT=\n' >> "$MANIFEST"
expect_invalid "EMPTY_VALUE" "EMPTY_VALUE" "CBS_REMOTE_SSH_PORT"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
printf ' CBS_REMOTE_SSH_PORT=22\n' >> "$MANIFEST"
expect_invalid "INDENTED_LINE" "INVALID_LINE"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
sed -i '/^CBS_REMOTE_EXPECTED_BRANCH=/d' "$MANIFEST"
expect_invalid "MISSING_BRANCH" "MISSING_KEY" "CBS_REMOTE_EXPECTED_BRANCH"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
sed -i '/^CBS_REMOTE_ALLOWED_ACTIONS=/d' "$MANIFEST"
expect_invalid "MISSING_ALLOWED_ACTIONS" "MISSING_KEY" "CBS_REMOTE_ALLOWED_ACTIONS"

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
sed -i 's/^CBS_REMOTE_MANIFEST_VERSION=1/CBS_REMOTE_MANIFEST_VERSION=2/' "$MANIFEST"
expect_invalid "UNSUPPORTED_VERSION" "UNSUPPORTED_VERSION"

# CRLF line endings are not silently accepted.
remote_test_scenario
remote_test_write_manifest "$MANIFEST"
sed -i 's/$/\r/' "$MANIFEST"
load "$MANIFEST"
[[ "$RC" -ne 0 ]] || remote_test_fail "CRLF_ACCEPTED"

echo "TEST_REMOTE_MANIFEST_STRUCTURAL_REJECTIONS=PASS"

# --- value rejections (injection attempts and malformed values)

reject_value() {
    local label="$1"
    local key="$2"
    local value="$3"

    remote_test_scenario
    remote_test_write_manifest "$MANIFEST"
    sed -i "/^${key}=/d" "$MANIFEST"
    printf '%s=%s\n' "$key" "$value" >> "$MANIFEST"
    expect_invalid "$label" "INVALID_VALUE" "$key"
}

reject_value "DEST_SEMICOLON" CBS_REMOTE_SSH_DESTINATION 'host;touch /tmp/x'
reject_value "DEST_SPACE" CBS_REMOTE_SSH_DESTINATION 'host -oProxyCommand=x'
reject_value "DEST_OPTION" CBS_REMOTE_SSH_DESTINATION '-oProxyCommand=x'
reject_value "DEST_SUBSHELL" CBS_REMOTE_SSH_DESTINATION 'host$(id)'
reject_value "DEST_BACKTICK" CBS_REMOTE_SSH_DESTINATION 'host`id`'
reject_value "ID_UPPERCASE" CBS_REMOTE_ID 'Fixture'
reject_value "PORT_ZERO" CBS_REMOTE_SSH_PORT '0'
reject_value "PORT_TOO_BIG" CBS_REMOTE_SSH_PORT '65536'
reject_value "PORT_TEXT" CBS_REMOTE_SSH_PORT '22a'
reject_value "TIMEOUT_ZERO" CBS_REMOTE_SSH_CONNECT_TIMEOUT '0'
reject_value "TIMEOUT_TOO_BIG" CBS_REMOTE_SSH_CONNECT_TIMEOUT '121'
reject_value "IDENTITY_RELATIVE" CBS_REMOTE_SSH_IDENTITY_FILE 'id_rsa'
reject_value "IDENTITY_TILDE" CBS_REMOTE_SSH_IDENTITY_FILE '~/id_rsa'
reject_value "IDENTITY_PARENT" CBS_REMOTE_SSH_IDENTITY_FILE '/home/u/../root/id'
reject_value "PATH_PREPEND_RELATIVE" CBS_REMOTE_PATH_PREPEND 'bin'
reject_value "PATH_PREPEND_SUBSHELL" CBS_REMOTE_PATH_PREPEND '/opt/x:$(id)'
reject_value "REPOSITORY_RELATIVE" CBS_REMOTE_REPOSITORY_PATH 'repo'
reject_value "REPOSITORY_TILDE" CBS_REMOTE_REPOSITORY_PATH '~/repo'
reject_value "REPOSITORY_PARENT" CBS_REMOTE_REPOSITORY_PATH '/srv/../etc'
reject_value "REPOSITORY_SEMICOLON" CBS_REMOTE_REPOSITORY_PATH '/srv/repo;touch x'
reject_value "REPOSITORY_QUOTE" CBS_REMOTE_REPOSITORY_PATH "/srv/re'po"
reject_value "REPOSITORY_SUBSHELL" CBS_REMOTE_REPOSITORY_PATH '/srv/$(id)'
reject_value "REPOSITORY_TRAILING_SPACE" CBS_REMOTE_REPOSITORY_PATH '/srv/repo '
reject_value "ORIGIN_SPACE" CBS_REMOTE_REPOSITORY_ORIGIN 'git@host:a b.git'
reject_value "ORIGIN_SEMICOLON" CBS_REMOTE_REPOSITORY_ORIGIN 'git@host:a.git;id'
reject_value "BRANCH_SPACE" CBS_REMOTE_EXPECTED_BRANCH 'ma in'
reject_value "BRANCH_OPTION" CBS_REMOTE_EXPECTED_BRANCH '--force'
reject_value "BRANCH_DOTDOT" CBS_REMOTE_EXPECTED_BRANCH 'a..b'
reject_value "BRANCH_SUBSHELL" CBS_REMOTE_EXPECTED_BRANCH 'x$(id)'
reject_value "COMMIT_SHORT" CBS_REMOTE_EXPECTED_COMMIT 'abc1234'
reject_value "COMMIT_UPPERCASE" CBS_REMOTE_EXPECTED_COMMIT '0123456789ABCDEF0123456789ABCDEF01234567'
reject_value "COMMIT_BRANCH_NAME" CBS_REMOTE_EXPECTED_COMMIT 'main'
reject_value "ALLOWED_DOUBLE_SPACE" CBS_REMOTE_ALLOWED_ACTIONS 'show_version  show_args'

# The unquoted values below also prove that nothing is evaluated.
remote_test_scenario
M_ALLOWED='show_version;touch /tmp/pwned'
remote_test_write_manifest "$MANIFEST"
expect_invalid "ALLOWED_SEMICOLON" "INVALID_ACTION_NAME"

remote_test_scenario
M_ALLOWED='Show_Version'
remote_test_write_manifest "$MANIFEST"
expect_invalid "ALLOWED_UPPERCASE" "INVALID_ACTION_NAME"

remote_test_scenario
M_ALLOWED='show_version show_version'
remote_test_write_manifest "$MANIFEST"
expect_invalid "ALLOWED_DUPLICATE" "DUPLICATE_ACTION"

remote_test_scenario
M_COMMIT="LOCAL_HEAD"
remote_test_write_manifest "$MANIFEST"
sed -i '/^CBS_REMOTE_LOCAL_REPOSITORY_PATH=/d' "$MANIFEST"
expect_invalid "LOCAL_HEAD_WITHOUT_LOCAL_PATH" "MISSING_KEY" "CBS_REMOTE_LOCAL_REPOSITORY_PATH"

remote_test_scenario
M_COMMIT="0123456789abcdef0123456789abcdef01234567"
M_EXTRA="CBS_REMOTE_LOCAL_REPOSITORY_PATH=$REMOTE_TEST_LOCAL"
remote_test_write_manifest "$MANIFEST"
expect_invalid "PINNED_WITH_LOCAL_PATH" "UNUSED_KEY" "CBS_REMOTE_LOCAL_REPOSITORY_PATH"

for entrypoint in 'cbs' '../cbs' 'bin/../../cbs' 'bin/cbs;id' 'bin/$(id)'; do
    remote_test_scenario
    M_EXTRA="CBS_REMOTE_CBS_ENTRYPOINT=$entrypoint"
    remote_test_write_manifest "$MANIFEST"
    expect_invalid "ENTRYPOINT_$entrypoint" "INVALID_VALUE" "CBS_REMOTE_CBS_ENTRYPOINT"
done

echo "TEST_REMOTE_MANIFEST_VALUE_REJECTIONS=PASS"

# --- secrets must be refused

remote_test_scenario
M_ORIGIN="https://deploy:s3cr3t-token@example.invalid/group/project.git"
remote_test_write_manifest "$MANIFEST"
expect_invalid "ORIGIN_WITH_PASSWORD" "SECRET_IN_VALUE" "CBS_REMOTE_REPOSITORY_ORIGIN"

if grep -Fq 's3cr3t' <<<"$OUT$ERR"; then
    remote_test_fail "SECRET_ECHOED_BY_LOADER"
fi

remote_test_scenario
M_ORIGIN="https://deploy:@example.invalid/group/project.git"
remote_test_write_manifest "$MANIFEST"
expect_invalid "ORIGIN_WITH_EMPTY_PASSWORD" "SECRET_IN_VALUE" "CBS_REMOTE_REPOSITORY_ORIGIN"

remote_test_scenario
M_ORIGIN="git@example.invalid:group/project.git"
remote_test_write_manifest "$MANIFEST"
expect_valid "ORIGIN_SCP_STYLE_IS_NOT_A_SECRET"

remote_test_scenario
M_ORIGIN="https://example.invalid/group/project.git"
remote_test_write_manifest "$MANIFEST"
expect_valid "ORIGIN_HTTPS_WITHOUT_USERINFO"

echo "TEST_REMOTE_MANIFEST_SECRET_REFUSAL=PASS"

# --- actions

for command in \
    'repository ensure /x git@h:a.git' \
    'workspace ensure /x' \
    'worktree ensure /x /y b' \
    'instance ensure x.env' \
    'runtime android start' \
    'runtime android stop' \
    'runtime android ensure' \
    'runtime android ensure medium_phone' \
    'stack toolchains ensure stacks/flutter/stack.env' \
    'stack toolchains ensure' \
    'platform start platforms/x/platform.env' \
    'platform stop platforms/x/platform.env' \
    'platform check platforms/x/platform.env' \
    'platform status platforms/x/platform.env' \
    'platform qualify platforms/x/platform.env' \
    'remote check m.env' \
    'rm -rf /' \
    'bash -c id' \
    'sh' \
    'help' \
    'platform deploy x.env' \
    'stack toolchains x.env'
do
    remote_test_scenario
    M_ALLOWED="bad_action"
    M_EXTRA="CBS_REMOTE_ACTION_BAD_ACTION_COMMAND=$command"
    remote_test_write_manifest "$MANIFEST"
    sed -i '/^CBS_REMOTE_ACTION_SHOW_/d' "$MANIFEST"
    expect_invalid "COMMAND_NOT_ALLOWED_$command" "COMMAND_NOT_ALLOWED" "CBS_REMOTE_ACTION_BAD_ACTION_COMMAND"
done

# Every command of the explicit allow-list is accepted, with arguments.
for command in \
    'version' \
    'status context.env' \
    'workstation check context.env' \
    'workspace check /w /w/r git@h:a.git' \
    'worktree check /w/r' \
    'instance check instances/x/instance.env' \
    'stack resolve stacks/flutter/stack.env' \
    'stack prerequisites stacks/flutter/stack.env' \
    'stack environment stacks/flutter/stack.env' \
    'platform resolve platforms/x/platform.env' \
    'runtime android list'
do
    remote_test_scenario
    M_ALLOWED="ok_action"
    M_EXTRA="CBS_REMOTE_ACTION_OK_ACTION_COMMAND=$command"
    remote_test_write_manifest "$MANIFEST"
    sed -i '/^CBS_REMOTE_ACTION_SHOW_/d' "$MANIFEST"
    expect_valid "COMMAND_ALLOWED_$command"
done

for command in \
    'version;id' \
    'version $(id)' \
    'version `id`' \
    'version | cat' \
    'version && id' \
    'version > /tmp/x' \
    'version "quoted"' \
    "version 'quoted'" \
    'version *' \
    'version ~' \
    'version $HOME' \
    'version ../x' \
    'version a/../b' \
    '-version' \
    'version  doubled' \
    'version trailing '
do
    remote_test_scenario
    M_ALLOWED="bad_action"
    M_EXTRA="CBS_REMOTE_ACTION_BAD_ACTION_COMMAND=$command"
    remote_test_write_manifest "$MANIFEST"
    sed -i '/^CBS_REMOTE_ACTION_SHOW_/d' "$MANIFEST"
    load "$MANIFEST"
    [[ "$RC" -ne 0 ]] ||
        remote_test_fail "COMMAND_INJECTION_ACCEPTED:$command"
done

remote_test_scenario
M_ALLOWED="show_version"
remote_test_write_manifest "$MANIFEST"
expect_invalid "ACTION_COMMAND_FOR_UNDECLARED_ACTION" "ACTION_NOT_DECLARED"

remote_test_scenario
M_ALLOWED="show_version missing_action"
remote_test_write_manifest "$MANIFEST"
sed -i '/^CBS_REMOTE_ACTION_SHOW_\(ARGS\|FAIL\|EXIT42\)_COMMAND=/d' "$MANIFEST"
expect_invalid "DECLARED_ACTION_WITHOUT_COMMAND" "ACTION_COMMAND_MISSING" "CBS_REMOTE_ACTION_MISSING_ACTION_COMMAND"

echo "TEST_REMOTE_MANIFEST_ACTIONS=PASS"

# --- the manifest is parsed, never executed

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
cat >> "$MANIFEST" <<EOF_MANIFEST
touch "$SCN/pwned-line"
CBS_REMOTE_EXPECTED_BRANCH_EXTRA=\$(touch "$SCN/pwned-subshell")
\$(touch "$SCN/pwned-standalone")
EOF_MANIFEST
load "$MANIFEST"
[[ "$RC" -ne 0 ]] || remote_test_fail "EXECUTABLE_CONTENT_ACCEPTED"

remote_test_scenario
M_BRANCH='main$(touch '"$SCN"'/pwned-branch)'
remote_test_write_manifest "$MANIFEST"
load "$MANIFEST"
[[ "$RC" -ne 0 ]] || remote_test_fail "BRANCH_SUBSHELL_ACCEPTED"

for marker in "$TMP"/scenario-*/pwned-*; do
    [[ ! -e "$marker" ]] ||
        remote_test_fail "MANIFEST_CONTENT_WAS_EXECUTED:$marker"
done

echo "TEST_REMOTE_MANIFEST_NOT_EXECUTED=PASS"

echo "TEST_REMOTE_MANIFEST_RESULT=PASS"
