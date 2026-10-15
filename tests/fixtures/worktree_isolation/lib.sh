#!/usr/bin/env bash

# Shared hermetic fixture for D04b-C.1 isolation tests.
# Requires the caller to define: ROOT, TEST_PREFIX.
# Bash 3.2 compatible: no arrays, no associative arrays, no mapfile.

ISO_MANAGER="$ROOT/cbs/worktree/isolation_manager.sh"
ISO_ORIGIN="https://example.invalid/cbs/isolation-fixture.git"

iso_fail() {
    echo "${TEST_PREFIX}_RESULT=FAIL" >&2
    echo "${TEST_PREFIX}_FAILURE=$1" >&2
    exit 1
}

iso_pass() {
    echo "${TEST_PREFIX}_$1=PASS"
}

iso_fixture_init() {
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/cbs-isolation-test.XXXXXX")"
    # Canonical form: macOS mktemp returns /var/... which is a symlink.
    TMP="$(cd -P "$TMP" && pwd -P)"

    trap 'iso_fixture_cleanup' EXIT

    # Hermetic Git environment: no user, system or inherited configuration.
    mkdir -p "$TMP/home"
    export HOME="$TMP/home"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_TERMINAL_PROMPT=0
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

    SOURCE="$TMP/source"
    ISO_ROOT="$TMP/isolation-root"

    mkdir -p "$SOURCE"
    git -C "$SOURCE" init -q
    git -C "$SOURCE" config user.name "CBS D04b-C Test"
    git -C "$SOURCE" config user.email "d04b-c-test@example.invalid"
    git -C "$SOURCE" remote add origin "$ISO_ORIGIN"

    printf '%s\n' "first" > "$SOURCE/file.txt"
    git -C "$SOURCE" add file.txt
    git -C "$SOURCE" commit -qm "first"
    C1="$(git -C "$SOURCE" rev-parse HEAD)"

    printf '%s\n' "second" > "$SOURCE/file.txt"
    printf '%s\n' "extra" > "$SOURCE/extra.txt"
    git -C "$SOURCE" add file.txt extra.txt
    git -C "$SOURCE" commit -qm "second"
    C2="$(git -C "$SOURCE" rev-parse HEAD)"

    # Development state that must be preserved: untracked file, local branch.
    mkdir -p "$SOURCE/.local"
    printf '%s\n' "local-dev-state" > "$SOURCE/.local/note.txt"
    git -C "$SOURCE" branch dev-branch

    iso_make_root "$ISO_ROOT"
}

iso_fixture_cleanup() {
    if [[ -n "${TMP:-}" && -d "$TMP" && "$TMP" == */* && "$TMP" != "/" ]]; then
        chmod -R u+rwx "$TMP" 2>/dev/null || true
        rm -rf "$TMP"
    fi
}

iso_make_root() {
    mkdir -p "$1"
    printf '%s\n' "CBS_ISOLATION_ROOT_V1" > "$1/.cbs-isolation-root"
}

# iso_run <args...> : sets ISO_OUT and ISO_RC, never aborts the test.
iso_run() {
    set +e
    ISO_OUT="$("$ISO_MANAGER" "$@" 2>&1)"
    ISO_RC=$?
    set -e
}

iso_value() {
    printf '%s\n' "$ISO_OUT" |
        sed -n "s/^CBS_FLUTTER_ISOLATION_$1=//p" |
        head -n 1
}

iso_expect_pass() {
    local label="$1"

    [[ "$ISO_RC" -eq 0 ]] ||
        iso_fail "${label}_RC_${ISO_RC}_$(iso_value REASON)"
    [[ "$(iso_value RESULT)" == "PASS" ]] ||
        iso_fail "${label}_RESULT"
}

# iso_expect_blocked <label> <reason> <rc>
iso_expect_blocked() {
    local label="$1"
    local reason="$2"
    local rc="$3"

    [[ "$(iso_value RESULT)" == "BLOCKED" ]] ||
        iso_fail "${label}_RESULT_$(iso_value RESULT)_$(iso_value REASON)"
    [[ "$(iso_value REASON)" == "$reason" ]] ||
        iso_fail "${label}_REASON_$(iso_value REASON)"
    [[ "$ISO_RC" -eq "$rc" ]] ||
        iso_fail "${label}_RC_${ISO_RC}"
    [[ "$(iso_value RC)" == "$rc" ]] ||
        iso_fail "${label}_RC_FIELD_$(iso_value RC)"
}

# Complete observable state of the source repository (development state).
iso_source_state() {
    printf 'HEAD=%s\n' "$(git -C "$SOURCE" rev-parse HEAD)"
    printf 'BRANCH=%s\n' "$(git -C "$SOURCE" branch --show-current)"
    git -C "$SOURCE" for-each-ref
    git -C "$SOURCE" status --porcelain
    printf 'NOTE=%s\n' "$(cat "$SOURCE/.local/note.txt")"
    printf 'FILE=%s\n' "$(cat "$SOURCE/file.txt")"
}

iso_assert_source_untouched() {
    [[ "$(iso_source_state)" == "$ISO_SOURCE_STATE_REF" ]] ||
        iso_fail "$1"
    [[ -f "$SOURCE/.local/note.txt" ]] ||
        iso_fail "$1_UNTRACKED_LOST"
}

iso_snapshot_source() {
    ISO_SOURCE_STATE_REF="$(iso_source_state)"
}

# Fingerprint of a directory tree (names and sizes), to prove "untouched".
iso_tree_fingerprint() {
    (cd "$1" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} \; | LC_ALL=C sort)
}

# ---------------------------------------------------------------- shims (test only)

# Installs the Git shim (and, on demand, the strict portability shims) first in
# a dedicated directory. The real tools are resolved BEFORE the directory is
# put in PATH. Only the manager is run with the shim directory in PATH.
iso_shim_init() {
    ISO_SHIM_BIN="$TMP/shim-bin"
    mkdir -p "$ISO_SHIM_BIN" "$TMP/shim-sync"

    export CBS_SHIM_REAL_GIT="$(command -v git)"
    export CBS_SHIM_REAL_FIND="$(command -v find)"
    export CBS_SHIM_REAL_SED="$(command -v sed)"
    export CBS_SHIM_REAL_LS="$(command -v ls)"
    export CBS_SHIM_LOG="$TMP/shim-git.log"
    export CBS_SHIM_SYNC="$TMP/shim-sync"
    export CBS_SHIM_TOOLLOG="$TMP/shim-tools.log"

    : > "$CBS_SHIM_LOG"
    : > "$CBS_SHIM_TOOLLOG"

    cp "$ROOT/tests/fixtures/worktree_isolation/git_shim.sh" "$ISO_SHIM_BIN/git"
    chmod 755 "$ISO_SHIM_BIN/git"
}

iso_shim_install_strict() {
    cp "$ROOT/tests/fixtures/worktree_isolation/strict_find.sh" "$ISO_SHIM_BIN/find"
    cp "$ROOT/tests/fixtures/worktree_isolation/strict_sed.sh" "$ISO_SHIM_BIN/sed"
    cp "$ROOT/tests/fixtures/worktree_isolation/strict_ls.sh" "$ISO_SHIM_BIN/ls"
    chmod 755 "$ISO_SHIM_BIN/find" "$ISO_SHIM_BIN/sed" "$ISO_SHIM_BIN/ls"
}

iso_shim_reset() {
    unset CBS_SHIM_ADD_MODE CBS_SHIM_REMOVE_MODE CBS_SHIM_MUTATE
    unset CBS_SHIM_MUTATE_AT CBS_SHIM_MUTATE_PATH CBS_SHIM_COMMIT2
    unset CBS_SHIM_BRANCH CBS_SHIM_PROOF CBS_SHIM_LOCK
    rm -f "$CBS_SHIM_SYNC/reached" "$CBS_SHIM_SYNC/release" "$CBS_SHIM_SYNC/foreach.count"
    : > "$CBS_SHIM_LOG"
}

# iso_run_shim <args...> : like iso_run, with the shim directory in PATH.
# Fault injection variables are passed through the environment.
iso_run_shim() {
    set +e
    ISO_OUT="$(PATH="$ISO_SHIM_BIN:$PATH" "$ISO_MANAGER" "$@" 2>&1)"
    ISO_RC=$?
    set -e
}

# Number of "git worktree <subcommand>" calls seen by the shim.
iso_shim_count() {
    local count

    count="$(grep -c "^worktree-$1 " "$CBS_SHIM_LOG" 2>/dev/null || true)"
    printf '%s\n' "${count:-0}"
}

# True when any recorded "git worktree" call carries a force option.
iso_shim_saw_force() {
    grep -Eq -- ' (--force|-f|-ff)( |$)' "$CBS_SHIM_LOG"
}

iso_worktree_count() {
    git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ' || true
}

iso_is_registered() {
    git -C "$SOURCE" worktree list --porcelain | grep -Fxq "worktree $1"
}

# iso_expect_failed <label> <reason> <rc>
iso_expect_failed() {
    local label="$1"
    local reason="$2"
    local rc="$3"

    [[ "$(iso_value RESULT)" == "FAIL" ]] ||
        iso_fail "${label}_RESULT_$(iso_value RESULT)_$(iso_value REASON)"
    [[ "$(iso_value REASON)" == "$reason" ]] ||
        iso_fail "${label}_REASON_$(iso_value REASON)"
    [[ "$ISO_RC" -eq "$rc" ]] ||
        iso_fail "${label}_RC_${ISO_RC}"
}

# Exact mode of a path through find (portable: exact -perm match).
iso_has_mode() {
    [[ -n "$(find "$1" -maxdepth 0 -perm "$2" 2>/dev/null)" ]]
}

iso_proof_value() {
    sed -n "s/^CBS_ISOLATION_$2=//p" "$ISO_ROOT/.cbs-isolation/$1.proof" | head -n 1
}
