#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/worktree/worktree_manager.sh"

source "$ROOT/cbs/worktree/contract.sh"

fail() {
    echo "TEST_WORKTREE_MANAGER_RESULT=FAIL" >&2
    echo "TEST_WORKTREE_MANAGER_FAILURE=$1" >&2
    exit 1
}

TMP="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP"
}

trap cleanup EXIT

REPO="$TMP/repository"
WT_RELEASE="$TMP/release"
WT_HOTFIX="$TMP/hotfix"
CONFLICT_PATH="$TMP/conflict"

mkdir -p "$REPO"

git -C "$REPO" init -q
git -C "$REPO" config user.name "CBS B17 Test"
git -C "$REPO" config user.email "b17-test@example.invalid"

printf '%s\n' "baseline" > "$REPO/file.txt"

git -C "$REPO" add file.txt
git -C "$REPO" commit -qm "baseline"

git -C "$REPO" branch release
git -C "$REPO" branch hotfix

echo "TEST_WORKTREE_MANAGER_FIXTURE=PASS"

OUTPUT="$(
    "$MANAGER" \
        "$REPO" \
        "$WT_RELEASE" \
        release
)"

grep -Fq 'CBS_WORKTREE_STATE_BEFORE=MISSING' <<<"$OUTPUT" ||
    fail "CREATE_STATE_BEFORE"

grep -Fq 'CBS_WORKTREE_ACTION=CREATE' <<<"$OUTPUT" ||
    fail "CREATE_ACTION"

grep -Fq 'CBS_WORKTREE_STATE=READY' <<<"$OUTPUT" ||
    fail "CREATE_STATE"

[[ -d "$WT_RELEASE" ]] ||
    fail "CREATE_PATH"

[[ "$(git -C "$WT_RELEASE" branch --show-current)" == "release" ]] ||
    fail "CREATE_BRANCH"

echo "TEST_WORKTREE_MANAGER_CREATE=PASS"

OUTPUT="$(
    "$MANAGER" \
        "$REPO" \
        "$WT_RELEASE" \
        release
)"

grep -Fq 'CBS_WORKTREE_STATE_BEFORE=READY' <<<"$OUTPUT" ||
    fail "REUSE_STATE_BEFORE"

grep -Fq 'CBS_WORKTREE_ACTION=REUSE' <<<"$OUTPUT" ||
    fail "REUSE_ACTION"

grep -Fq 'CBS_WORKTREE_STATE=READY' <<<"$OUTPUT" ||
    fail "REUSE_STATE"

echo "TEST_WORKTREE_MANAGER_REUSE=PASS"

set +e

OUTPUT="$(
    "$MANAGER" \
        "$REPO" \
        "$WT_HOTFIX" \
        release \
        2>&1
)"

RC=$?

set -e

[[ "$RC" -eq "$CBS_RC_WORKTREE_BRANCH_CONFLICT" ]] ||
    fail "BRANCH_CONFLICT_RC"

grep -Fq 'CBS_WORKTREE_ACTION=BLOCK' <<<"$OUTPUT" ||
    fail "BRANCH_CONFLICT_ACTION"

grep -Fq 'CBS_WORKTREE_STATE=BRANCH_CONFLICT' <<<"$OUTPUT" ||
    fail "BRANCH_CONFLICT_STATE"

echo "TEST_WORKTREE_MANAGER_BRANCH_CONFLICT=PASS"

mkdir -p "$CONFLICT_PATH"

set +e

OUTPUT="$(
    "$MANAGER" \
        "$REPO" \
        "$CONFLICT_PATH" \
        hotfix \
        2>&1
)"

RC=$?

set -e

[[ "$RC" -eq "$CBS_RC_WORKTREE_PATH_CONFLICT" ]] ||
    fail "PATH_CONFLICT_RC"

grep -Fq 'CBS_WORKTREE_ACTION=BLOCK' <<<"$OUTPUT" ||
    fail "PATH_CONFLICT_ACTION"

grep -Fq 'CBS_WORKTREE_STATE=PATH_CONFLICT' <<<"$OUTPUT" ||
    fail "PATH_CONFLICT_STATE"

echo "TEST_WORKTREE_MANAGER_PATH_CONFLICT=PASS"

MISSING_PARENT="$TMP/missing-parent/worktree"

set +e

OUTPUT="$(
    "$MANAGER" \
        "$REPO" \
        "$MISSING_PARENT" \
        hotfix \
        2>&1
)"

RC=$?

set -e

[[ "$RC" -eq "$CBS_RC_WORKTREE_PATH_CONFLICT" ]] ||
    fail "MISSING_PARENT_RC"

grep -Fq 'CBS_WORKTREE_ERROR=PARENT_DIRECTORY_MISSING' <<<"$OUTPUT" ||
    fail "MISSING_PARENT_ERROR"

[[ ! -e "$TMP/missing-parent" ]] ||
    fail "MISSING_PARENT_CREATED"

echo "TEST_WORKTREE_MANAGER_NO_RECURSIVE_PARENT_CREATE=PASS"

set +e

OUTPUT="$(
    "$MANAGER" \
        "$REPO" \
        "$WT_HOTFIX" \
        does-not-exist \
        2>&1
)"

RC=$?

set -e

[[ "$RC" -eq "$CBS_RC_WORKTREE_BRANCH_CONFLICT" ]] ||
    fail "MISSING_BRANCH_RC"

grep -Fq 'CBS_WORKTREE_ERROR=BRANCH_NOT_FOUND' <<<"$OUTPUT" ||
    fail "MISSING_BRANCH_ERROR"

[[ ! -e "$WT_HOTFIX" ]] ||
    fail "MISSING_BRANCH_CREATED_PATH"

echo "TEST_WORKTREE_MANAGER_MISSING_BRANCH=PASS"

echo "TEST_WORKTREE_MANAGER_RESULT=PASS"
