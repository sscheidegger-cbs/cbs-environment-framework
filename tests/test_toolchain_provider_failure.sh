#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/toolchain/toolchain_manager.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROVIDER_DIR="$TMP/providers"
TOOLCHAIN_ROOT="$TMP/toolchains"
MANIFEST="$TMP/toolchain.env"

mkdir -p "$PROVIDER_DIR"

cat > "$MANIFEST" <<'MANIFEST'
CBS_TOOLCHAIN_ID=failing
CBS_TOOLCHAIN_VERSION=1.0.0
CBS_TOOLCHAIN_PROVIDER=failing
MANIFEST

cat > "$PROVIDER_DIR/failing.sh" <<'PROVIDER'
#!/usr/bin/env bash

set -Eeuo pipefail

operation="${1:-}"
toolchain_id="${2:-}"
requested_version="${3:-}"
toolchain_root="${4:-}"

resolved_path="$toolchain_root/$toolchain_id/$requested_version"

case "$operation" in
    DETECT)
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        ;;
    ENSURE)
        echo "CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=FAIL"
        exit 82
        ;;
    VERIFY)
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        exit 82
        ;;
    *)
        exit 82
        ;;
esac
PROVIDER

chmod +x "$PROVIDER_DIR/failing.sh"

fail() {
    echo "TEST_TOOLCHAIN_PROVIDER_FAILURE_RESULT=FAIL" >&2
    echo "TEST_TOOLCHAIN_PROVIDER_FAILURE_FAILURE=$1" >&2
    return 1
}

printf '%s\n' '--- RESOLVE REMAINS READ-ONLY ---'

set +e
OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" resolve "$MANIFEST" 2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 0 ]] ||
    fail "RESOLVE_RC"

grep -Fq 'CBS_TOOLCHAIN_INSTALLATION_STATE=MISSING' <<<"$OUTPUT" ||
    fail "RESOLVE_STATE"

grep -Fq 'CBS_TOOLCHAIN_DECISION=INSTALL' <<<"$OUTPUT" ||
    fail "RESOLVE_DECISION"

grep -Fq 'CBS_TOOLCHAIN_MUTATION=NONE' <<<"$OUTPUT" ||
    fail "RESOLVE_MUTATION"

[[ ! -e "$TOOLCHAIN_ROOT/failing/1.0.0" ]] ||
    fail "RESOLVE_MUTATED"

echo "TEST_TOOLCHAIN_PROVIDER_FAILURE_RESOLVE=PASS"

printf '%s\n' '--- ENSURE FAILURE MUST PROPAGATE CONTROLLED RC ---'

set +e
OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" ensure "$MANIFEST" 2>&1
)"
RC=$?
set -e

printf 'OBSERVED_ENSURE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "ENSURE_FAILURE_RC"

grep -Fq 'CBS_TOOLCHAIN_ERROR=PROVIDER_FAILURE' <<<"$OUTPUT" ||
    fail "ENSURE_FAILURE_ERROR"

if grep -Fq 'command not found' <<<"$OUTPUT"; then
    fail "SHELL_COMMAND_ERROR"
fi

echo "TEST_TOOLCHAIN_PROVIDER_FAILURE_ENSURE=PASS"

printf '%s\n' '--- ENSURE ZERO RC WITHOUT PASS MARKER MUST FAIL CLEANLY ---'

cat > "$PROVIDER_DIR/failing.sh" <<'PROVIDER'
#!/usr/bin/env bash

set -Eeuo pipefail

operation="${1:-}"
toolchain_id="${2:-}"
requested_version="${3:-}"
toolchain_root="${4:-}"

resolved_path="$toolchain_root/$toolchain_id/$requested_version"

case "$operation" in
    DETECT)
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        ;;
    ENSURE)
        echo "CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=FAIL"
        exit 0
        ;;
    VERIFY)
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        exit 82
        ;;
    *)
        exit 82
        ;;
esac
PROVIDER

chmod +x "$PROVIDER_DIR/failing.sh"

set +e
OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" ensure "$MANIFEST" 2>&1
)"
RC=$?
set -e

printf 'OBSERVED_ZERO_RC_ENSURE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "ENSURE_RESULT_FAILURE_RC"

grep -Fq 'CBS_TOOLCHAIN_ERROR=ENSURE_FAILED' <<<"$OUTPUT" ||
    fail "ENSURE_RESULT_FAILURE_ERROR"

if grep -Fq 'command not found' <<<"$OUTPUT"; then
    fail "ENSURE_RESULT_SHELL_COMMAND_ERROR"
fi

echo "TEST_TOOLCHAIN_PROVIDER_FAILURE_ENSURE_RESULT=PASS"
echo "TEST_TOOLCHAIN_PROVIDER_FAILURE_RESULT=PASS"
