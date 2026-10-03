#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVALUATOR="$ROOT/cbs/stack/stack_toolchain_evaluator.sh"

fail() {
    echo "TEST_STACK_TOOLCHAIN_NOT_APPLICABLE_RESULT=FAIL" >&2
    echo "TEST_STACK_TOOLCHAIN_NOT_APPLICABLE_FAILURE=$1" >&2
    return 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROVIDER_DIR="$TMP/providers"
TOOLCHAIN_ROOT="$TMP/toolchains"
STACK_MANIFEST="$TMP/stack.env"

mkdir -p "$PROVIDER_DIR"

cat > "$PROVIDER_DIR/host-bound.sh" <<'PROVIDER'
#!/usr/bin/env bash

set -Eeuo pipefail

operation="${1:-}"
toolchain_id="${2:-}"
requested_version="${3:-}"
toolchain_root="${4:-}"

[[ "$operation" == "DETECT" ]] || {
    echo "CBS_TOOLCHAIN_PROVIDER_ERROR=UNEXPECTED_OPERATION" >&2
    exit 82
}

echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=NOT_APPLICABLE"
echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$toolchain_root/$toolchain_id/$requested_version"
echo "CBS_TOOLCHAIN_PROVIDER_REASON=HOST_PLATFORM_UNSUPPORTED"
PROVIDER

chmod +x "$PROVIDER_DIR/host-bound.sh"

cat > "$STACK_MANIFEST" <<'MANIFEST'
CBS_STACK_ID=host-bound-stack
CBS_STACK_VERSION=1

CBS_STACK_MANAGED_TOOLCHAIN_IDS=HOST_BOUND

CBS_STACK_MANAGED_TOOLCHAIN_HOST_BOUND_REQUIREMENT=REQUIRED
CBS_STACK_MANAGED_TOOLCHAIN_HOST_BOUND_ID=host-bound
CBS_STACK_MANAGED_TOOLCHAIN_HOST_BOUND_VERSION=1
CBS_STACK_MANAGED_TOOLCHAIN_HOST_BOUND_PROVIDER=host-bound

CBS_STACK_MANIFEST_CAPABILITY_CHECK=check
MANIFEST

printf '%s\n' '--- EVALUATE REQUIRED + NOT_APPLICABLE ---'

set +e
OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$EVALUATOR" "$STACK_MANIFEST" \
    2>&1
)"
RC=$?
set -e

printf 'STACK_NOT_APPLICABLE_EVALUATE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "EVALUATE_RC"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_INSTALLATION_STATE=NOT_APPLICABLE' \
    <<<"$OUTPUT" ||
    fail "INSTALLATION_STATE"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_DECISION=BLOCK' \
    <<<"$OUTPUT" ||
    fail "DECISION"

grep -Fq \
    'CBS_STACK_MANAGED_TOOLCHAIN_MUTATION=NONE' \
    <<<"$OUTPUT" ||
    fail "MUTATION"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_REQUIRED_COUNT=1' \
    <<<"$OUTPUT" ||
    fail "REQUIRED_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_MISSING_COUNT=0' \
    <<<"$OUTPUT" ||
    fail "MISSING_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_NOT_APPLICABLE_COUNT=1' \
    <<<"$OUTPUT" ||
    fail "NOT_APPLICABLE_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_FAILURE_COUNT=0' \
    <<<"$OUTPUT" ||
    fail "FAILURE_COUNT"

grep -Fq \
    'CBS_STACK_TOOLCHAIN_EVALUATION_RESULT=PASS' \
    <<<"$OUTPUT" ||
    fail "EVALUATION_RESULT"

echo "TEST_STACK_TOOLCHAIN_NOT_APPLICABLE_RESULT=PASS"
