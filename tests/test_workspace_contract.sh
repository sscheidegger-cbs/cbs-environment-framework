#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/workspace/contract.sh"

fail() {
    echo "TEST_WORKSPACE_CONTRACT_RESULT=FAIL" >&2
    echo "TEST_WORKSPACE_CONTRACT_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"

[[ "$CBS_WORKSPACE_CONTRACT_VERSION" == "1" ]] ||
    fail "VERSION"

[[ "$CBS_WORKSPACE_RC_OK" -eq 0 ]] ||
    fail "RC_OK"

[[ "$CBS_WORKSPACE_RC_MISSING" -eq 40 ]] ||
    fail "RC_MISSING"

[[ "$CBS_WORKSPACE_RC_INVALID" -eq 41 ]] ||
    fail "RC_INVALID"

[[ "$CBS_WORKSPACE_RC_UNKNOWN" -eq 42 ]] ||
    fail "RC_UNKNOWN"

[[ "$CBS_WORKSPACE_RC_USAGE" -eq 64 ]] ||
    fail "RC_USAGE"

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

mkdir "$TMP_DIR/workspace"
touch "$TMP_DIR/file"

CLASS="$(
    cbs_workspace_classify_path "$TMP_DIR/workspace"
)"

[[ "$CLASS" == "$CBS_WORKSPACE_PATH_DIRECTORY" ]] ||
    fail "DIRECTORY_CLASS"

STATE="$(
    cbs_workspace_state_from_path_class "$CLASS"
)"

[[ "$STATE" == "$CBS_WORKSPACE_READY" ]] ||
    fail "READY_STATE"

CLASS="$(
    cbs_workspace_classify_path "$TMP_DIR/missing"
)"

[[ "$CLASS" == "$CBS_WORKSPACE_PATH_ABSENT" ]] ||
    fail "ABSENT_CLASS"

STATE="$(
    cbs_workspace_state_from_path_class "$CLASS"
)"

[[ "$STATE" == "$CBS_WORKSPACE_MISSING" ]] ||
    fail "MISSING_STATE"

CLASS="$(
    cbs_workspace_classify_path "$TMP_DIR/file"
)"

[[ "$CLASS" == "$CBS_WORKSPACE_PATH_FILE" ]] ||
    fail "FILE_CLASS"

STATE="$(
    cbs_workspace_state_from_path_class "$CLASS"
)"

[[ "$STATE" == "$CBS_WORKSPACE_INVALID" ]] ||
    fail "INVALID_STATE"

STATE="$(
    cbs_workspace_state_from_path_class "UNSUPPORTED"
)"

[[ "$STATE" == "$CBS_WORKSPACE_UNKNOWN" ]] ||
    fail "UNKNOWN_STATE"

set +e
cbs_workspace_rc_from_state "$CBS_WORKSPACE_READY"
RC=$?
set -e

[[ "$RC" -eq "$CBS_WORKSPACE_RC_OK" ]] ||
    fail "READY_RC"

set +e
cbs_workspace_rc_from_state "$CBS_WORKSPACE_MISSING"
RC=$?
set -e

[[ "$RC" -eq "$CBS_WORKSPACE_RC_MISSING" ]] ||
    fail "MISSING_RC"

set +e
cbs_workspace_rc_from_state "$CBS_WORKSPACE_INVALID"
RC=$?
set -e

[[ "$RC" -eq "$CBS_WORKSPACE_RC_INVALID" ]] ||
    fail "INVALID_RC"

set +e
cbs_workspace_rc_from_state "$CBS_WORKSPACE_UNKNOWN"
RC=$?
set -e

[[ "$RC" -eq "$CBS_WORKSPACE_RC_UNKNOWN" ]] ||
    fail "UNKNOWN_RC"

echo "TEST_WORKSPACE_CONTRACT_VERSION=PASS"
echo "TEST_WORKSPACE_CONTRACT_PATH_CLASSIFICATION=PASS"
echo "TEST_WORKSPACE_CONTRACT_STATE=PASS"
echo "TEST_WORKSPACE_CONTRACT_RETURN_CODES=PASS"
echo "TEST_WORKSPACE_CONTRACT_RESULT=PASS"
