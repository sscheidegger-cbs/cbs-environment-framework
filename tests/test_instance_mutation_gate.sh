#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBSERVER="$ROOT/cbs/instance/instance_observer.sh"
MANIFEST="$ROOT/instances/core-platform/instance.env"

fail() {
    echo "TEST_INSTANCE_MUTATION_GATE_RESULT=FAIL" >&2
    echo "TEST_INSTANCE_MUTATION_GATE_FAILURE=$1" >&2
    exit 1
}

source "$ROOT/cbs/instance/contract.sh"
source "$OBSERVER"

[[ "$(cbs_instance_mutation_decision READY)" == "REUSE" ]] ||
    fail "READY"

echo "TEST_INSTANCE_MUTATION_GATE_READY=PASS"

[[ "$(cbs_instance_mutation_decision STOPPED)" == "REUSE" ]] ||
    fail "STOPPED"

echo "TEST_INSTANCE_MUTATION_GATE_STOPPED=PASS"

[[ "$(cbs_instance_mutation_decision PARTIAL)" == "OBSERVE" ]] ||
    fail "PARTIAL"

echo "TEST_INSTANCE_MUTATION_GATE_PARTIAL=PASS"

[[ "$(cbs_instance_mutation_decision CONFLICT)" == "BLOCK" ]] ||
    fail "CONFLICT"

echo "TEST_INSTANCE_MUTATION_GATE_CONFLICT=PASS"

[[ "$(cbs_instance_mutation_decision INVALID)" == "BLOCK" ]] ||
    fail "INVALID"

echo "TEST_INSTANCE_MUTATION_GATE_INVALID=PASS"

[[ "$(cbs_instance_mutation_decision UNKNOWN)" == "OBSERVE" ]] ||
    fail "UNKNOWN"

echo "TEST_INSTANCE_MUTATION_GATE_UNKNOWN=PASS"

set +e
cbs_instance_mutation_decision "" >/dev/null 2>&1
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_INSTANCE_USAGE" ]] ||
    fail "EMPTY_RC"

echo "TEST_INSTANCE_MUTATION_GATE_USAGE=PASS"

set +e
cbs_instance_mutation_decision "NOT_A_STATE" >/dev/null 2>&1
RC=$?
set -e

[[ "$RC" -eq "$CBS_RC_INSTANCE_INVALID" ]] ||
    fail "INVALID_STATE_RC"

echo "TEST_INSTANCE_MUTATION_GATE_INVALID_STATE=PASS"

REAL_OUTPUT="$("$OBSERVER" "$MANIFEST")"

REAL_STATE="$(
    awk -F= '
        $1 == "CBS_INSTANCE_STATE" {
            print $2
        }
    ' <<<"$REAL_OUTPUT"
)"

REAL_ACTION="$(
    cbs_instance_mutation_decision "$REAL_STATE"
)"

[[ "$REAL_STATE" == "READY" ]] ||
    fail "REAL_STATE_$REAL_STATE"

[[ "$REAL_ACTION" == "REUSE" ]] ||
    fail "REAL_ACTION_$REAL_ACTION"

echo "TEST_INSTANCE_MUTATION_GATE_REAL_STATE=PASS"
echo "TEST_INSTANCE_MUTATION_GATE_REAL_ACTION=PASS"

echo "TEST_INSTANCE_MUTATION_GATE_RESULT=PASS"
