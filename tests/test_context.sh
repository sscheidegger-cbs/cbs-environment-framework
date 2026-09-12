#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/cbs/context/context.sh"
CONTEXT="$ROOT/config/contexts/core-platform.local.env"

source "$LIB"

fail() {
    echo "TEST_CONTEXT_RESULT=FAIL" >&2
    echo "TEST_CONTEXT_FAILURE=$1" >&2
    exit 1
}

cbs_context_load "$CONTEXT"

[[ "$CBS_CONTEXT_VERSION" == "1" ]] || fail "VERSION"
[[ "$CBS_CONTEXT_CLIENT" == "ourea" ]] || fail "CLIENT"
[[ "$CBS_CONTEXT_ENTITY_TYPE" == "platform" ]] || fail "ENTITY_TYPE"
[[ "$CBS_CONTEXT_ENTITY_NAME" == "core-platform" ]] || fail "ENTITY_NAME"
[[ "$CBS_CONTEXT_REPOSITORY_PATH" == "/home/sscheidegger/projects/core-platform" ]] || fail "REPOSITORY_PATH"
[[ "$CBS_CONTEXT_BRANCH" == "fix/b06-keycloak-kong-e2e" ]] || fail "BRANCH"
[[ "$CBS_CONTEXT_ENVIRONMENT" == "LOCAL" ]] || fail "ENVIRONMENT"

INVALID="$(mktemp)"
trap 'rm -f "$INVALID"' EXIT

cp "$CONTEXT" "$INVALID"
printf "%s\n" "CBS_CONTEXT_UNKNOWN=value" >> "$INVALID"

set +e
ERROR_OUTPUT="$(cbs_context_load "$INVALID" 2>&1)"
ERROR_RC=$?
set -e

[[ "$ERROR_RC" -eq 12 ]] || fail "UNKNOWN_KEY_RC"
grep -Fq "CBS_CONTEXT_ERROR=UNKNOWN_KEY" <<<"$ERROR_OUTPUT" || fail "UNKNOWN_KEY_ERROR"

echo "TEST_CONTEXT_READ=PASS"
echo "TEST_CONTEXT_VALIDATE=PASS"
echo "TEST_CONTEXT_UNKNOWN_KEY=PASS"
echo "TEST_CONTEXT_RESULT=PASS"
