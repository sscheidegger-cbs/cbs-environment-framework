#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT/cbs/stack/stack_resolver.sh"
MANIFEST="$ROOT/stacks/core-platform/stack.env"

fail() {
    echo "TEST_STACK_RESOLVER_RESULT=FAIL" >&2
    echo "TEST_STACK_RESOLVER_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/stack/contract.sh"

OUTPUT="$("$RESOLVER" "$MANIFEST")"

grep -Fq 'CBS_STACK_ID=core-platform' <<<"$OUTPUT" ||
    fail "STACK_ID"

grep -Fq 'CBS_STACK_VERSION=1' <<<"$OUTPUT" ||
    fail "STACK_VERSION"

grep -Fq 'CBS_STACK_STATE=READY' <<<"$OUTPUT" ||
    fail "STACK_STATE"

for prerequisite in \
    GIT \
    UV \
    DOCKER \
    DOCKER_COMPOSE \
    PYTHON_312
do
    grep -Fq \
        "CBS_STACK_PREREQUISITE_NAME=$prerequisite" \
        <<<"$OUTPUT" ||
        fail "PREREQUISITE_$prerequisite"
done

echo "TEST_STACK_RESOLVER_PREREQUISITES=PASS"

for component in \
    FASTAPI \
    SQLALCHEMY \
    ALEMBIC \
    POSTGRESQL \
    POSTGIS \
    PGVECTOR \
    REDIS \
    OPENSEARCH \
    KONG \
    KEYCLOAK
do
    grep -Fq \
        "CBS_STACK_COMPONENT_NAME=$component" \
        <<<"$OUTPUT" ||
        fail "COMPONENT_$component"
done

echo "TEST_STACK_RESOLVER_COMPONENTS=PASS"

for capability in \
    start \
    check \
    status \
    qualify
do
    grep -Fq \
        "CBS_STACK_CAPABILITY=$capability" \
        <<<"$OUTPUT" ||
        fail "CAPABILITY_$capability"
done

echo "TEST_STACK_RESOLVER_CAPABILITIES=PASS"

grep -Fq 'CBS_STACK_RESOLUTION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "RESULT"

set +e
MISSING_OUTPUT="$("$RESOLVER" 2>&1)"
MISSING_RC=$?
set -e

[[ "$MISSING_RC" -eq "$CBS_RC_STACK_USAGE" ]] ||
    fail "MISSING_MANIFEST_RC"

grep -Fq 'CBS_STACK_ERROR=MANIFEST_REQUIRED' <<<"$MISSING_OUTPUT" ||
    fail "MISSING_MANIFEST_ERROR"

echo "TEST_STACK_RESOLVER_USAGE=PASS"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

INVALID="$TMP/invalid.env"

printf '%s\n' \
    'CBS_STACK_VERSION=1' \
    > "$INVALID"

set +e
INVALID_OUTPUT="$("$RESOLVER" "$INVALID" 2>&1)"
INVALID_RC=$?
set -e

[[ "$INVALID_RC" -eq "$CBS_RC_STACK_INVALID" ]] ||
    fail "INVALID_MANIFEST_RC"

grep -Fq 'CBS_STACK_STATE=INVALID' <<<"$INVALID_OUTPUT" ||
    fail "INVALID_MANIFEST_STATE"

echo "TEST_STACK_RESOLVER_INVALID=PASS"

echo "TEST_STACK_RESOLVER_RESULT=PASS"

# D01b-B — generic declaration discovery
#
# The generic Stack resolver must discover manifest declarations without
# requiring the technology/resource name to be hardcoded in the resolver.

GENERIC_MANIFEST="$TMP/generic-stack.env"

cat > "$GENERIC_MANIFEST" <<'MANIFEST'
CBS_STACK_ID=d01bb-generic-test
CBS_STACK_VERSION=1

CBS_STACK_PREREQUISITE_GIT=REQUIRED
CBS_STACK_PREREQUISITE_D01BB_SYNTHETIC_TOOL=OPTIONAL

CBS_STACK_COMPONENT_D01BB_SYNTHETIC_RUNTIME=REQUIRED

CBS_STACK_MANIFEST_CAPABILITY_CHECK=check
MANIFEST

GENERIC_OUTPUT="$("$RESOLVER" "$GENERIC_MANIFEST")"

grep -Fq \
    'CBS_STACK_PREREQUISITE_NAME=D01BB_SYNTHETIC_TOOL' \
    <<<"$GENERIC_OUTPUT" ||
    fail "GENERIC_PREREQUISITE_DISCOVERY"

grep -Fq \
    'CBS_STACK_PREREQUISITE_REQUIREMENT=OPTIONAL' \
    <<<"$GENERIC_OUTPUT" ||
    fail "GENERIC_PREREQUISITE_REQUIREMENT"

grep -Fq \
    'CBS_STACK_COMPONENT_NAME=D01BB_SYNTHETIC_RUNTIME' \
    <<<"$GENERIC_OUTPUT" ||
    fail "GENERIC_COMPONENT_DISCOVERY"

grep -Fq \
    'CBS_STACK_COMPONENT_REQUIREMENT=REQUIRED' \
    <<<"$GENERIC_OUTPUT" ||
    fail "GENERIC_COMPONENT_REQUIREMENT"

grep -Fq \
    'CBS_STACK_CAPABILITY=check' \
    <<<"$GENERIC_OUTPUT" ||
    fail "GENERIC_CAPABILITY_DISCOVERY"

echo "TEST_STACK_RESOLVER_GENERIC_DISCOVERY=PASS"
