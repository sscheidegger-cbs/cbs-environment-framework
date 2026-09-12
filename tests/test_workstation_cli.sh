#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CBS="$ROOT/bin/cbs"
CONTEXT="$ROOT/config/contexts/core-platform.local.env"

fail() {
    echo "TEST_WORKSTATION_CLI_RESULT=FAIL" >&2
    echo "TEST_WORKSTATION_CLI_FAILURE=$1" >&2
    exit 1
}

HELP="$("$CBS" help)"

grep -Fq \
    'cbs workstation check <context-file>' \
    <<<"$HELP" ||
    fail "HELP_COMMAND_MISSING"

OUTPUT="$(
    "$CBS" workstation check "$CONTEXT"
)"

grep -Fq \
    'CBS_WORKSTATION_PREREQUISITE_RC=0' \
    <<<"$OUTPUT" ||
    fail "PREREQUISITE_RC"

grep -Fq \
    'CBS_WORKSTATION_ISOLATION_RC=0' \
    <<<"$OUTPUT" ||
    fail "ISOLATION_RC"

grep -Fq \
    'CBS_WORKSTATION_STATE=READY' \
    <<<"$OUTPUT" ||
    fail "READY_STATE"

grep -Fq \
    'CBS_WORKSTATION_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "READY_RESULT"

set +e
NO_CONTEXT_OUTPUT="$(
    "$CBS" workstation check 2>&1
)"
NO_CONTEXT_RC=$?
set -e

[[ "$NO_CONTEXT_RC" -eq 64 ]] ||
    fail "MISSING_CONTEXT_RC"

grep -Fq \
    'CBS_WORKSTATION_ERROR=CONTEXT_FILE_REQUIRED' \
    <<<"$NO_CONTEXT_OUTPUT" ||
    fail "MISSING_CONTEXT_ERROR"

set +e
UNKNOWN_OUTPUT="$(
    "$CBS" workstation does-not-exist 2>&1
)"
UNKNOWN_RC=$?
set -e

[[ "$UNKNOWN_RC" -eq 2 ]] ||
    fail "UNKNOWN_SUBCOMMAND_RC"

grep -Fq \
    'CBS_ERROR=UNKNOWN_WORKSTATION_COMMAND' \
    <<<"$UNKNOWN_OUTPUT" ||
    fail "UNKNOWN_SUBCOMMAND_ERROR"

echo "TEST_WORKSTATION_CLI_HELP=PASS"
echo "TEST_WORKSTATION_CLI_READY=PASS"
echo "TEST_WORKSTATION_CLI_MISSING_CONTEXT=PASS"
echo "TEST_WORKSTATION_CLI_UNKNOWN_SUBCOMMAND=PASS"
echo "TEST_WORKSTATION_CLI_RESULT=PASS"
