#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"

WORKSPACE="/home/sscheidegger/projects"
REPOSITORY="$WORKSPACE/core-platform"
ORIGIN="git@gitlab.com:core3234722/core-platform.git"

fail() {
    echo "TEST_WORKSPACE_CLI_RESULT=FAIL" >&2
    echo "TEST_WORKSPACE_CLI_FAILURE=$1" >&2
    exit 1
}

HELP="$("$CBS" help)"

grep -Fq \
    'cbs workspace check <workspace-path> <repository-path> <origin>' \
    <<<"$HELP" ||
    fail "HELP_WORKSPACE_CHECK"

grep -Fq \
    'cbs workspace ensure <workspace-path>' \
    <<<"$HELP" ||
    fail "HELP_WORKSPACE_ENSURE"

grep -Fq \
    'cbs repository ensure <repository-path> <origin>' \
    <<<"$HELP" ||
    fail "HELP_REPOSITORY_ENSURE"

OUTPUT="$(
    "$CBS" workspace check \
        "$WORKSPACE" \
        "$REPOSITORY" \
        "$ORIGIN"
)"

grep -Fq 'CBS_WORKSPACE_STATE=READY' <<<"$OUTPUT" ||
    fail "CHECK_WORKSPACE_READY"

grep -Fq 'CBS_REPOSITORY_STATE=READY' <<<"$OUTPUT" ||
    fail "CHECK_REPOSITORY_READY"

echo "TEST_WORKSPACE_CLI_CHECK=PASS"

OUTPUT="$(
    "$CBS" workspace ensure "$WORKSPACE"
)"

grep -Fq 'CBS_WORKSPACE_ACTION=REUSE' <<<"$OUTPUT" ||
    fail "WORKSPACE_ENSURE_REUSE"

echo "TEST_WORKSPACE_CLI_WORKSPACE_ENSURE=PASS"

OUTPUT="$(
    "$CBS" repository ensure \
        "$REPOSITORY" \
        "$ORIGIN"
)"

grep -Fq 'CBS_REPOSITORY_ACTION=REUSE' <<<"$OUTPUT" ||
    fail "REPOSITORY_ENSURE_REUSE"

echo "TEST_WORKSPACE_CLI_REPOSITORY_ENSURE=PASS"

set +e
OUTPUT="$("$CBS" workspace does-not-exist 2>&1)"
RC=$?
set -e

[[ "$RC" -eq 2 ]] ||
    fail "UNKNOWN_WORKSPACE_RC"

grep -Fq \
    'CBS_ERROR=UNKNOWN_WORKSPACE_COMMAND' \
    <<<"$OUTPUT" ||
    fail "UNKNOWN_WORKSPACE_ERROR"

set +e
OUTPUT="$("$CBS" repository does-not-exist 2>&1)"
RC=$?
set -e

[[ "$RC" -eq 2 ]] ||
    fail "UNKNOWN_REPOSITORY_RC"

grep -Fq \
    'CBS_ERROR=UNKNOWN_REPOSITORY_COMMAND' \
    <<<"$OUTPUT" ||
    fail "UNKNOWN_REPOSITORY_ERROR"

echo "TEST_WORKSPACE_CLI_UNKNOWN_COMMANDS=PASS"
echo "TEST_WORKSPACE_CLI_RESULT=PASS"
