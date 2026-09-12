#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/workspace/workspace_manager.sh"

fail() {
    echo "TEST_WORKSPACE_MANAGER_RESULT=FAIL" >&2
    echo "TEST_WORKSPACE_MANAGER_FAILURE=$1" >&2
    exit 1
}

TMP="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP"
}

trap cleanup EXIT

WORKSPACE="$TMP/workspace"

OUTPUT="$(
    "$MANAGER" "$WORKSPACE" 2>&1
)"

grep -Fq \
    'CBS_WORKSPACE_STATE_BEFORE=MISSING' \
    <<<"$OUTPUT" ||
    fail "CREATE_STATE_BEFORE"

grep -Fq \
    'CBS_WORKSPACE_ACTION=CREATE' \
    <<<"$OUTPUT" ||
    fail "CREATE_ACTION"

grep -Fq \
    'CBS_WORKSPACE_STATE_AFTER=READY' \
    <<<"$OUTPUT" ||
    fail "CREATE_STATE_AFTER"

grep -Fq \
    'CBS_WORKSPACE_STATE=READY' \
    <<<"$OUTPUT" ||
    fail "CREATE_RESULT"

[[ -d "$WORKSPACE" ]] ||
    fail "WORKSPACE_NOT_CREATED"

echo "TEST_WORKSPACE_MANAGER_CREATE=PASS"

OUTPUT="$(
    "$MANAGER" "$WORKSPACE" 2>&1
)"

grep -Fq \
    'CBS_WORKSPACE_STATE_BEFORE=READY' \
    <<<"$OUTPUT" ||
    fail "REUSE_STATE"

grep -Fq \
    'CBS_WORKSPACE_ACTION=REUSE' \
    <<<"$OUTPUT" ||
    fail "REUSE_ACTION"

echo "TEST_WORKSPACE_MANAGER_REUSE=PASS"

INVALID="$TMP/file"
printf '%s\n' "preserve me" > "$INVALID"

set +e
OUTPUT="$(
    "$MANAGER" "$INVALID" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 41 ]] ||
    fail "INVALID_RC"

grep -Fq \
    'CBS_WORKSPACE_ACTION=BLOCK' \
    <<<"$OUTPUT" ||
    fail "INVALID_ACTION"

grep -Fq \
    'CBS_WORKSPACE_ERROR=TARGET_INVALID' \
    <<<"$OUTPUT" ||
    fail "INVALID_ERROR"

[[ "$(cat "$INVALID")" == "preserve me" ]] ||
    fail "INVALID_CONTENT_MUTATED"

echo "TEST_WORKSPACE_MANAGER_INVALID_BLOCK=PASS"

NESTED="$TMP/missing-parent/workspace"

set +e
OUTPUT="$(
    "$MANAGER" "$NESTED" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 40 ]] ||
    fail "MISSING_PARENT_RC"

grep -Fq \
    'CBS_WORKSPACE_ACTION=BLOCK' \
    <<<"$OUTPUT" ||
    fail "MISSING_PARENT_ACTION"

grep -Fq \
    'CBS_WORKSPACE_ERROR=PARENT_DIRECTORY_MISSING' \
    <<<"$OUTPUT" ||
    fail "MISSING_PARENT_ERROR"

[[ ! -e "$TMP/missing-parent" ]] ||
    fail "PARENT_CREATED_RECURSIVELY"

echo "TEST_WORKSPACE_MANAGER_NO_RECURSIVE_PARENT_CREATE=PASS"

set +e
OUTPUT="$("$MANAGER" 2>&1)"
RC=$?
set -e

[[ "$RC" -eq 64 ]] ||
    fail "USAGE_RC"

grep -Fq \
    'CBS_WORKSPACE_ERROR=WORKSPACE_PATH_REQUIRED' \
    <<<"$OUTPUT" ||
    fail "USAGE_ERROR"

echo "TEST_WORKSPACE_MANAGER_USAGE=PASS"
echo "TEST_WORKSPACE_MANAGER_RESULT=PASS"
