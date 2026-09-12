#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT/cbs/workspace/repository_contract.sh"

fail() {
    echo "TEST_REPOSITORY_MUTATION_GATE_RESULT=FAIL" >&2
    echo "TEST_REPOSITORY_MUTATION_GATE_FAILURE=$1" >&2
    exit 1
}

TMP="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP"
}

trap cleanup EXIT

EXPECTED_ORIGIN="git@example.invalid:cbs/project.git"

MISSING_PATH="$TMP/missing"

STATE="$(
    cbs_repository_state \
        "$MISSING_PATH" \
        "$EXPECTED_ORIGIN"
)"

[[ "$STATE" == "$CBS_REPOSITORY_MISSING" ]] ||
    fail "MISSING_STATE"

echo "TEST_REPOSITORY_MUTATION_GATE_MISSING=PASS"

NOT_GIT_PATH="$TMP/not-git"
mkdir "$NOT_GIT_PATH"

STATE="$(
    cbs_repository_state \
        "$NOT_GIT_PATH" \
        "$EXPECTED_ORIGIN"
)"

[[ "$STATE" == "$CBS_REPOSITORY_NOT_GIT" ]] ||
    fail "NOT_GIT_STATE"

echo "TEST_REPOSITORY_MUTATION_GATE_NOT_GIT=PASS"

MISMATCH_PATH="$TMP/mismatch"
mkdir "$MISMATCH_PATH"

git -C "$MISMATCH_PATH" init -q
git -C "$MISMATCH_PATH" remote add origin \
    "git@example.invalid:cbs/other.git"

STATE="$(
    cbs_repository_state \
        "$MISMATCH_PATH" \
        "$EXPECTED_ORIGIN"
)"

[[ "$STATE" == "$CBS_REPOSITORY_REMOTE_MISMATCH" ]] ||
    fail "REMOTE_MISMATCH_STATE"

echo "TEST_REPOSITORY_MUTATION_GATE_REMOTE_MISMATCH=PASS"

READY_PATH="$TMP/ready"
mkdir "$READY_PATH"

git -C "$READY_PATH" init -q
git -C "$READY_PATH" remote add origin "$EXPECTED_ORIGIN"

STATE="$(
    cbs_repository_state \
        "$READY_PATH" \
        "$EXPECTED_ORIGIN"
)"

[[ "$STATE" == "$CBS_REPOSITORY_READY" ]] ||
    fail "READY_STATE"

echo "TEST_REPOSITORY_MUTATION_GATE_READY=PASS"

echo "TEST_REPOSITORY_MUTATION_GATE_RESULT=PASS"
