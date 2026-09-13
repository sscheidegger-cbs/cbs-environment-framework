#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/worktree/worktree_manager.sh"

fail() {
    echo "TEST_WORKTREE_COEXISTENCE_RESULT=FAIL" >&2
    echo "TEST_WORKTREE_COEXISTENCE_FAILURE=$1" >&2
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repository"

WT_DEVELOP="$TMP/worktrees/develop"
WT_RELEASE="$TMP/worktrees/release"
WT_HOTFIX="$TMP/worktrees/hotfix"

mkdir -p "$REPO"
mkdir -p "$TMP/worktrees"

git -C "$REPO" init -q
git -C "$REPO" config user.name "CBS B17 Test"
git -C "$REPO" config user.email "b17-test@example.invalid"

printf '%s\n' "baseline" > "$REPO/file.txt"

git -C "$REPO" add file.txt
git -C "$REPO" commit -qm "baseline"

git -C "$REPO" branch develop
git -C "$REPO" branch release
git -C "$REPO" branch hotfix

echo "TEST_WORKTREE_COEXISTENCE_FIXTURE=PASS"

"$MANAGER" "$REPO" "$WT_DEVELOP" develop >/dev/null
"$MANAGER" "$REPO" "$WT_RELEASE" release >/dev/null
"$MANAGER" "$REPO" "$WT_HOTFIX" hotfix >/dev/null

echo "TEST_WORKTREE_COEXISTENCE_CREATE=PASS"

[[ -d "$WT_DEVELOP" ]] ||
    fail "DEVELOP_PATH"

[[ -d "$WT_RELEASE" ]] ||
    fail "RELEASE_PATH"

[[ -d "$WT_HOTFIX" ]] ||
    fail "HOTFIX_PATH"

[[ "$(git -C "$WT_DEVELOP" branch --show-current)" == "develop" ]] ||
    fail "DEVELOP_BRANCH"

[[ "$(git -C "$WT_RELEASE" branch --show-current)" == "release" ]] ||
    fail "RELEASE_BRANCH"

[[ "$(git -C "$WT_HOTFIX" branch --show-current)" == "hotfix" ]] ||
    fail "HOTFIX_BRANCH"

echo "TEST_WORKTREE_COEXISTENCE_BRANCHES=PASS"

PORCELAIN="$(
    git -C "$REPO" worktree list --porcelain
)"

grep -Fq "worktree $WT_DEVELOP" <<<"$PORCELAIN" ||
    fail "DEVELOP_NOT_LISTED"

grep -Fq "branch refs/heads/develop" <<<"$PORCELAIN" ||
    fail "DEVELOP_REF_NOT_LISTED"

grep -Fq "worktree $WT_RELEASE" <<<"$PORCELAIN" ||
    fail "RELEASE_NOT_LISTED"

grep -Fq "branch refs/heads/release" <<<"$PORCELAIN" ||
    fail "RELEASE_REF_NOT_LISTED"

grep -Fq "worktree $WT_HOTFIX" <<<"$PORCELAIN" ||
    fail "HOTFIX_NOT_LISTED"

grep -Fq "branch refs/heads/hotfix" <<<"$PORCELAIN" ||
    fail "HOTFIX_REF_NOT_LISTED"

echo "TEST_WORKTREE_COEXISTENCE_LIST=PASS"

DEVELOP_HEAD="$(git -C "$WT_DEVELOP" rev-parse HEAD)"
RELEASE_HEAD="$(git -C "$WT_RELEASE" rev-parse HEAD)"
HOTFIX_HEAD="$(git -C "$WT_HOTFIX" rev-parse HEAD)"

[[ -n "$DEVELOP_HEAD" ]]
[[ -n "$RELEASE_HEAD" ]]
[[ -n "$HOTFIX_HEAD" ]]

echo "TEST_WORKTREE_COEXISTENCE_HEADS=PASS"

"$MANAGER" "$REPO" "$WT_DEVELOP" develop >/dev/null
"$MANAGER" "$REPO" "$WT_RELEASE" release >/dev/null
"$MANAGER" "$REPO" "$WT_HOTFIX" hotfix >/dev/null

[[ "$(git -C "$WT_DEVELOP" branch --show-current)" == "develop" ]]
[[ "$(git -C "$WT_RELEASE" branch --show-current)" == "release" ]]
[[ "$(git -C "$WT_HOTFIX" branch --show-current)" == "hotfix" ]]

echo "TEST_WORKTREE_COEXISTENCE_REUSE=PASS"

COUNT="$(
    git -C "$REPO" worktree list --porcelain |
    grep -c '^worktree '
)"

echo "TEST_WORKTREE_COEXISTENCE_COUNT=$COUNT"

# Primary repository + develop + release + hotfix.
[[ "$COUNT" -eq 4 ]] ||
    fail "WORKTREE_COUNT"

echo "TEST_WORKTREE_COEXISTENCE_COUNT=PASS"

echo "TEST_WORKTREE_COEXISTENCE_RESULT=PASS"
