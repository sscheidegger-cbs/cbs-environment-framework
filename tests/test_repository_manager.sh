#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MANAGER="$ROOT/cbs/workspace/repository_manager.sh"

fail() {
    echo "TEST_REPOSITORY_MANAGER_RESULT=FAIL" >&2
    echo "TEST_REPOSITORY_MANAGER_FAILURE=$1" >&2
    exit 1
}

TMP="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP"
}

trap cleanup EXIT

SOURCE="$TMP/source.git"
SEED="$TMP/seed"
TARGET="$TMP/target"

git init --bare -q "$SOURCE"

git init -q "$SEED"

git -C "$SEED" config user.name "CBS Test"
git -C "$SEED" config user.email "cbs-test@example.invalid"

printf '%s\n' "CBS repository manager test" \
    > "$SEED/README.md"

git -C "$SEED" add README.md
git -C "$SEED" commit -q -m "initial test commit"

git -C "$SEED" remote add origin "$SOURCE"
git -C "$SEED" push -q origin HEAD:main

git --git-dir="$SOURCE" symbolic-ref HEAD refs/heads/main

EXPECTED_ORIGIN="$SOURCE"

OUTPUT="$(
    "$MANAGER" \
        "$TARGET" \
        "$EXPECTED_ORIGIN" \
        2>&1
)"

grep -Fq \
    'CBS_REPOSITORY_STATE_BEFORE=MISSING' \
    <<<"$OUTPUT" ||
    fail "CLONE_STATE_BEFORE"

grep -Fq \
    'CBS_REPOSITORY_ACTION=CLONE' \
    <<<"$OUTPUT" ||
    fail "CLONE_ACTION"

grep -Fq \
    'CBS_REPOSITORY_STATE_AFTER=READY' \
    <<<"$OUTPUT" ||
    fail "CLONE_STATE_AFTER"

grep -Fq \
    'CBS_REPOSITORY_STATE=READY' \
    <<<"$OUTPUT" ||
    fail "CLONE_RESULT"

[[ -d "$TARGET/.git" ]] ||
    fail "CLONE_GIT_DIRECTORY"

[[ "$(
    git -C "$TARGET" remote get-url origin
)" == "$EXPECTED_ORIGIN" ]] ||
    fail "CLONE_ORIGIN"

echo "TEST_REPOSITORY_MANAGER_CLONE=PASS"

HEAD_BEFORE="$(
    git -C "$TARGET" rev-parse HEAD
)"

OUTPUT="$(
    "$MANAGER" \
        "$TARGET" \
        "$EXPECTED_ORIGIN" \
        2>&1
)"

HEAD_AFTER="$(
    git -C "$TARGET" rev-parse HEAD
)"

grep -Fq \
    'CBS_REPOSITORY_STATE_BEFORE=READY' \
    <<<"$OUTPUT" ||
    fail "REUSE_STATE"

grep -Fq \
    'CBS_REPOSITORY_ACTION=REUSE' \
    <<<"$OUTPUT" ||
    fail "REUSE_ACTION"

[[ "$HEAD_BEFORE" == "$HEAD_AFTER" ]] ||
    fail "REUSE_MUTATED_HEAD"

echo "TEST_REPOSITORY_MANAGER_REUSE=PASS"

NOT_GIT="$TMP/not-git"
mkdir "$NOT_GIT"

printf '%s\n' "preserve me" > "$NOT_GIT/content.txt"

set +e
OUTPUT="$(
    "$MANAGER" \
        "$NOT_GIT" \
        "$EXPECTED_ORIGIN" \
        2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 51 ]] ||
    fail "NOT_GIT_RC"

grep -Fq \
    'CBS_REPOSITORY_ACTION=BLOCK' \
    <<<"$OUTPUT" ||
    fail "NOT_GIT_ACTION"

grep -Fq \
    'CBS_REPOSITORY_ERROR=TARGET_NOT_GIT' \
    <<<"$OUTPUT" ||
    fail "NOT_GIT_ERROR"

[[ -f "$NOT_GIT/content.txt" ]] ||
    fail "NOT_GIT_CONTENT_MUTATED"

echo "TEST_REPOSITORY_MANAGER_NOT_GIT_BLOCK=PASS"

MISMATCH="$TMP/mismatch"
mkdir "$MISMATCH"

git -C "$MISMATCH" init -q
git -C "$MISMATCH" remote add origin \
    "$TMP/other.git"

set +e
OUTPUT="$(
    "$MANAGER" \
        "$MISMATCH" \
        "$EXPECTED_ORIGIN" \
        2>&1
)"
RC=$?
set -e

[[ "$RC" -eq 52 ]] ||
    fail "REMOTE_MISMATCH_RC"

grep -Fq \
    'CBS_REPOSITORY_ACTION=BLOCK' \
    <<<"$OUTPUT" ||
    fail "REMOTE_MISMATCH_ACTION"

grep -Fq \
    'CBS_REPOSITORY_ERROR=REMOTE_MISMATCH' \
    <<<"$OUTPUT" ||
    fail "REMOTE_MISMATCH_ERROR"

[[ "$(
    git -C "$MISMATCH" remote get-url origin
)" == "$TMP/other.git" ]] ||
    fail "REMOTE_WAS_REWRITTEN"

echo "TEST_REPOSITORY_MANAGER_REMOTE_MISMATCH_BLOCK=PASS"

set +e
OUTPUT="$("$MANAGER" 2>&1)"
RC=$?
set -e

[[ "$RC" -eq 64 ]] ||
    fail "USAGE_RC"

grep -Fq \
    'CBS_REPOSITORY_ERROR=REPOSITORY_PATH_REQUIRED' \
    <<<"$OUTPUT" ||
    fail "USAGE_ERROR"

echo "TEST_REPOSITORY_MANAGER_USAGE=PASS"
echo "TEST_REPOSITORY_MANAGER_RESULT=PASS"
