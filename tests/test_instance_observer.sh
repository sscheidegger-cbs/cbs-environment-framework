#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBSERVER="$ROOT/cbs/instance/instance_observer.sh"
MANIFEST="$ROOT/instances/core-platform/instance.env"

fail() {
    echo "TEST_INSTANCE_OBSERVER_RESULT=FAIL" >&2
    echo "TEST_INSTANCE_OBSERVER_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/instance/contract.sh"

OUTPUT="$("$OBSERVER" "$MANIFEST")"

grep -Fq 'CBS_INSTANCE_ID=core-platform-local' <<<"$OUTPUT" ||
    fail "INSTANCE_ID"

grep -Fq 'CBS_INSTANCE_VERSION=1' <<<"$OUTPUT" ||
    fail "INSTANCE_VERSION"

grep -Fq 'CBS_INSTANCE_STACK_ID=core-platform' <<<"$OUTPUT" ||
    fail "STACK_ID"

echo "TEST_INSTANCE_OBSERVER_IDENTITY=PASS"

for resource in \
    core-platform-redis \
    core-platform-opensearch \
    core-platform-postgres \
    core-platform-api \
    core-platform-kong \
    core-platform-keycloak \
    core-platform-network \
    b15-postgres18-target-data
do
    grep -Fq \
        "CBS_INSTANCE_RESOURCE_NAME=$resource" \
        <<<"$OUTPUT" ||
        fail "RESOURCE_$resource"
done

echo "TEST_INSTANCE_OBSERVER_RESOURCES=PASS"

RESOURCE_COUNT="$(
    grep -Fc 'CBS_INSTANCE_RESOURCE_NAME=' <<<"$OUTPUT"
)"

[[ "$RESOURCE_COUNT" -eq 8 ]] ||
    fail "RESOURCE_COUNT_$RESOURCE_COUNT"

echo "TEST_INSTANCE_OBSERVER_RESOURCE_COUNT=PASS"

EXPECTED_COUNT="$(
    awk -F= '
        $1 == "CBS_INSTANCE_EXPECTED_RESOURCE_COUNT" {
            print $2
        }
    ' <<<"$OUTPUT"
)"

AVAILABLE_COUNT="$(
    awk -F= '
        $1 == "CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT" {
            print $2
        }
    ' <<<"$OUTPUT"
)"

CONFLICT_COUNT="$(
    awk -F= '
        $1 == "CBS_INSTANCE_CONFLICT_RESOURCE_COUNT" {
            print $2
        }
    ' <<<"$OUTPUT"
)"

[[ "$EXPECTED_COUNT" =~ ^[0-9]+$ ]] ||
    fail "EXPECTED_COUNT"

[[ "$AVAILABLE_COUNT" =~ ^[0-9]+$ ]] ||
    fail "AVAILABLE_COUNT"

[[ "$CONFLICT_COUNT" =~ ^[0-9]+$ ]] ||
    fail "CONFLICT_COUNT"

[[ $((EXPECTED_COUNT + AVAILABLE_COUNT + CONFLICT_COUNT)) -eq 8 ]] ||
    fail "RESOURCE_AGGREGATION"

echo "TEST_INSTANCE_OBSERVER_AGGREGATION=PASS"

STATE="$(
    awk -F= '
        $1 == "CBS_INSTANCE_STATE" {
            print $2
        }
    ' <<<"$OUTPUT"
)"

ACTION="$(
    awk -F= '
        $1 == "CBS_INSTANCE_ACTION" {
            print $2
        }
    ' <<<"$OUTPUT"
)"

cbs_instance_state_is_valid "$STATE" ||
    fail "STATE_$STATE"

cbs_instance_action_is_valid "$ACTION" ||
    fail "ACTION_$ACTION"

[[ "$(cbs_instance_action_from_state "$STATE")" == "$ACTION" ]] ||
    fail "STATE_ACTION_MAPPING"

grep -Fq 'CBS_INSTANCE_OBSERVATION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "OBSERVATION_RESULT"

echo "TEST_INSTANCE_OBSERVER_CLASSIFICATION=PASS"

set +e
MISSING_OUTPUT="$("$OBSERVER" 2>&1)"
MISSING_RC=$?
set -e

[[ "$MISSING_RC" -eq "$CBS_RC_INSTANCE_USAGE" ]] ||
    fail "MISSING_MANIFEST_RC"

grep -Fq 'CBS_INSTANCE_ERROR=MANIFEST_REQUIRED' <<<"$MISSING_OUTPUT" ||
    fail "MISSING_MANIFEST_ERROR"

echo "TEST_INSTANCE_OBSERVER_USAGE=PASS"

set +e
INVALID_OUTPUT="$(
    "$OBSERVER" /tmp/cbs-instance-manifest-does-not-exist.env 2>&1
)"
INVALID_RC=$?
set -e

[[ "$INVALID_RC" -eq "$CBS_RC_INSTANCE_INVALID" ]] ||
    fail "INVALID_MANIFEST_RC"

grep -Fq 'CBS_INSTANCE_ERROR=MANIFEST_INVALID' <<<"$INVALID_OUTPUT" ||
    fail "INVALID_MANIFEST_ERROR"

echo "TEST_INSTANCE_OBSERVER_INVALID=PASS"

echo "TEST_INSTANCE_OBSERVER_RESULT=PASS"
