#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/toolchain/toolchain_manager.sh"

fail() {
    echo "TEST_TOOLCHAIN_RECONCILE_RESULT=FAIL" >&2
    echo "TEST_TOOLCHAIN_RECONCILE_FAILURE=$1" >&2
    return 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROVIDER_DIR="$TMP/providers"
TOOLCHAIN_ROOT="$TMP/toolchains"
MANIFEST="$TMP/toolchain.env"

mkdir -p "$PROVIDER_DIR"

cat > "$MANIFEST" <<'MANIFEST'
CBS_TOOLCHAIN_ID=synthetic
CBS_TOOLCHAIN_VERSION=2.0.0
CBS_TOOLCHAIN_PROVIDER=synthetic
MANIFEST

cat > "$PROVIDER_DIR/synthetic.sh" <<'PROVIDER'
#!/usr/bin/env bash
set -Eeuo pipefail

operation="${1:-}"
toolchain_id="${2:-}"
requested_version="${3:-}"
toolchain_root="${4:-}"

resolved_path="$toolchain_root/$toolchain_id/$requested_version"

case "$operation" in
    DETECT)
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_INCOMPATIBLE"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        ;;
    ENSURE|VERIFY|RESOLVE)
        echo "CBS_TOOLCHAIN_PROVIDER_ERROR=UNEXPECTED_CALL" >&2
        exit 82
        ;;
    *)
        exit 82
        ;;
esac
PROVIDER

chmod +x "$PROVIDER_DIR/synthetic.sh"

printf '%s\n' '--- RESOLVE CLASSIFICATION ---'

OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" resolve "$MANIFEST"
)"

grep -Fq \
    'CBS_TOOLCHAIN_INSTALLATION_STATE=PRESENT_INCOMPATIBLE' \
    <<<"$OUTPUT" ||
    fail "INCOMPATIBLE_STATE"

grep -Fq \
    'CBS_TOOLCHAIN_DECISION=RECONCILE' \
    <<<"$OUTPUT" ||
    fail "RECONCILE_DECISION"

grep -Fq \
    'CBS_TOOLCHAIN_MUTATION=NONE' \
    <<<"$OUTPUT" ||
    fail "RESOLVE_MUTATION"

echo "TEST_TOOLCHAIN_RECONCILE_RESOLVE=PASS"

printf '%s\n' '--- ENSURE MUST BLOCK EXPLICITLY ---'

set +e
OUTPUT="$(
    CBS_TOOLCHAIN_PROVIDER_DIR="$PROVIDER_DIR" \
    CBS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    "$MANAGER" ensure "$MANIFEST" 2>&1
)"
RC=$?
set -e

printf 'RECONCILE_ENSURE_RC=%s\n' "$RC"
printf '%s\n' "$OUTPUT"

[[ "$RC" -eq 82 ]] ||
    fail "RECONCILE_RC"

grep -Fq \
    'CBS_TOOLCHAIN_ERROR=RECONCILE_NOT_IMPLEMENTED' \
    <<<"$OUTPUT" ||
    fail "RECONCILE_ERROR"

if grep -Fq \
    'CBS_TOOLCHAIN_PROVIDER_ERROR=UNEXPECTED_CALL' \
    <<<"$OUTPUT"
then
    fail "PROVIDER_MUTATION_CALLED"
fi

echo "TEST_TOOLCHAIN_RECONCILE_BLOCK=PASS"
echo "TEST_TOOLCHAIN_RECONCILE_RESULT=PASS"
