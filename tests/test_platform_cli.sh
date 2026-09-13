#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"

fail() {
    echo "TEST_PLATFORM_CLI_RESULT=FAIL" >&2
    echo "TEST_PLATFORM_CLI_FAILURE=$1" >&2
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

for action in start check status stop qualify; do
    cat > "$REPO/hooks/$action.sh" <<SH
#!/usr/bin/env bash
echo "FIXTURE_PLATFORM_ACTION=$action"
exit 0
SH
    chmod 0755 "$REPO/hooks/$action.sh"
done

cat > "$MANIFEST" <<EOF_MANIFEST
CBS_PLATFORM_ID=test-platform
CBS_PLATFORM_VERSION=1
CBS_PLATFORM_STACK_ID=test-stack
CBS_PLATFORM_INSTANCE_ID=test-instance
CBS_PLATFORM_REPOSITORY_RELATIVE_PATH=../../../repo
CBS_PLATFORM_HOOK_START=hooks/start.sh
CBS_PLATFORM_HOOK_CHECK=hooks/check.sh
CBS_PLATFORM_HOOK_STATUS=hooks/status.sh
CBS_PLATFORM_HOOK_STOP=hooks/stop.sh
CBS_PLATFORM_HOOK_QUALIFY=hooks/qualify.sh
EOF_MANIFEST

echo "TEST_PLATFORM_CLI_FIXTURE=PASS"

OUTPUT="$(
    "$CBS" platform resolve "$MANIFEST"
)"

grep -Fq 'CBS_PLATFORM_ID=test-platform' <<<"$OUTPUT" ||
    fail "RESOLVE_ID"

grep -Fq 'CBS_PLATFORM_STATE=READY' <<<"$OUTPUT" ||
    fail "RESOLVE_STATE"

grep -Fq 'CBS_PLATFORM_RESOLUTION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "RESOLVE_RESULT"

echo "TEST_PLATFORM_CLI_RESOLVE=PASS"

for action in start check status stop qualify; do
    OUTPUT="$(
        "$CBS" platform "$action" "$MANIFEST"
    )"

    grep -Fq \
        "CBS_PLATFORM_RUNNER_ACTION=$action" \
        <<<"$OUTPUT" ||
        fail "${action}_RUNNER_ACTION"

    grep -Fq \
        "FIXTURE_PLATFORM_ACTION=$action" \
        <<<"$OUTPUT" ||
        fail "${action}_HOOK_OUTPUT"

    grep -Fq \
        'CBS_PLATFORM_RUNNER_HOOK_RC=0' \
        <<<"$OUTPUT" ||
        fail "${action}_HOOK_RC"

    grep -Fq \
        'CBS_PLATFORM_RUNNER_RESULT=PASS' \
        <<<"$OUTPUT" ||
        fail "${action}_RESULT"

    echo "TEST_PLATFORM_CLI_${action^^}=PASS"
done

set +e
OUTPUT="$(
    "$CBS" platform deploy "$MANIFEST" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 2 ]] ||
    fail "UNKNOWN_COMMAND_RC_$RC"

grep -Fq \
    'CBS_ERROR=UNKNOWN_PLATFORM_COMMAND' \
    <<<"$OUTPUT" ||
    fail "UNKNOWN_COMMAND_ERROR"

echo "TEST_PLATFORM_CLI_UNKNOWN_COMMAND=PASS"

set +e
OUTPUT="$(
    "$CBS" platform resolve 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_USAGE" ]] ||
    fail "RESOLVE_USAGE_RC_$RC"

grep -Fq \
    'CBS_PLATFORM_ERROR=MANIFEST_REQUIRED' \
    <<<"$OUTPUT" ||
    fail "RESOLVE_USAGE_ERROR"

echo "TEST_PLATFORM_CLI_RESOLVE_USAGE=PASS"

set +e
OUTPUT="$(
    "$CBS" platform status 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_PLATFORM_USAGE" ]] ||
    fail "RUNNER_USAGE_RC_$RC"

grep -Fq \
    'CBS_PLATFORM_RUNNER_ERROR=USAGE' \
    <<<"$OUTPUT" ||
    fail "RUNNER_USAGE_ERROR"

echo "TEST_PLATFORM_CLI_RUNNER_USAGE=PASS"

HELP="$("$CBS" help)"

for expected in \
    'cbs platform resolve <manifest>' \
    'cbs platform start <manifest>' \
    'cbs platform check <manifest>' \
    'cbs platform status <manifest>' \
    'cbs platform stop <manifest>' \
    'cbs platform qualify <manifest>'
do
    grep -Fq "$expected" <<<"$HELP" ||
        fail "HELP_$expected"
done

echo "TEST_PLATFORM_CLI_HELP=PASS"

echo "TEST_PLATFORM_CLI_RESULT=PASS"
