#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/toolchain/toolchain_manager.sh"

fail() {
    echo "TEST_TOOLCHAIN_NOT_APPLICABLE_RESULT=FAIL" >&2
    echo "TEST_TOOLCHAIN_NOT_APPLICABLE_FAILURE=$1" >&2
    return 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROVIDER_DIR="$TMP/providers"
TOOLCHAIN_ROOT="$TMP/toolchains"
MANIFEST="$TMP/toolchain.env"

mkdir -p "$PROVIDER_DIR"

cat > "$MANIFEST" <<'MANIFEST'
CBS_TOOLCHAIN_ID=host-bound
CBS_TOOLCHAIN_VERSION=1
CBS_TOOLCHAIN_PROVIDER=host-bound
MANIFEST

cat > "$PROVIDER_DIR/host-bound.sh" <<'PROVIDER'
#!/usr/bin/env bash

set -Eeuo pipefail

operation="${1:-}"
toolchain_id="${2:-}"
requested_version="${3:-}"
toolchain_root="${4:-}"

resolved_path="$toolchain_root/$toolchain_id/$requested_version"

case "$operation" in
    DETECT)
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=NOT_APPLICABLE"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        echo "CBS_TOOLCHAIN_PROVIDER_REASON=HOST_PLATFORM_UNSUPPORTED"
        ;;
    ENSURE|VERIFY)
        echo "CBS_TOOLCHAIN_PROVIDER_ERROR=UNEXPECTED_MUTATION_OR_VERIFY" >&2
        exit 82
        ;;
    *)
        exit 82
        ;;
esac
PROVIDER

chmod +x "$PROVIDER_DIR/host-bound.sh"

printf '%s\n' '--- RESOLVE NOT_APPLICABLE ---'

set +e
OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" resolve "$MANIFEST" 2>&1
)"
RC=$?
set -e

printf 'NOT_APPLICABLE_RESOLVE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 0 ]] ||
    fail "RESOLVE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_INSTALLATION_STATE=NOT_APPLICABLE' \
    <<<"$OUTPUT" ||
    fail "RESOLVE_STATE"

grep -Fq \
    'CBS_TOOLCHAIN_DECISION=BLOCK' \
    <<<"$OUTPUT" ||
    fail "RESOLVE_DECISION"

grep -Fq \
    'CBS_TOOLCHAIN_MUTATION=NONE' \
    <<<"$OUTPUT" ||
    fail "RESOLVE_MUTATION"

[[ ! -e "$TOOLCHAIN_ROOT/host-bound/1" ]] ||
    fail "RESOLVE_MUTATED"

echo "TEST_TOOLCHAIN_NOT_APPLICABLE_RESOLVE=PASS"

printf '%s\n' '--- ENSURE MUST BLOCK WITHOUT PROVIDER MUTATION ---'

set +e
OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" ensure "$MANIFEST" 2>&1
)"
RC=$?
set -e

printf 'NOT_APPLICABLE_ENSURE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "ENSURE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_ERROR=BLOCKED' \
    <<<"$OUTPUT" ||
    fail "ENSURE_BLOCK"

if grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ERROR=UNEXPECTED_MUTATION_OR_VERIFY' \
    <<<"$OUTPUT"
then
    fail "PROVIDER_OPERATION_CALLED"
fi

[[ ! -e "$TOOLCHAIN_ROOT/host-bound/1" ]] ||
    fail "ENSURE_MUTATED"

echo "TEST_TOOLCHAIN_NOT_APPLICABLE_ENSURE=PASS"
echo "TEST_TOOLCHAIN_NOT_APPLICABLE_RESULT=PASS"
