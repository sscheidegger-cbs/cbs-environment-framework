#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MANAGER="$ROOT/cbs/workstation/workstation_manager.sh"
CONTRACT="$ROOT/cbs/workstation/contract.sh"
CONTEXT="$ROOT/config/contexts/core-platform.local.env"

fail() {
    echo "TEST_WORKSTATION_MANAGER_RESULT=FAIL" >&2
    echo "TEST_WORKSTATION_MANAGER_FAILURE=$1" >&2
    exit 1
}

source "$CONTRACT"

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

REAL_OUTPUT="$("$MANAGER" "$CONTEXT")"

grep -Fq 'CBS_WORKSTATION_PREREQUISITE_RC=0' <<<"$REAL_OUTPUT" ||
    fail "READY_PREREQUISITE_RC"

grep -Fq 'CBS_WORKSTATION_ISOLATION_RC=0' <<<"$REAL_OUTPUT" ||
    fail "READY_ISOLATION_RC"

grep -Fq 'CBS_WORKSTATION_STATE=READY' <<<"$REAL_OUTPUT" ||
    fail "READY_STATE"

grep -Fq 'CBS_WORKSTATION_RESULT=PASS' <<<"$REAL_OUTPUT" ||
    fail "READY_RESULT"

echo "TEST_WORKSTATION_MANAGER_READY=PASS"

cat > "$TMP_DIR/prerequisite-fail.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "CBS_PREREQUISITE_RESULT=FAIL"
exit 10
SCRIPT

chmod 0755 "$TMP_DIR/prerequisite-fail.sh"

set +e
OUTPUT="$(
    CBS_PREREQUISITE_CHECKER="$TMP_DIR/prerequisite-fail.sh" \
        "$MANAGER" "$CONTEXT" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PREREQUISITE_FAILURE" ]] ||
    fail "INCOMPLETE_RC"

grep -Fq 'CBS_WORKSTATION_STATE=INCOMPLETE' <<<"$OUTPUT" ||
    fail "INCOMPLETE_STATE"

grep -Fq 'CBS_WORKSTATION_RESULT=FAIL' <<<"$OUTPUT" ||
    fail "INCOMPLETE_RESULT"

echo "TEST_WORKSTATION_MANAGER_INCOMPLETE=PASS"

cat > "$TMP_DIR/prerequisite-pass.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "CBS_PREREQUISITE_RESULT=PASS"
exit 0
SCRIPT

cat > "$TMP_DIR/isolation-conflict.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "CBS_ISOLATION_CONFLICTS=1"
echo "CBS_ISOLATION_RESULT=FAIL"
exit 20
SCRIPT

chmod 0755 \
    "$TMP_DIR/prerequisite-pass.sh" \
    "$TMP_DIR/isolation-conflict.sh"

set +e
OUTPUT="$(
    CBS_PREREQUISITE_CHECKER="$TMP_DIR/prerequisite-pass.sh" \
    CBS_ISOLATION_CHECKER="$TMP_DIR/isolation-conflict.sh" \
        "$MANAGER" "$CONTEXT" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_ISOLATION_CONFLICT" ]] ||
    fail "CONFLICT_RC"

grep -Fq 'CBS_WORKSTATION_STATE=CONFLICT' <<<"$OUTPUT" ||
    fail "CONFLICT_STATE"

grep -Fq 'CBS_WORKSTATION_RESULT=FAIL' <<<"$OUTPUT" ||
    fail "CONFLICT_RESULT"

echo "TEST_WORKSTATION_MANAGER_CONFLICT=PASS"

cat > "$TMP_DIR/unknown.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "SIMULATED_UNKNOWN_FAILURE=YES"
exit 99
SCRIPT

chmod 0755 "$TMP_DIR/unknown.sh"

set +e
OUTPUT="$(
    CBS_PREREQUISITE_CHECKER="$TMP_DIR/unknown.sh" \
        "$MANAGER" "$CONTEXT" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_INVALID_INPUT" ]] ||
    fail "UNKNOWN_RC"

grep -Fq 'CBS_WORKSTATION_STATE=UNKNOWN' <<<"$OUTPUT" ||
    fail "UNKNOWN_STATE"

grep -Fq 'CBS_WORKSTATION_RESULT=UNKNOWN' <<<"$OUTPUT" ||
    fail "UNKNOWN_RESULT"

echo "TEST_WORKSTATION_MANAGER_UNKNOWN=PASS"

set +e
OUTPUT="$("$MANAGER" 2>&1)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_INVALID_CONTEXT" ]] ||
    fail "CONTEXT_RC"

grep -Fq \
    'CBS_WORKSTATION_ERROR=CONTEXT_FILE_REQUIRED' \
    <<<"$OUTPUT" ||
    fail "CONTEXT_ERROR"

echo "TEST_WORKSTATION_MANAGER_CONTEXT=PASS"
echo "TEST_WORKSTATION_MANAGER_RESULT=PASS"
