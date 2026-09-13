#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/cbs/platform/platform_hook_runner.sh"

fail() {
    echo "TEST_PLATFORM_HOOK_RUNNER_RESULT=FAIL" >&2
    echo "TEST_PLATFORM_HOOK_RUNNER_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/platform/contract.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
BINDING_DIR="$TMP/framework/platforms/test-platform"
MANIFEST="$BINDING_DIR/platform.env"

mkdir -p "$REPO/.git"
mkdir -p "$REPO/hooks"
mkdir -p "$BINDING_DIR"

cat > "$REPO/hooks/pass.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH

cat > "$REPO/hooks/fail7.sh" <<'SH'
#!/usr/bin/env bash
exit 7
SH

cat > "$REPO/hooks/not-executable.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH

chmod 0755 "$REPO/hooks/pass.sh"
chmod 0755 "$REPO/hooks/fail7.sh"
chmod 0644 "$REPO/hooks/not-executable.sh"

cat > "$MANIFEST" <<EOF_MANIFEST
CBS_PLATFORM_ID=test-platform
CBS_PLATFORM_VERSION=1
CBS_PLATFORM_STACK_ID=test-stack
CBS_PLATFORM_INSTANCE_ID=test-instance
CBS_PLATFORM_REPOSITORY_RELATIVE_PATH=../../../repo
CBS_PLATFORM_HOOK_START=hooks/pass.sh
CBS_PLATFORM_HOOK_CHECK=hooks/fail7.sh
CBS_PLATFORM_HOOK_STATUS=hooks/pass.sh
CBS_PLATFORM_HOOK_STOP=hooks/not-executable.sh
CBS_PLATFORM_HOOK_QUALIFY=hooks/missing.sh
EOF_MANIFEST

echo "TEST_PLATFORM_HOOK_RUNNER_FIXTURE=PASS"

echo
echo "--- success ---"

OUTPUT="$(
    "$RUNNER" "$MANIFEST" start
)"

grep -Fq 'CBS_PLATFORM_RUNNER_ACTION=start' <<<"$OUTPUT" ||
    fail "SUCCESS_ACTION"

grep -Fq 'CBS_PLATFORM_RUNNER_HOOK=hooks/pass.sh' <<<"$OUTPUT" ||
    fail "SUCCESS_HOOK"

grep -Fq 'CBS_PLATFORM_RUNNER_HOOK_RC=0' <<<"$OUTPUT" ||
    fail "SUCCESS_RC"

grep -Fq 'CBS_PLATFORM_RUNNER_RESULT=PASS' <<<"$OUTPUT" ||
    fail "SUCCESS_RESULT"

echo "TEST_PLATFORM_HOOK_RUNNER_SUCCESS=PASS"

echo
echo "--- return code propagation ---"

set +e
OUTPUT="$(
    "$RUNNER" "$MANIFEST" check 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 7 ]] ||
    fail "RETURN_CODE_$RC"

grep -Fq 'CBS_PLATFORM_RUNNER_ACTION=check' <<<"$OUTPUT" ||
    fail "FAIL_ACTION"

grep -Fq 'CBS_PLATFORM_RUNNER_HOOK=hooks/fail7.sh' <<<"$OUTPUT" ||
    fail "FAIL_HOOK"

grep -Fq 'CBS_PLATFORM_RUNNER_HOOK_RC=7' <<<"$OUTPUT" ||
    fail "FAIL_RC_OUTPUT"

grep -Fq 'CBS_PLATFORM_RUNNER_RESULT=FAIL' <<<"$OUTPUT" ||
    fail "FAIL_RESULT"

echo "TEST_PLATFORM_HOOK_RUNNER_RETURN_CODE_PROPAGATION=PASS"

echo
echo "--- not executable ---"

set +e
OUTPUT="$(
    "$RUNNER" "$MANIFEST" stop 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_HOOK_NOT_EXECUTABLE" ]] ||
    fail "NOT_EXECUTABLE_RC_$RC"

grep -Fq \
    'CBS_PLATFORM_RUNNER_ERROR=HOOK_NOT_EXECUTABLE' \
    <<<"$OUTPUT" ||
    fail "NOT_EXECUTABLE_ERROR"

echo "TEST_PLATFORM_HOOK_RUNNER_NOT_EXECUTABLE=PASS"

echo
echo "--- missing hook ---"

set +e
OUTPUT="$(
    "$RUNNER" "$MANIFEST" qualify 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_HOOK_MISSING" ]] ||
    fail "MISSING_RC_$RC"

grep -Fq \
    'CBS_PLATFORM_RUNNER_ERROR=HOOK_MISSING' \
    <<<"$OUTPUT" ||
    fail "MISSING_ERROR"

echo "TEST_PLATFORM_HOOK_RUNNER_MISSING=PASS"

echo
echo "--- invalid action ---"

set +e
OUTPUT="$(
    "$RUNNER" "$MANIFEST" deploy 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_INVALID" ]] ||
    fail "INVALID_ACTION_RC_$RC"

grep -Fq \
    'CBS_PLATFORM_RUNNER_ERROR=INVALID_ACTION' \
    <<<"$OUTPUT" ||
    fail "INVALID_ACTION_ERROR"

echo "TEST_PLATFORM_HOOK_RUNNER_INVALID_ACTION=PASS"

echo
echo "--- usage ---"

set +e
OUTPUT="$(
    "$RUNNER" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_USAGE" ]] ||
    fail "USAGE_RC_$RC"

grep -Fq \
    'CBS_PLATFORM_RUNNER_ERROR=USAGE' \
    <<<"$OUTPUT" ||
    fail "USAGE_ERROR"

echo "TEST_PLATFORM_HOOK_RUNNER_USAGE=PASS"

echo "TEST_PLATFORM_HOOK_RUNNER_RESULT=PASS"
