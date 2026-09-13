#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/platforms/core-platform/platform.env"

fail() {
    echo "TEST_CORE_PLATFORM_BINDING_MANIFEST_RESULT=FAIL" >&2
    echo "TEST_CORE_PLATFORM_BINDING_MANIFEST_FAILURE=$1" >&2
    exit 1
}

[[ -f "$MANIFEST" ]] ||
    fail "MANIFEST_MISSING"

set -a
source "$MANIFEST"
set +a

[[ "${CBS_PLATFORM_ID:-}" == "core-platform" ]] ||
    fail "PLATFORM_ID"

[[ "${CBS_PLATFORM_VERSION:-}" == "1" ]] ||
    fail "PLATFORM_VERSION"

[[ "${CBS_PLATFORM_STACK_ID:-}" == "core-platform" ]] ||
    fail "STACK_ID"

[[ "${CBS_PLATFORM_INSTANCE_ID:-}" == "core-platform-local" ]] ||
    fail "INSTANCE_ID"

[[ "${CBS_PLATFORM_REPOSITORY_RELATIVE_PATH:-}" == "../../../core-platform" ]] ||
    fail "REPOSITORY_PATH"

echo "TEST_CORE_PLATFORM_BINDING_MANIFEST_IDENTITY=PASS"

[[ "${CBS_PLATFORM_HOOK_START:-}" == "scripts/start_dev.sh" ]] ||
    fail "HOOK_START"

[[ "${CBS_PLATFORM_HOOK_CHECK:-}" == "scripts/check_dev.sh" ]] ||
    fail "HOOK_CHECK"

[[ "${CBS_PLATFORM_HOOK_STATUS:-}" == "scripts/status_dev.sh" ]] ||
    fail "HOOK_STATUS"

[[ "${CBS_PLATFORM_HOOK_STOP:-}" == "scripts/stop_dev.sh" ]] ||
    fail "HOOK_STOP"

[[ "${CBS_PLATFORM_HOOK_QUALIFY:-}" == "scripts/qualification/run_local_regression.sh" ]] ||
    fail "HOOK_QUALIFY"

echo "TEST_CORE_PLATFORM_BINDING_MANIFEST_HOOKS=PASS"

echo "TEST_CORE_PLATFORM_BINDING_MANIFEST_RESULT=PASS"
