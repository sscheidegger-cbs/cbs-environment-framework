#!/usr/bin/env bash

# D04b-C.1 safety regression: find / sed (and ls) portability with macOS BSD.
#
# No macOS host is available to this test. It enforces the portable subset in
# three ways, none of which replaces a native macOS run:
#   1. the strict wrappers reject every GNU-only usage (self-check);
#   2. the whole manager (create, verify, rollback, cleanup) runs behind the
#      strict wrappers, which must never reject a call;
#   3. a static scan forbids GNU-only options in the code and in the tests.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PREFIX="TEST_WORKTREE_ISOLATION_PORTABILITY"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

iso_fixture_init
iso_shim_init
iso_shim_install_strict

echo "${TEST_PREFIX}_FIXTURE=PASS"

strict() {
    # strict <tool> <args...> : prints the exit code of the strict wrapper.
    local tool="$1"
    shift

    set +e
    PATH="$ISO_SHIM_BIN:$PATH" "$ISO_SHIM_BIN/$tool" "$@" >/dev/null 2>&1
    STRICT_RC=$?
    set -e
}

expect_rejected() {
    strict "$@"
    [[ "$STRICT_RC" -eq 97 ]] || iso_fail "STRICT_ACCEPTED_GNU_USAGE_$1_$2"
}

expect_accepted() {
    strict "$@"
    [[ "$STRICT_RC" -eq 0 ]] || iso_fail "STRICT_REJECTED_PORTABLE_USAGE_$1_$2_RC_$STRICT_RC"
}

# ---------------------------------------------------------------- 1. the wrappers mean what they say

expect_accepted find "$TMP" -maxdepth 0 -user "$(id -u)"
expect_accepted find "$TMP" -maxdepth 0 -perm 700
expect_accepted find "$TMP" -maxdepth 0 -links 1
expect_accepted find "$TMP" -maxdepth 0 \( -perm -020 -o -perm -002 \)

expect_rejected find -maxdepth 0 "$TMP"
expect_rejected find "$TMP" -maxdepth 0 -printf '%p'
expect_rejected find "$TMP" -maxdepth 0 -perm /020
expect_rejected find "$TMP" -maxdepth 0 -perm +020
expect_rejected find "$TMP" -maxdepth 0 -xtype l
expect_rejected find "$TMP" -maxdepth 0 -regextype posix-extended
expect_rejected find "$TMP" -maxdepth 0 -newermt 2020-01-01
expect_rejected find "$TMP" -maxdepth 1 -delete

expect_accepted sed -n 's/^A=//p' /dev/null
expect_accepted sed -e 's#://[^/@]*@#://[REDACTED]@#' /dev/null

expect_rejected sed -i 's/a/b/' /dev/null
expect_rejected sed -r 's/a+/b/' /dev/null
expect_rejected sed -z 's/a/b/' /dev/null
expect_rejected sed 's/a\+/b/' /dev/null
expect_rejected sed 's/a\|b/c/' /dev/null
expect_rejected sed 's/a/b/I' /dev/null
expect_rejected sed 's/a/x\ny/' /dev/null
expect_rejected sed 's/\w/b/' /dev/null
expect_rejected sed --expression='s/a/b/' /dev/null

expect_accepted ls -di "$TMP"
expect_rejected ls --color=never "$TMP"
expect_rejected ls -h "$TMP"

: > "$CBS_SHIM_TOOLLOG"

echo "${TEST_PREFIX}_WRAPPERS=PASS"

# ---------------------------------------------------------------- 2. the manager behind the strict wrappers

iso_snapshot_source

iso_shim_reset
iso_run_shim create alpha "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
iso_expect_pass "STRICT_CREATE"

iso_run_shim verify alpha "$SOURCE" "$ISO_ROOT"
iso_expect_pass "STRICT_VERIFY"

# Rollback path (clean, owned, then source changed).
export CBS_SHIM_ADD_MODE="source-change"
iso_run_shim create rolled "$SOURCE" "$ISO_ORIGIN" "$C1" "$ISO_ROOT"
unset CBS_SHIM_ADD_MODE
iso_expect_failed "STRICT_ROLLBACK" "SOURCE_CHANGED" 68
[[ "$(iso_value ROLLBACK)" == "DONE" ]] || iso_fail "STRICT_ROLLBACK_FIELD_$(iso_value ROLLBACK)"
git -C "$SOURCE" branch -D shim-extra >/dev/null 2>&1
iso_snapshot_source

iso_run_shim cleanup alpha "$SOURCE" "$ISO_ROOT"
iso_expect_pass "STRICT_CLEANUP"
[[ ! -e "$ISO_ROOT/alpha" ]] || iso_fail "STRICT_CLEANUP_PATH_REMAINS"

# Refusals go through the same helpers.
iso_run_shim cleanup alpha "$SOURCE" "$ISO_ROOT"
iso_expect_blocked "STRICT_CLEANUP_TWICE" "ALREADY_CLEANED" 67

iso_assert_source_untouched "STRICT_SOURCE"

if grep -q '^REJECTED ' "$CBS_SHIM_TOOLLOG"; then
    iso_fail "STRICT_REJECTED_A_CALL_$(grep '^REJECTED ' "$CBS_SHIM_TOOLLOG" | head -n 1)"
fi

# The test is not vacuous: the helpers were really exercised.
grep -q '^find ' "$CBS_SHIM_TOOLLOG" || iso_fail "STRICT_FIND_NOT_EXERCISED"
grep -q '^sed ' "$CBS_SHIM_TOOLLOG" || iso_fail "STRICT_SED_NOT_EXERCISED"
grep -q '^ls ' "$CBS_SHIM_TOOLLOG" || iso_fail "STRICT_LS_NOT_EXERCISED"

echo "${TEST_PREFIX}_MANAGER_BEHIND_STRICT_TOOLS=PASS"

# ---------------------------------------------------------------- 3. static scan (code, fixtures, tests)

SCANNED="$ROOT/cbs/worktree/isolation_contract.sh $ROOT/cbs/worktree/isolation_manager.sh"

for file in "$ROOT"/tests/test_worktree_isolation_*.sh "$ROOT"/tests/fixtures/worktree_isolation/*.sh; do
    case "$file" in
        */test_worktree_isolation_portability.sh|*/test_worktree_isolation_contract.sh)
            # These two files hold the patterns themselves.
            continue
            ;;
    esac
    SCANNED="$SCANNED $file"
done

GNU_ONLY='find[^|]*[[:space:]](-printf|-regextype|-xtype|-readable|-writable|-executable|-newer[a-zA-Z]+|-delete|-fprint[a-z0-9]*|-quit|-samefile)|find[^|]*-perm[[:space:]]+[/+]|sed[[:space:]]+(-[a-zA-Z]*[irzsu][a-zA-Z]*|--[a-z])|sed[^|]*\\[+?|]|grep[[:space:]]+-[a-zA-Z]*P|xargs[[:space:]]+-r|sort[[:space:]]+-[a-zA-Z]*[VR]|head[[:space:]]+-n[[:space:]]+-|cp[[:space:]]+-[a-zA-Z]*a|ls[[:space:]]+--|du[[:space:]]+-b|readlink[[:space:]]+-f|realpath|stat[[:space:]]+-[cf]|date[[:space:]]+-d|mktemp[[:space:]]+--'

for file in $SCANNED; do
    [[ -f "$file" ]] || iso_fail "SCAN_FILE_MISSING_$file"

    if grep -En "$GNU_ONLY" "$file" |
        grep -Ev '^[0-9]+:[[:space:]]*#' |
        grep -Eq .
    then
        iso_fail "SCAN_GNU_ONLY_$file"
    fi
done

# find is always given an explicit path first (BSD requirement).
for file in $SCANNED; do
    if grep -En '(^|[^a-zA-Z_./-])find[[:space:]]+-' "$file" |
        grep -Ev '^[0-9]+:[[:space:]]*#' |
        grep -Eq .
    then
        iso_fail "SCAN_FIND_WITHOUT_PATH_$file"
    fi
done

echo "${TEST_PREFIX}_STATIC_SCAN=PASS"

echo "${TEST_PREFIX}_NATIVE_MACOS=NOT_RUN"
echo "${TEST_PREFIX}_RESULT=PASS"
