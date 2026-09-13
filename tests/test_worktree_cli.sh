#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"

fail() {
    echo "TEST_WORKTREE_CLI_RESULT=FAIL" >&2
    echo "TEST_WORKTREE_CLI_FAILURE=$1" >&2
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repository"
WT="$TMP/release"

mkdir -p "$REPO"

git -C "$REPO" init -q
git -C "$REPO" config user.name "CBS B17 Test"
git -C "$REPO" config user.email "b17-test@example.invalid"

printf '%s\n' "baseline" > "$REPO/file.txt"

git -C "$REPO" add file.txt
git -C "$REPO" commit -qm "baseline"
git -C "$REPO" branch release

OUTPUT="$("$CBS" worktree check "$REPO")"

grep -Fq "CBS_WORKTREE_REPOSITORY=$REPO" <<<"$OUTPUT" ||
    fail "CHECK_REPOSITORY"

grep -Fq 'CBS_WORKTREE_OBSERVATION_RESULT=PASS' <<<"$OUTPUT" ||
    fail "CHECK_RESULT"

echo "TEST_WORKTREE_CLI_CHECK=PASS"

OUTPUT="$(
    "$CBS" worktree ensure "$REPO" "$WT" release
)"

grep -Fq 'CBS_WORKTREE_ACTION=CREATE' <<<"$OUTPUT" ||
    fail "ENSURE_CREATE"

grep -Fq 'CBS_WORKTREE_STATE=READY' <<<"$OUTPUT" ||
    fail "ENSURE_READY"

[[ "$(git -C "$WT" branch --show-current)" == "release" ]] ||
    fail "ENSURE_BRANCH"

echo "TEST_WORKTREE_CLI_ENSURE_CREATE=PASS"

OUTPUT="$(
    "$CBS" worktree ensure "$REPO" "$WT" release
)"

grep -Fq 'CBS_WORKTREE_ACTION=REUSE' <<<"$OUTPUT" ||
    fail "ENSURE_REUSE"

echo "TEST_WORKTREE_CLI_ENSURE_REUSE=PASS"

set +e
OUTPUT="$("$CBS" worktree unknown 2>&1)"
RC=$?
set -e

[[ "$RC" -eq 2 ]] ||
    fail "UNKNOWN_RC"

grep -Fq 'CBS_ERROR=UNKNOWN_WORKTREE_COMMAND' <<<"$OUTPUT" ||
    fail "UNKNOWN_ERROR"

echo "TEST_WORKTREE_CLI_UNKNOWN_COMMAND=PASS"

HELP="$("$CBS" help)"

grep -Fq 'cbs worktree check <repository-path>' <<<"$HELP" ||
    fail "HELP_CHECK"

grep -Fq \
    'cbs worktree ensure <repository-path> <worktree-path> <branch>' \
    <<<"$HELP" ||
    fail "HELP_ENSURE"

echo "TEST_WORKTREE_CLI_HELP=PASS"
echo "TEST_WORKTREE_CLI_RESULT=PASS"
