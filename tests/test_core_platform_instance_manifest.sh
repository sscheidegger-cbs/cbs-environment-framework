#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/instances/core-platform/instance.env"

fail() {
    echo "TEST_CORE_PLATFORM_INSTANCE_MANIFEST_RESULT=FAIL" >&2
    echo "TEST_CORE_PLATFORM_INSTANCE_MANIFEST_FAILURE=$1" >&2
    exit 1
}

[[ -f "$MANIFEST" ]] ||
    fail "MANIFEST_MISSING"

set -a
source "$MANIFEST"
set +a

[[ "$CBS_INSTANCE_ID" == "core-platform-local" ]] ||
    fail "INSTANCE_ID"

[[ "$CBS_INSTANCE_VERSION" == "1" ]] ||
    fail "INSTANCE_VERSION"

[[ "$CBS_INSTANCE_STACK_ID" == "core-platform" ]] ||
    fail "STACK_ID"

echo "TEST_CORE_PLATFORM_INSTANCE_MANIFEST_IDENTITY=PASS"

[[ "$CBS_INSTANCE_CONTAINER_REDIS" == "core-platform-redis" ]]
[[ "$CBS_INSTANCE_CONTAINER_OPENSEARCH" == "core-platform-opensearch" ]]
[[ "$CBS_INSTANCE_CONTAINER_POSTGRES" == "core-platform-postgres" ]]
[[ "$CBS_INSTANCE_CONTAINER_API" == "core-platform-api" ]]
[[ "$CBS_INSTANCE_CONTAINER_KONG" == "core-platform-kong" ]]
[[ "$CBS_INSTANCE_CONTAINER_KEYCLOAK" == "core-platform-keycloak" ]]

echo "TEST_CORE_PLATFORM_INSTANCE_MANIFEST_CONTAINERS=PASS"

[[ "$CBS_INSTANCE_NETWORK" == "core-platform-network" ]] ||
    fail "NETWORK"

[[ "$CBS_INSTANCE_EXTERNAL_VOLUME" == "b15-postgres18-target-data" ]] ||
    fail "EXTERNAL_VOLUME"

echo "TEST_CORE_PLATFORM_INSTANCE_MANIFEST_SHARED_RESOURCES=PASS"

for value in \
    "$CBS_INSTANCE_CONSTRAINT_FIXED_CONTAINER_NAMES" \
    "$CBS_INSTANCE_CONSTRAINT_FIXED_NETWORK_NAME" \
    "$CBS_INSTANCE_CONSTRAINT_FIXED_EXTERNAL_VOLUME" \
    "$CBS_INSTANCE_CONSTRAINT_FIXED_HOST_PORTS"
do
    [[ "$value" == "REQUIRED" ]] ||
        fail "CONSTRAINT_CLASSIFICATION"
done

echo "TEST_CORE_PLATFORM_INSTANCE_MANIFEST_CONSTRAINTS=PASS"

echo "TEST_CORE_PLATFORM_INSTANCE_MANIFEST_RESULT=PASS"
