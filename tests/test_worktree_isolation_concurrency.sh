#!/usr/bin/env bash

# D04b-C.1 safety regression: mutual exclusion of create and cleanup.
#
# The exclusion is a directory lock (mkdir is atomic on Linux and macOS and
# needs no flock, which macOS does not provide). A held lock is never stolen.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_CONCURRENCY"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

iso_fixture_init
iso_shim_init

echo "${TEST_PREFIX}_FIXTURE=PASS"

PROOF_DIR="$ISO_ROOT/.cbs-isolation"
LOCK_DIR="$ISO_ROOT/.cbs-isolation.lock"

iso_run create resident "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_pass "SETUP_RESIDENT"
iso_snapshot_source

RESIDENT_BEFORE="$(iso_tree_fingerprint "$ISO_ROOT/resident")"

wait_for_file() {
    local file="$1"
    local waited=0

    while [[ ! -e "$file" ]]; do
        sleep 0.1
        waited=$((waited + 1))
        [[ "$waited" -le 300 ]] || iso_fail "TIMEOUT_WAITING_$(basename "$file")"
    done
}

# ---------------------------------------------------------------- a held lock blocks create and cleanup

iso_shim_reset
export CBS_SHIM_ADD_MODE="hold"

(
    set +e
    PATH="$ISO_SHIM_BIN:$PATH" "$ISO_MANAGER" create holder "$SOURCE" "$ISO_ORIGIN" "$C2" "$ISO_ROOT" \
        > "$TMP/holder.out" 2>&1
    echo "$?" > "$TMP/holder.rc"
) &
HOLDER_PID=$!

unset CBS_SHIM_ADD_MODE

wait_for_file "$CBS_SHIM_SYNC/reached"

# The holder is blocked inside "git worktree add", lock held.
[[ -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]] || iso_fail "LOCK_NOT_HELD"
iso_has_mode "$LOCK_DIR" 700 || iso_fail "LOCK_MODE"

iso_run create other "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "CREATE_WHILE_LOCKED" "LOCK_BUSY" 68
[[ ! -e "$ISO_ROOT/other" ]] || iso_fail "CREATE_WHILE_LOCKED_CREATED"
[[ ! -e "$PROOF_DIR/other.proof" ]] || iso_fail "CREATE_WHILE_LOCKED_PROOF"

iso_run create holder "$SOURCE" "$ISO_ORIGIN" "$C2" "$ISO_ROOT"
iso_expect_blocked "SAME_ID_WHILE_LOCKED" "LOCK_BUSY" 68

iso_run cleanup resident "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "CLEANUP_WHILE_LOCKED" "LOCK_BUSY" 68
[[ -d "$ISO_ROOT/resident" ]] || iso_fail "CLEANUP_WHILE_LOCKED_REMOVED"
[[ ! -e "$PROOF_DIR/resident.cleaned" ]] || iso_fail "CLEANUP_WHILE_LOCKED_RECORDED"
[[ "$(iso_tree_fingerprint "$ISO_ROOT/resident")" == "$RESIDENT_BEFORE" ]] || iso_fail "CLEANUP_WHILE_LOCKED_CHANGED"

# The refused operations did not release or alter the holder's lock.
[[ -d "$LOCK_DIR" ]] || iso_fail "LOCK_RELEASED_BY_LOSER"

: > "$CBS_SHIM_SYNC/release"
wait "$HOLDER_PID" || true

[[ "$(cat "$TMP/holder.rc")" == "0" ]] || iso_fail "HOLDER_RC_$(cat "$TMP/holder.rc")"
grep -Fxq "CBS_FLUTTER_ISOLATION_RESULT=PASS" "$TMP/holder.out" || iso_fail "HOLDER_RESULT"
[[ "$(git -C "$ISO_ROOT/holder" rev-parse HEAD)" == "$C2" ]] || iso_fail "HOLDER_HEAD"
[[ ! -e "$LOCK_DIR" ]] || iso_fail "LOCK_REMAINS_AFTER_HOLDER"

iso_shim_reset
iso_pass "LOCK_EXCLUDES_CREATE_AND_CLEANUP"

# ---------------------------------------------------------------- the lock is free again

iso_run create other "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_pass "CREATE_AFTER_RELEASE"
iso_run cleanup other "$SOURCE" "$ISO_ROOT"
iso_expect_pass "CLEANUP_AFTER_RELEASE"
[[ ! -e "$LOCK_DIR" ]] || iso_fail "LOCK_REMAINS_AFTER_SEQUENCE"

iso_pass "LOCK_RELEASED_AFTER_USE"

# ---------------------------------------------------------------- lock hygiene

# A symlink in place of the lock is refused and never followed.
mkdir -p "$TMP/lock-target"
ln -s "$TMP/lock-target" "$LOCK_DIR"
iso_run create via-link "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "LOCK_SYMLINK" "LOCK_INVALID" 61
[[ -z "$(ls -A "$TMP/lock-target")" ]] || iso_fail "LOCK_SYMLINK_TARGET_WRITTEN"
[[ -L "$LOCK_DIR" ]] || iso_fail "LOCK_SYMLINK_REMOVED"
rm "$LOCK_DIR"

# A regular file in place of the lock is refused and kept.
printf '%s\n' "not-a-lock" > "$LOCK_DIR"
iso_run create via-file "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_blocked "LOCK_FILE" "LOCK_INVALID" 61
[[ "$(cat "$LOCK_DIR")" == "not-a-lock" ]] || iso_fail "LOCK_FILE_CHANGED"
rm "$LOCK_DIR"

# A pre-existing lock directory (stale or foreign) blocks and is kept intact.
mkdir -m 700 "$LOCK_DIR"
printf '%s\n' "pid=1 token=stale" > "$LOCK_DIR/owner"
iso_run cleanup resident "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "LOCK_STALE" "LOCK_BUSY" 68
[[ "$(cat "$LOCK_DIR/owner")" == "pid=1 token=stale" ]] || iso_fail "LOCK_STALE_CHANGED"
[[ -d "$ISO_ROOT/resident" ]] || iso_fail "LOCK_STALE_REMOVED_RESOURCE"
rm -f "$LOCK_DIR/owner"
rmdir "$LOCK_DIR"

# Refusals before the root is validated never create a lock there.
mkdir -p "$TMP/unauthorized-root"
iso_run create id1 "$SOURCE" "$ISO_ORIGIN" "$C1" "$TMP/unauthorized-root"
iso_expect_blocked "LOCK_UNAUTHORIZED_ROOT" "ROOT_NOT_AUTHORIZED" 61
[[ -z "$(ls -A "$TMP/unauthorized-root")" ]] || iso_fail "LOCK_IN_UNAUTHORIZED_ROOT"

iso_pass "LOCK_HYGIENE"

# ---------------------------------------------------------------- same identifier, parallel creations

iso_snapshot_source
COUNT_BEFORE="$(iso_worktree_count)"

mkdir -p "$TMP/storm"
STORM_PIDS=""
i=1
while [[ "$i" -le 6 ]]; do
    (
        set +e
        "$ISO_MANAGER" create storm "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT" > "$TMP/storm/$i.out" 2>&1
        echo "$?" > "$TMP/storm/$i.rc"
    ) &
    STORM_PIDS="$STORM_PIDS $!"
    i=$((i + 1))
done

for pid in $STORM_PIDS; do
    wait "$pid" || true
done

PASSES=0
i=1
while [[ "$i" -le 6 ]]; do
    result="$(sed -n 's/^CBS_FLUTTER_ISOLATION_RESULT=//p' "$TMP/storm/$i.out" | head -n 1)"
    reason="$(sed -n 's/^CBS_FLUTTER_ISOLATION_REASON=//p' "$TMP/storm/$i.out" | head -n 1)"

    case "$result:$reason" in
        PASS:NONE)
            PASSES=$((PASSES + 1))
            ;;
        BLOCKED:LOCK_BUSY|BLOCKED:ID_ALREADY_USED)
            ;;
        *)
            iso_fail "STORM_UNEXPECTED_${i}_${result}_${reason}"
            ;;
    esac

    i=$((i + 1))
done

[[ "$PASSES" -eq 1 ]] || iso_fail "STORM_PASS_COUNT_$PASSES"
[[ "$(iso_worktree_count)" == "$((COUNT_BEFORE + 1))" ]] || iso_fail "STORM_WORKTREE_COUNT"
iso_is_registered "$ISO_ROOT/storm" || iso_fail "STORM_UNREGISTERED"
grep -Fxq "CBS_ISOLATION_STATE=READY" "$PROOF_DIR/storm.proof" || iso_fail "STORM_PROOF_STATE"
[[ ! -e "$LOCK_DIR" ]] || iso_fail "STORM_LOCK_REMAINS"

iso_run verify storm "$SOURCE" "$ISO_ROOT"
iso_expect_pass "STORM_VERIFY"

iso_assert_source_untouched "STORM_SOURCE"

iso_pass "PARALLEL_SAME_ID"

# ---------------------------------------------------------------- cleanups in parallel: exactly one effect

iso_run create twice "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_pass "SETUP_TWICE"
iso_snapshot_source

CLEAN_PIDS=""
i=1
while [[ "$i" -le 6 ]]; do
    (
        set +e
        "$ISO_MANAGER" cleanup twice "$SOURCE" "$ISO_ROOT" > "$TMP/storm/c$i.out" 2>&1
        echo "$?" > "$TMP/storm/c$i.rc"
    ) &
    CLEAN_PIDS="$CLEAN_PIDS $!"
    i=$((i + 1))
done

for pid in $CLEAN_PIDS; do
    wait "$pid" || true
done

PASSES=0
i=1
while [[ "$i" -le 6 ]]; do
    result="$(sed -n 's/^CBS_FLUTTER_ISOLATION_RESULT=//p' "$TMP/storm/c$i.out" | head -n 1)"
    reason="$(sed -n 's/^CBS_FLUTTER_ISOLATION_REASON=//p' "$TMP/storm/c$i.out" | head -n 1)"

    case "$result:$reason" in
        PASS:NONE)
            PASSES=$((PASSES + 1))
            ;;
        BLOCKED:LOCK_BUSY|BLOCKED:ALREADY_CLEANED)
            ;;
        *)
            iso_fail "CLEAN_STORM_UNEXPECTED_${i}_${result}_${reason}"
            ;;
    esac

    i=$((i + 1))
done

[[ "$PASSES" -eq 1 ]] || iso_fail "CLEAN_STORM_PASS_COUNT_$PASSES"
[[ ! -e "$ISO_ROOT/twice" ]] || iso_fail "CLEAN_STORM_PATH_REMAINS"
[[ -f "$PROOF_DIR/twice.cleaned" ]] || iso_fail "CLEAN_STORM_RECORD"
[[ ! -e "$LOCK_DIR" ]] || iso_fail "CLEAN_STORM_LOCK_REMAINS"

# Everything else is untouched.
[[ "$(iso_tree_fingerprint "$ISO_ROOT/resident")" == "$RESIDENT_BEFORE" ]] || iso_fail "CLEAN_STORM_RESIDENT_CHANGED"
iso_is_registered "$ISO_ROOT/storm" || iso_fail "CLEAN_STORM_OTHER_UNREGISTERED"
iso_assert_source_untouched "CLEAN_STORM_SOURCE"

iso_pass "PARALLEL_CLEANUP"

echo "${TEST_PREFIX}_RESULT=PASS"
