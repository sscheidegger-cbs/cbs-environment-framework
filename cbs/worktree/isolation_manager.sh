#!/usr/bin/env bash

# D04b-C.1 - Git isolation: detached worktree at an explicit commit.
#
# Commands:
#   isolation_manager.sh create  <id> <source-repository> <expected-origin> <commit> <isolation-root>
#   isolation_manager.sh verify  <id> <source-repository> <isolation-root>
#   isolation_manager.sh cleanup <id> <source-repository> <isolation-root>
#
# Guarantees:
#   - local Git operations only (no network access, no implicit retrieval);
#   - all inputs are validated as data, never sourced or evaluated;
#   - nothing is created before every precondition has been verified;
#   - every created resource is recorded in a CBS ownership proof;
#   - nothing is removed unless the CBS proof and the Git association agree;
#   - the source repository is never modified beyond Git's own worktree
#     administrative entry for the worktree CBS creates or removes.
#
# Compatible with Bash 3.2 (macOS) and Bash 5 (Linux).

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT/cbs/worktree/contract.sh"
source "$ROOT/cbs/worktree/worktree_observer.sh"
source "$ROOT/cbs/worktree/isolation_contract.sh"

# Hermetic Git behaviour: no inherited repository redirection, no prompt,
# no implicit object retrieval, no optional index refresh on the source.
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
unset GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_PREFIX
export GIT_TERMINAL_PROMPT=0
export GIT_NO_LAZY_FETCH=1
export GIT_OPTIONAL_LOCKS=0
export LC_ALL=C

# Git wrapper: repository hooks and file system monitors are never executed.
cbs_isolation_git() {
    # Descriptor 9 (kept for the interruption report) is never given to Git.
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@" 9>&-
}

# ---------------------------------------------------------------- state

cbs_isolation_reset() {
    ISO_OPERATION="${1:-$CBS_ISOLATION_NOT_RUN}"
    ISO_RESULT="$CBS_ISOLATION_RESULT_PASS"
    ISO_REASON="NONE"
    ISO_RC=0
    ISO_ID="$CBS_ISOLATION_NOT_RUN"
    ISO_PATH="$CBS_ISOLATION_NOT_RUN"
    ISO_ORIGIN_REDACTED="$CBS_ISOLATION_NOT_RUN"
    ISO_COMMIT_EXPECTED="$CBS_ISOLATION_NOT_RUN"
    ISO_COMMIT_OBSERVED="$CBS_ISOLATION_NOT_RUN"
    ISO_GIT_STATUS="$CBS_ISOLATION_NOT_RUN"
    ISO_PROOF_ID="$CBS_ISOLATION_NOT_RUN"
    ISO_REMOVED="$CBS_ISOLATION_NOT_RUN"
    ISO_ROLLBACK="$CBS_ISOLATION_NOT_RUN"
    ISO_ROLLBACK_REASON="$CBS_ISOLATION_NOT_RUN"

    ISO_TOKEN=""
    ISO_CREATED_AT=""
    ISO_PROOF_STATE=""
    ISO_ABORT_REASON="NONE"
    ISO_PROOF_FILE=""
    ISO_PROOF_INODE=""
    ISO_SOURCE_COMMON_DIR=""
    ISO_WORKTREE_GIT_DIR="NONE"
    ISO_PATH_IDENTITY="NONE"
    ISO_GIT_DIR_IDENTITY="NONE"
    ISO_LOCK_DIR=""
    ISO_LOCK_TOKEN=""
    ISO_CONCLUDED=0
    ISO_CREATED_DIR=0
    ISO_SOURCE_ROOT=""
    ISO_SOURCE_REPOSITORY=""
    ISO_ORIGIN_OBSERVED=""
    ISO_SOURCE_SNAPSHOT=""
}

cbs_isolation_refuse() {
    ISO_RESULT="$CBS_ISOLATION_RESULT_BLOCKED"
    ISO_REASON="$1"
    ISO_RC="$2"
    return 1
}

cbs_isolation_fail() {
    ISO_RESULT="$CBS_ISOLATION_RESULT_FAIL"
    ISO_REASON="$1"
    ISO_RC="$2"
    return 1
}

cbs_isolation_kv() {
    printf 'CBS_FLUTTER_ISOLATION_%s=' "$1"
    printf '%s' "$2" | tr '[:cntrl:]' '?'
    printf '\n'
}

# Prints the structured result. Always returns 0: callers return ISO_RC.
cbs_isolation_conclude() {
    ISO_CONCLUDED=1

    printf 'CBS_FLUTTER_ISOLATION_VERSION=%s\n' "$CBS_ISOLATION_CONTRACT_VERSION"
    cbs_isolation_kv OPERATION "$ISO_OPERATION"
    cbs_isolation_kv ID "$ISO_ID"
    cbs_isolation_kv ORIGIN "$ISO_ORIGIN_REDACTED"
    cbs_isolation_kv COMMIT_EXPECTED "$ISO_COMMIT_EXPECTED"
    cbs_isolation_kv COMMIT_OBSERVED "$ISO_COMMIT_OBSERVED"
    cbs_isolation_kv PATH "$ISO_PATH"
    cbs_isolation_kv GIT_STATUS "$ISO_GIT_STATUS"
    cbs_isolation_kv PROOF_ID "$ISO_PROOF_ID"
    cbs_isolation_kv REMOVED "$ISO_REMOVED"
    cbs_isolation_kv ROLLBACK "$ISO_ROLLBACK"
    cbs_isolation_kv ROLLBACK_REASON "$ISO_ROLLBACK_REASON"
    cbs_isolation_kv REASON "$ISO_REASON"
    cbs_isolation_kv RC "$ISO_RC"
    cbs_isolation_kv RESULT "$ISO_RESULT"
    return 0
}

# ---------------------------------------------------------------- paths

# True when the spelling of the directory is already its physical path
# (no symlink component, no "..", no ".", no trailing or doubled slash).
cbs_isolation_is_canonical() {
    local candidate="${1:-}"
    local physical

    physical="$(cd -P -- "$candidate" 2>/dev/null && pwd -P)" || return 1

    [[ "$physical" == "$candidate" ]]
}

# Absolute physical path of a Git directory reported by rev-parse.
cbs_isolation_git_abs_path() {
    local directory="${1:-}"
    local option="${2:-}"
    local raw

    raw="$(cbs_isolation_git -C "$directory" rev-parse "$option" 2>/dev/null)" || return 1

    [[ -n "$raw" ]] || return 1

    (cd -P -- "$directory" 2>/dev/null && cd -P -- "$raw" 2>/dev/null && pwd -P)
}

# Prints "<HEAD> <attached|detached>" when the path is a registered worktree.
cbs_isolation_list_entry() {
    local source="${1:-}"
    local path="${2:-}"

    cbs_isolation_git -C "$source" worktree list --porcelain 2>/dev/null |
        CBS_ISOLATION_WANTED="$path" awk '
            BEGIN { wanted = ENVIRON["CBS_ISOLATION_WANTED"] }
            /^worktree / { current = substr($0, 10); head = ""; state = "attached"; next }
            /^HEAD /     { if (current == wanted) head = substr($0, 6); next }
            /^detached$/ { if (current == wanted) state = "detached"; next }
            /^$/         { if (current == wanted && !done) { print head " " state; done = 1 } current = ""; next }
            END          { if (current == wanted && !done) print head " " state }
        '
}

# ---------------------------------------------------------------- identity and permissions

# Inode of a directory or file (POSIX "ls -di", identical on Linux and macOS).
# Together with the Git association it identifies a resource: a path that was
# removed and recreated, or swapped for a copy, does not keep its inode.
cbs_isolation_inode() {
    local path="${1:-}"
    local listing
    local inode
    local rest
    local pattern='^[0-9]+$'

    [[ "$path" == /* ]] || return 1

    listing="$(ls -di "$path" 2>/dev/null)" || return 1

    read -r inode rest <<< "$listing"

    [[ "$inode" =~ $pattern ]] || return 1

    printf '%s\n' "$inode"
}

cbs_isolation_new_token() {
    od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
}

# find with an explicit path first and only options shared by GNU and BSD find.
cbs_isolation_owned_by_me() {
    local found

    found="$(find "${1:-}" -maxdepth 0 -user "$(id -u)" 2>/dev/null)" || found=""

    [[ -n "$found" ]]
}

cbs_isolation_mode_is() {
    local found

    found="$(find "${1:-}" -maxdepth 0 -perm "${2:-}" 2>/dev/null)" || found=""

    [[ -n "$found" ]]
}

cbs_isolation_writable_by_others() {
    local found

    found="$(find "${1:-}" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" || found=""

    [[ -n "$found" ]]
}

cbs_isolation_single_link() {
    local found

    found="$(find "${1:-}" -maxdepth 0 -links 1 2>/dev/null)" || found=""

    [[ -n "$found" ]]
}

# The evidence directory: no symlink, a directory, owned by the current user,
# accessible by nobody else. A directory that is not exactly as CBS creates it
# is refused, never repaired.
cbs_isolation_check_proof_dir() {
    local dir="${1:-}"

    if [[ -L "$dir" ]] || [[ ! -d "$dir" ]]; then
        cbs_isolation_refuse "PROOF_DIR_INVALID" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if ! cbs_isolation_owned_by_me "$dir"; then
        cbs_isolation_refuse "PROOF_DIR_NOT_OWNED" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if ! cbs_isolation_mode_is "$dir" 700; then
        cbs_isolation_refuse "PROOF_DIR_INSECURE" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    return 0
}

# A proof file: regular, no symlink, owned by the current user, a single link
# (no second name to rewrite it), not writable by group or others.
cbs_isolation_check_proof_file() {
    local file="${1:-}"

    if [[ -L "$file" ]]; then
        cbs_isolation_refuse "PROOF_SYMLINK" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        cbs_isolation_refuse "PROOF_MISSING" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if ! cbs_isolation_owned_by_me "$file"; then
        cbs_isolation_refuse "PROOF_NOT_OWNED" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if cbs_isolation_writable_by_others "$file" || ! cbs_isolation_single_link "$file"; then
        cbs_isolation_refuse "PROOF_INSECURE" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------- mutual exclusion

# One lock per authorized root, shared by create and cleanup. mkdir is atomic
# on Linux and macOS and needs no flock (absent on macOS). The lock records
# its owner; it is released only by its owner and never stolen: a lock that
# survives a hard kill blocks until the operator removes it.
cbs_isolation_lock_held() {
    local owner_line=""
    local expected

    [[ -n "$ISO_LOCK_DIR" && -n "$ISO_LOCK_TOKEN" ]] || return 1
    [[ -d "$ISO_LOCK_DIR" && ! -L "$ISO_LOCK_DIR" ]] || return 1
    [[ -f "$ISO_LOCK_DIR/owner" && ! -L "$ISO_LOCK_DIR/owner" ]] || return 1

    IFS= read -r owner_line < "$ISO_LOCK_DIR/owner" 2>/dev/null || true

    expected="pid=$$ token=$ISO_LOCK_TOKEN"

    [[ "$owner_line" == "$expected" ]]
}

cbs_isolation_lock_release() {
    [[ -n "$ISO_LOCK_DIR" ]] || return 0

    if cbs_isolation_lock_held; then
        rm -f "$ISO_LOCK_DIR/owner" 2>/dev/null || true
        rmdir "$ISO_LOCK_DIR" 2>/dev/null || true
    fi

    ISO_LOCK_DIR=""
    ISO_LOCK_TOKEN=""

    exec 9>&-
    trap - EXIT INT TERM HUP
}

# Interruption: report it, release the lock if it is still ours, and stop
# without any further operation (no rollback, no removal).
cbs_isolation_on_signal() {
    local code="${1:-1}"

    trap '' INT TERM HUP

    # A trap runs inside the redirections of the command it interrupted
    # (">/dev/null" around a Git call): the report goes to descriptor 9, the
    # standard output saved when the lock was taken.
    if [[ "$ISO_CONCLUDED" != "1" ]]; then
        ISO_RESULT="$CBS_ISOLATION_RESULT_FAIL"
        ISO_REASON="INTERRUPTED"
        ISO_RC="$code"
        cbs_isolation_conclude >&9 2>/dev/null || true
    fi

    cbs_isolation_lock_release

    exit "$code"
}

cbs_isolation_lock_acquire() {
    local root="${1:-}"
    local lock="$root/$CBS_ISOLATION_LOCK_DIR"
    local token
    local token_pattern='^[0-9a-f]{32}$'

    if [[ -L "$lock" ]] || { [[ -e "$lock" ]] && [[ ! -d "$lock" ]]; }; then
        cbs_isolation_refuse "LOCK_INVALID" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    token="$(cbs_isolation_new_token)" || token=""

    if [[ ! "$token" =~ $token_pattern ]]; then
        cbs_isolation_refuse "LOCK_UNAVAILABLE" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if ! mkdir -m 700 "$lock" 2>/dev/null; then
        if [[ -d "$lock" && ! -L "$lock" ]]; then
            cbs_isolation_refuse "LOCK_BUSY" "$CBS_RC_ISOLATION_STATE_CONFLICT"
        else
            cbs_isolation_refuse "LOCK_UNAVAILABLE" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        fi

        return 1
    fi

    ISO_LOCK_DIR="$lock"
    ISO_LOCK_TOKEN="$token"

    if ! ( umask 077; set -C; printf 'pid=%s token=%s\n' "$$" "$token" > "$lock/owner" ) 2>/dev/null; then
        # The directory was created by this very call and is still empty.
        rmdir "$lock" 2>/dev/null || true
        ISO_LOCK_DIR=""
        ISO_LOCK_TOKEN=""
        cbs_isolation_refuse "LOCK_UNAVAILABLE" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    exec 9>&1

    trap 'cbs_isolation_on_signal 130' INT
    trap 'cbs_isolation_on_signal 143' TERM
    trap 'cbs_isolation_on_signal 129' HUP
    trap 'cbs_isolation_lock_release' EXIT

    return 0
}

# ---------------------------------------------------------------- source repository

cbs_isolation_check_source() {
    local source="${1:-}"
    local top

    if ! cbs_isolation_valid_text "$source"; then
        cbs_isolation_refuse "SOURCE_INVALID" "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
        return 1
    fi

    if [[ "$source" != /* ]]; then
        cbs_isolation_refuse "SOURCE_NOT_ABSOLUTE" "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
        return 1
    fi

    if [[ -L "$source" ]]; then
        cbs_isolation_refuse "SOURCE_SYMLINK" "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
        return 1
    fi

    if [[ ! -d "$source" ]]; then
        cbs_isolation_refuse "SOURCE_MISSING" "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
        return 1
    fi

    if ! cbs_isolation_is_canonical "$source"; then
        cbs_isolation_refuse "SOURCE_NOT_CANONICAL" "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
        return 1
    fi

    if ! cbs_worktree_repository_valid "$source"; then
        cbs_isolation_refuse "SOURCE_NOT_REPOSITORY" "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
        return 1
    fi

    top="$(cbs_isolation_git -C "$source" rev-parse --show-toplevel 2>/dev/null)" || top=""

    if [[ -z "$top" ]] || ! cbs_isolation_is_canonical "$top" || [[ "$top" != "$source" ]]; then
        cbs_isolation_refuse "SOURCE_NOT_TOPLEVEL" "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
        return 1
    fi

    ISO_SOURCE_COMMON_DIR="$(cbs_isolation_git_abs_path "$source" --git-common-dir)" || ISO_SOURCE_COMMON_DIR=""

    if [[ -z "$ISO_SOURCE_COMMON_DIR" ]]; then
        cbs_isolation_refuse "SOURCE_NOT_REPOSITORY" "$CBS_RC_WORKTREE_INVALID_REPOSITORY"
        return 1
    fi

    ISO_SOURCE_REPOSITORY="$source"

    return 0
}

# Reads the origin of the source repository without any network access.
cbs_isolation_observe_origin() {
    local source="${1:-}"

    ISO_ORIGIN_OBSERVED="$(cbs_isolation_git -C "$source" remote get-url origin 2>/dev/null)" || ISO_ORIGIN_OBSERVED=""

    if [[ -z "$ISO_ORIGIN_OBSERVED" ]]; then
        cbs_isolation_refuse "ORIGIN_MISSING" "$CBS_RC_ISOLATION_ORIGIN_MISMATCH"
        return 1
    fi

    return 0
}

cbs_isolation_check_origin() {
    local source="${1:-}"
    local expected="${2:-}"

    if ! cbs_isolation_valid_text "$expected"; then
        cbs_isolation_refuse "ORIGIN_INVALID" "$CBS_RC_ISOLATION_ORIGIN_MISMATCH"
        return 1
    fi

    cbs_isolation_observe_origin "$source" || return 1

    if [[ "$ISO_ORIGIN_OBSERVED" != "$expected" ]]; then
        cbs_isolation_refuse "ORIGIN_MISMATCH" "$CBS_RC_ISOLATION_ORIGIN_MISMATCH"
        return 1
    fi

    return 0
}

cbs_isolation_check_commit() {
    local source="${1:-}"
    local commit="${2:-}"
    local object_type
    local resolved

    if ! cbs_isolation_commit_format_valid "$commit"; then
        cbs_isolation_refuse "COMMIT_NOT_FULL_SHA" "$CBS_RC_ISOLATION_COMMIT_INVALID"
        return 1
    fi

    object_type="$(cbs_isolation_git -C "$source" cat-file -t "$commit" 2>/dev/null)" || object_type=""

    if [[ -z "$object_type" ]]; then
        cbs_isolation_refuse "COMMIT_NOT_AVAILABLE" "$CBS_RC_ISOLATION_COMMIT_INVALID"
        return 1
    fi

    if [[ "$object_type" != "commit" ]]; then
        cbs_isolation_refuse "COMMIT_NOT_A_COMMIT" "$CBS_RC_ISOLATION_COMMIT_INVALID"
        return 1
    fi

    resolved="$(cbs_isolation_git -C "$source" rev-parse --verify --quiet "${commit}^{commit}" 2>/dev/null)" || resolved=""

    if [[ "$resolved" != "$commit" ]]; then
        cbs_isolation_refuse "COMMIT_NOT_AVAILABLE" "$CBS_RC_ISOLATION_COMMIT_INVALID"
        return 1
    fi

    return 0
}

# HEAD, branch, refs and status of the source: used to prove preservation.
cbs_isolation_source_snapshot() {
    local source="${1:-}"
    local head
    local branch
    local refs
    local state

    head="$(cbs_isolation_git -C "$source" rev-parse HEAD 2>/dev/null)" || head="NONE"
    branch="$(cbs_isolation_git -C "$source" branch --show-current 2>/dev/null)" || branch="NONE"
    refs="$(cbs_isolation_git -C "$source" for-each-ref 2>/dev/null)" || refs="NONE"
    state="$(cbs_isolation_git -C "$source" status --porcelain 2>/dev/null)" || state="UNKNOWN"

    printf 'HEAD=%s\nBRANCH=%s\nREFS=\n%s\nSTATUS=\n%s\n' "$head" "$branch" "$refs" "$state"
}

# ---------------------------------------------------------------- isolation root

cbs_isolation_check_root() {
    local root="${1:-}"
    local source="${2:-}"
    local marker
    local marker_line
    local found

    if ! cbs_isolation_valid_text "$root"; then
        cbs_isolation_refuse "ROOT_INVALID" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if [[ "$root" != /* ]]; then
        cbs_isolation_refuse "ROOT_NOT_ABSOLUTE" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if [[ "$root" == "/" ]]; then
        cbs_isolation_refuse "ROOT_FORBIDDEN" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if [[ -L "$root" ]]; then
        cbs_isolation_refuse "ROOT_SYMLINK" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if [[ ! -d "$root" ]]; then
        cbs_isolation_refuse "ROOT_MISSING" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if ! cbs_isolation_is_canonical "$root"; then
        cbs_isolation_refuse "ROOT_NOT_CANONICAL" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    # The isolation root and the source repository must be disjoint.
    case "$root/" in
        "$source"/*)
            cbs_isolation_refuse "ROOT_OVERLAPS_SOURCE" "$CBS_RC_WORKTREE_PATH_CONFLICT"
            return 1
            ;;
    esac

    case "$source/" in
        "$root"/*)
            cbs_isolation_refuse "ROOT_OVERLAPS_SOURCE" "$CBS_RC_WORKTREE_PATH_CONFLICT"
            return 1
            ;;
    esac

    # Explicit authorization: marker file created by the operator.
    marker="$root/$CBS_ISOLATION_ROOT_MARKER"
    marker_line=""

    if [[ -L "$marker" || ! -f "$marker" ]]; then
        cbs_isolation_refuse "ROOT_NOT_AUTHORIZED" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    IFS= read -r marker_line < "$marker" || true

    if [[ "$marker_line" != "$CBS_ISOLATION_ROOT_MARKER_CONTENT" ]]; then
        cbs_isolation_refuse "ROOT_NOT_AUTHORIZED" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    # The root must belong to the current user ...
    found="$(find "$root" -maxdepth 0 -user "$(id -u)" 2>/dev/null)" || found=""

    if [[ -z "$found" ]]; then
        cbs_isolation_refuse "ROOT_NOT_OWNED" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    # ... and must not be writable by group or others.
    found="$(find "$root" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" || found=""

    if [[ -n "$found" ]]; then
        cbs_isolation_refuse "ROOT_WRITABLE_BY_OTHERS" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------- ownership proof

cbs_isolation_proof_content() {
    printf 'CBS_ISOLATION_PROOF_VERSION=%s\n' "$CBS_ISOLATION_CONTRACT_VERSION"
    printf 'CBS_ISOLATION_ID=%s\n' "$ISO_ID"
    printf 'CBS_ISOLATION_TOKEN=%s\n' "$ISO_TOKEN"
    printf 'CBS_ISOLATION_STATE=%s\n' "$ISO_PROOF_STATE"
    printf 'CBS_ISOLATION_CREATED_BY=CBS\n'
    printf 'CBS_ISOLATION_CREATED_AT=%s\n' "$ISO_CREATED_AT"
    printf 'CBS_ISOLATION_SOURCE_REPOSITORY=%s\n' "$ISO_SOURCE_REPOSITORY"
    printf 'CBS_ISOLATION_SOURCE_COMMON_DIR=%s\n' "$ISO_SOURCE_COMMON_DIR"
    printf 'CBS_ISOLATION_ORIGIN=%s\n' "$ISO_ORIGIN_REDACTED"
    printf 'CBS_ISOLATION_COMMIT=%s\n' "$ISO_COMMIT_EXPECTED"
    printf 'CBS_ISOLATION_ROOT=%s\n' "$ISO_SOURCE_ROOT"
    printf 'CBS_ISOLATION_PATH=%s\n' "$ISO_PATH"
    printf 'CBS_ISOLATION_WORKTREE_GIT_DIR=%s\n' "$ISO_WORKTREE_GIT_DIR"
    printf 'CBS_ISOLATION_PATH_IDENTITY=%s\n' "$ISO_PATH_IDENTITY"
    printf 'CBS_ISOLATION_GIT_DIR_IDENTITY=%s\n' "$ISO_GIT_DIR_IDENTITY"
    printf 'CBS_ISOLATION_RESOURCE_PROOF_FILE=%s\n' "$ISO_PROOF_FILE"
    printf 'CBS_ISOLATION_ABORT_REASON=%s\n' "$ISO_ABORT_REASON"
}

# Atomic rewrite: exclusive temporary file in the same directory (unique name,
# mode 600), then rename. The inode of the file just written is remembered:
# any later substitution of the proof is detected by cbs_isolation_proof_intact.
cbs_isolation_store_proof() {
    local file="${1:-}"
    local state="${2:-}"
    local temporary="${1:-}.tmp.${ISO_TOKEN}"

    ISO_PROOF_STATE="$state"

    if ( umask 077; set -C; cbs_isolation_proof_content > "$temporary" ) 2>/dev/null; then
        if mv -f "$temporary" "$file" 2>/dev/null; then
            ISO_PROOF_INODE="$(cbs_isolation_inode "$file")" || ISO_PROOF_INODE=""
            return 0
        fi
    fi

    rm -f "$temporary" 2>/dev/null || true

    return 1
}

# True only when the proof is still the very file this invocation wrote: not a
# symlink, regular, owned, single link, same inode, same token and identifier.
# The empty file of the initial reservation counts when its inode is unchanged.
cbs_isolation_proof_intact() {
    local file="$ISO_PROOF_FILE"

    [[ -n "$file" && -n "$ISO_PROOF_INODE" && -n "$ISO_TOKEN" ]] || return 1
    [[ ! -L "$file" && -f "$file" ]] || return 1

    cbs_isolation_owned_by_me "$file" || return 1
    cbs_isolation_single_link "$file" || return 1

    [[ "$(cbs_isolation_inode "$file")" == "$ISO_PROOF_INODE" ]] || return 1

    if [[ ! -s "$file" ]]; then
        return 0
    fi

    cbs_isolation_load_proof "$file" || return 1

    [[ "$P_TOKEN" == "$ISO_TOKEN" && "$P_ID" == "$ISO_ID" && "$P_CREATED_BY" == "CBS" ]]
}

# Strict parser: whitelisted KEY=VALUE lines, no duplicates, no empty value,
# never sourced and never evaluated.
cbs_isolation_load_proof() {
    local file="${1:-}"
    local line
    local key
    local value
    local variable
    local token_pattern='^[0-9a-f]{32}$'
    local identity_pattern='^([0-9]+|NONE)$'

    P_PROOF_VERSION=""
    P_ID=""
    P_TOKEN=""
    P_STATE=""
    P_CREATED_BY=""
    P_CREATED_AT=""
    P_SOURCE_REPOSITORY=""
    P_SOURCE_COMMON_DIR=""
    P_ORIGIN=""
    P_COMMIT=""
    P_ROOT=""
    P_PATH=""
    P_WORKTREE_GIT_DIR=""
    P_PATH_IDENTITY=""
    P_GIT_DIR_IDENTITY=""
    P_RESOURCE_PROOF_FILE=""
    P_ABORT_REASON=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            CBS_ISOLATION_*=*)
                ;;
            *)
                return 1
                ;;
        esac

        key="${line%%=*}"
        value="${line#*=}"

        case "$key" in
            CBS_ISOLATION_PROOF_VERSION|CBS_ISOLATION_ID|CBS_ISOLATION_TOKEN|CBS_ISOLATION_STATE|CBS_ISOLATION_CREATED_BY|CBS_ISOLATION_CREATED_AT|CBS_ISOLATION_SOURCE_REPOSITORY|CBS_ISOLATION_SOURCE_COMMON_DIR|CBS_ISOLATION_ORIGIN|CBS_ISOLATION_COMMIT|CBS_ISOLATION_ROOT|CBS_ISOLATION_PATH|CBS_ISOLATION_WORKTREE_GIT_DIR|CBS_ISOLATION_PATH_IDENTITY|CBS_ISOLATION_GIT_DIR_IDENTITY|CBS_ISOLATION_RESOURCE_PROOF_FILE|CBS_ISOLATION_ABORT_REASON)
                ;;
            *)
                return 1
                ;;
        esac

        cbs_isolation_valid_text "$value" || return 1

        variable="P_${key#CBS_ISOLATION_}"

        [[ -z "${!variable}" ]] || return 1

        printf -v "$variable" '%s' "$value"
    done < "$file"

    [[ -n "$P_PROOF_VERSION" && -n "$P_ID" && -n "$P_TOKEN" && -n "$P_STATE" ]] || return 1
    [[ -n "$P_CREATED_BY" && -n "$P_CREATED_AT" && -n "$P_SOURCE_REPOSITORY" ]] || return 1
    [[ -n "$P_SOURCE_COMMON_DIR" && -n "$P_ORIGIN" && -n "$P_COMMIT" && -n "$P_ROOT" ]] || return 1
    [[ -n "$P_PATH" && -n "$P_WORKTREE_GIT_DIR" && -n "$P_RESOURCE_PROOF_FILE" ]] || return 1
    [[ -n "$P_ABORT_REASON" ]] || return 1
    [[ -n "$P_PATH_IDENTITY" && -n "$P_GIT_DIR_IDENTITY" ]] || return 1

    [[ "$P_TOKEN" =~ $token_pattern ]] || return 1
    [[ "$P_PATH_IDENTITY" =~ $identity_pattern ]] || return 1
    [[ "$P_GIT_DIR_IDENTITY" =~ $identity_pattern ]] || return 1

    return 0
}

# ---------------------------------------------------------------- checkout verification

# Verifies the isolated checkout: path, Git identity, association with the
# source, exact HEAD, detached state and cleanliness. Never mutates.
cbs_isolation_check_checkout() {
    local path="${1:-}"
    local commit="${2:-}"
    local source="${3:-}"
    local top
    local head
    local common
    local entry
    local state

    if [[ -L "$path" ]]; then
        cbs_isolation_refuse "PATH_SYMLINK" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        cbs_isolation_refuse "PATH_MISSING" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if [[ ! -d "$path" ]]; then
        cbs_isolation_refuse "PATH_NOT_DIRECTORY" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    if ! cbs_isolation_is_canonical "$path"; then
        cbs_isolation_refuse "PATH_NOT_CANONICAL" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        return 1
    fi

    top="$(cbs_isolation_git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || top=""

    if [[ -z "$top" ]] || ! cbs_isolation_is_canonical "$top" || [[ "$top" != "$path" ]]; then
        cbs_isolation_refuse "NOT_A_WORKTREE" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    head="$(cbs_isolation_git -C "$path" rev-parse HEAD 2>/dev/null)" || head=""

    if [[ -n "$head" ]]; then
        ISO_COMMIT_OBSERVED="$head"
    fi

    if [[ "$head" != "$commit" ]]; then
        cbs_isolation_refuse "HEAD_MISMATCH" "$CBS_RC_ISOLATION_STATE_CONFLICT"
        return 1
    fi

    if [[ "$(cbs_worktree_branch_state "$path")" != "$CBS_WORKTREE_BRANCH_DETACHED" ]]; then
        cbs_isolation_refuse "NOT_DETACHED" "$CBS_RC_ISOLATION_STATE_CONFLICT"
        return 1
    fi

    common="$(cbs_isolation_git_abs_path "$path" --git-common-dir)" || common=""

    if [[ -z "$common" || "$common" != "$ISO_SOURCE_COMMON_DIR" ]]; then
        cbs_isolation_refuse "SOURCE_ASSOCIATION_MISMATCH" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    entry="$(cbs_isolation_list_entry "$source" "$path")" || entry=""

    if [[ "$entry" != "$commit detached" ]]; then
        cbs_isolation_refuse "NOT_LISTED_BY_SOURCE" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if ! cbs_isolation_git -C "$path" status --porcelain >/dev/null 2>&1; then
        cbs_isolation_refuse "WORKTREE_STATUS_UNKNOWN" "$CBS_RC_ISOLATION_STATE_CONFLICT"
        return 1
    fi

    state="$(cbs_worktree_worktree_state "$path")"
    ISO_GIT_STATUS="$state"

    if [[ "$state" != "CLEAN" ]]; then
        cbs_isolation_refuse "WORKTREE_DIRTY" "$CBS_RC_ISOLATION_STATE_CONFLICT"
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------- association and invariants

# The isolated worktree must be the very one Git registered under the source
# common directory: same Git directory (and under <common>/worktrees), Git
# directory pointing back to <path>/.git, same identity of the directory and
# of the Git directory as when CBS created them.
#   cbs_isolation_check_association <path> <git-dir> <path-id> <git-dir-id|NONE>
cbs_isolation_check_association() {
    local path="${1:-}"
    local git_dir="${2:-}"
    local path_identity="${3:-}"
    local git_dir_identity="${4:-}"
    local observed
    local backlink=""

    observed="$(cbs_isolation_git_abs_path "$path" --git-dir)" || observed=""

    if [[ -z "$observed" || "$observed" != "$git_dir" ]]; then
        cbs_isolation_refuse "GIT_DIR_MISMATCH" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    case "$observed" in
        "$ISO_SOURCE_COMMON_DIR"/worktrees/?*)
            ;;
        *)
            cbs_isolation_refuse "GIT_DIR_MISMATCH" "$CBS_RC_ISOLATION_OWNERSHIP"
            return 1
            ;;
    esac

    IFS= read -r backlink < "$observed/gitdir" 2>/dev/null || true

    if [[ "$backlink" != "$path/.git" ]]; then
        cbs_isolation_refuse "GIT_DIR_MISMATCH" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if [[ "$(cbs_isolation_inode "$path")" != "$path_identity" ]]; then
        cbs_isolation_refuse "PATH_IDENTITY_MISMATCH" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if [[ "$git_dir_identity" != "NONE" ]] &&
        [[ "$(cbs_isolation_inode "$observed")" != "$git_dir_identity" ]]
    then
        cbs_isolation_refuse "GIT_DIR_IDENTITY_MISMATCH" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    return 0
}

# Every Git invariant that must hold immediately before a removal.
cbs_isolation_git_invariants() {
    local path="${1:-}"
    local commit="${2:-}"
    local source="${3:-}"
    local git_dir="${4:-}"
    local path_identity="${5:-}"
    local git_dir_identity="${6:-}"

    cbs_isolation_check_checkout "$path" "$commit" "$source" || return 1
    cbs_isolation_check_association "$path" "$git_dir" "$path_identity" "$git_dir_identity" || return 1

    return 0
}

# ---------------------------------------------------------------- create

cbs_isolation_rollback_refused() {
    ISO_ROLLBACK="INCOMPLETE"
    ISO_ROLLBACK_REASON="$1"
    return 0
}

cbs_isolation_rollback_done() {
    ISO_ROLLBACK="DONE"
    ISO_ROLLBACK_REASON="NONE"
    return 0
}

# Rolls back only what this very invocation created, and only when, at that
# very moment, the lock is still held, the proof is still the one written by
# this invocation, the directory is still the one this invocation made and
# every Git invariant still holds. Anything else is left exactly as found:
# the rollback is refused (ROLLBACK=INCOMPLETE and the reason is reported).
# The removal is never forced, nothing is pruned, nothing is deleted
# recursively. An interrupted rollback leaves the proof unusable for cleanup.
cbs_isolation_rollback() {
    local source="${1:-}"
    local path="${2:-}"
    local entry
    local git_dir
    local refusal
    local saved_result
    local saved_reason
    local saved_rc
    local saved_observed
    local saved_status

    [[ "$ISO_CREATED_DIR" == "1" ]] || return 0

    if ! cbs_isolation_lock_held; then
        cbs_isolation_rollback_refused "LOCK_LOST"
        return 0
    fi

    if ! cbs_isolation_proof_intact; then
        cbs_isolation_rollback_refused "PROOF_SUBSTITUTED"
        return 0
    fi

    if [[ -L "$path" ]]; then
        cbs_isolation_rollback_refused "PATH_SYMLINK"
        return 0
    fi

    entry="$(cbs_isolation_list_entry "$source" "$path")" || entry=""

    if [[ ! -e "$path" ]]; then
        # Git already removed the directory it could not populate.
        if [[ -n "$entry" ]]; then
            cbs_isolation_rollback_refused "REGISTERED_WITHOUT_PATH"
        else
            cbs_isolation_rollback_done
        fi

        return 0
    fi

    if [[ ! -d "$path" ]]; then
        cbs_isolation_rollback_refused "PATH_REPLACED"
        return 0
    fi

    if [[ "$ISO_PATH_IDENTITY" == "NONE" ]]; then
        cbs_isolation_rollback_refused "PATH_IDENTITY_UNKNOWN"
        return 0
    fi

    if [[ "$(cbs_isolation_inode "$path")" != "$ISO_PATH_IDENTITY" ]]; then
        cbs_isolation_rollback_refused "PATH_REPLACED"
        return 0
    fi

    if [[ -z "$entry" ]]; then
        # Not registered: the only thing that can be removed is the empty
        # directory made by this invocation (rmdir never removes content).
        if rmdir "$path" 2>/dev/null; then
            cbs_isolation_rollback_done
        else
            cbs_isolation_rollback_refused "PATH_NOT_EMPTY"
        fi

        return 0
    fi

    # Registered: every Git invariant must hold, otherwise the worktree was
    # modified or is not the one this invocation made.
    saved_result="$ISO_RESULT"
    saved_reason="$ISO_REASON"
    saved_rc="$ISO_RC"
    saved_observed="$ISO_COMMIT_OBSERVED"
    saved_status="$ISO_GIT_STATUS"

    git_dir="$(cbs_isolation_git_abs_path "$path" --git-dir)" || git_dir=""
    refusal=""

    if ! cbs_isolation_git_invariants "$path" "$ISO_COMMIT_EXPECTED" "$source" "$git_dir" "$ISO_PATH_IDENTITY" "$ISO_GIT_DIR_IDENTITY"; then
        refusal="$ISO_REASON"
    fi

    ISO_RESULT="$saved_result"
    ISO_REASON="$saved_reason"
    ISO_RC="$saved_rc"
    ISO_COMMIT_OBSERVED="$saved_observed"
    ISO_GIT_STATUS="$saved_status"

    if [[ -n "$refusal" ]]; then
        cbs_isolation_rollback_refused "$refusal"
        return 0
    fi

    # Last gate, immediately before the removal.
    if ! cbs_isolation_lock_held; then
        cbs_isolation_rollback_refused "LOCK_LOST"
        return 0
    fi

    if ! cbs_isolation_proof_intact; then
        cbs_isolation_rollback_refused "PROOF_SUBSTITUTED"
        return 0
    fi

    if [[ -L "$path" || "$(cbs_isolation_inode "$path")" != "$ISO_PATH_IDENTITY" ]]; then
        cbs_isolation_rollback_refused "PATH_REPLACED"
        return 0
    fi

    # Non-forced removal: Git itself refuses a modified or locked worktree.
    if ! cbs_isolation_git -C "$source" worktree remove "$path" >/dev/null 2>&1; then
        cbs_isolation_rollback_refused "WORKTREE_REMOVE_FAILED"
        return 0
    fi

    entry="$(cbs_isolation_list_entry "$source" "$path")" || entry=""

    if [[ -e "$path" || -L "$path" || -n "$entry" || -e "$git_dir" ]]; then
        cbs_isolation_rollback_refused "REMOVE_INCOMPLETE"
        return 0
    fi

    cbs_isolation_rollback_done

    return 0
}

# Converts the current refusal into a FAIL, rolls back what can be proven to be
# ours, and records the abort in the proof when, and only when, the lock and the
# proof are still ours.
cbs_isolation_abort_create() {
    local source="${1:-}"

    ISO_RESULT="$CBS_ISOLATION_RESULT_FAIL"
    ISO_ABORT_REASON="$ISO_REASON"

    cbs_isolation_rollback "$source" "$ISO_PATH"

    if cbs_isolation_lock_held && cbs_isolation_proof_intact; then
        cbs_isolation_store_proof "$ISO_PROOF_FILE" "ABORTED" || true
    fi

    return 1
}

cbs_isolation_create_preconditions() {
    local source="${1:-}"
    local origin="${2:-}"
    local commit="${3:-}"
    local root="${4:-}"

    cbs_isolation_check_source "$source" &&
        cbs_isolation_check_origin "$source" "$origin" &&
        cbs_isolation_check_commit "$source" "$commit" &&
        cbs_isolation_check_root "$root" "$source"
}

cbs_isolation_create() {
    local id="${1:-}"
    local source="${2:-}"
    local origin="${3:-}"
    local commit="${4:-}"
    local root="${5:-}"
    local create_rc=0

    cbs_isolation_reset "create"

    ISO_ID="${id:-$CBS_ISOLATION_NOT_RUN}"
    ISO_COMMIT_EXPECTED="${commit:-$CBS_ISOLATION_NOT_RUN}"
    ISO_ORIGIN_REDACTED="$(cbs_isolation_redact "${origin:-$CBS_ISOLATION_NOT_RUN}")"

    if [[ -z "$id" || -z "$source" || -z "$origin" || -z "$commit" || -z "$root" ]]; then
        cbs_isolation_refuse "USAGE" "$CBS_RC_WORKTREE_USAGE"
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    # ---- read-only preconditions

    if ! cbs_isolation_id_valid "$id"; then
        cbs_isolation_refuse "ID_INVALID" "$CBS_RC_WORKTREE_USAGE"
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if ! cbs_isolation_create_preconditions "$source" "$origin" "$commit" "$root"; then
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    # ---- mutual exclusion: everything below runs with the lock of the root

    if ! cbs_isolation_lock_acquire "$root"; then
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    cbs_isolation_create_locked "$id" "$source" "$origin" "$commit" "$root" || create_rc=$?

    cbs_isolation_lock_release

    return "$create_rc"
}

cbs_isolation_create_locked() {
    local id="${1:-}"
    local source="${2:-}"
    local origin="${3:-}"
    local commit="${4:-}"
    local root="${5:-}"
    local path
    local proof_dir
    local proof_file
    local cleaned_file
    local entry
    local snapshot_before
    local snapshot_after
    local token_pattern='^[0-9a-f]{32}$'

    # Same preconditions again, now that nobody else can change the root.
    if ! cbs_isolation_create_preconditions "$source" "$origin" "$commit" "$root"; then
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    path="$root/$id"
    proof_dir="$root/$CBS_ISOLATION_PROOF_DIR"
    proof_file="$proof_dir/$id.proof"
    cleaned_file="$proof_dir/$id.cleaned"

    ISO_PATH="$path"
    ISO_PROOF_FILE="$proof_file"
    ISO_SOURCE_ROOT="$root"
    ISO_ORIGIN_REDACTED="$(cbs_isolation_redact "$ISO_ORIGIN_OBSERVED")"

    if [[ -e "$proof_dir" || -L "$proof_dir" ]]; then
        if ! cbs_isolation_check_proof_dir "$proof_dir"; then
            cbs_isolation_conclude
            return "$ISO_RC"
        fi
    fi

    # An identifier is never reused, even after a cleanup or an abort.
    if [[ -e "$proof_file" || -L "$proof_file" || -e "$cleaned_file" || -L "$cleaned_file" ]]; then
        cbs_isolation_refuse "ID_ALREADY_USED" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if [[ -L "$path" ]]; then
        cbs_isolation_refuse "PATH_SYMLINK" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if [[ -e "$path" ]]; then
        cbs_isolation_refuse "PATH_EXISTS" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    entry="$(cbs_isolation_list_entry "$source" "$path")" || entry=""

    if [[ -n "$entry" ]]; then
        cbs_isolation_refuse "PATH_REGISTERED" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_TOKEN="$(cbs_isolation_new_token)" || ISO_TOKEN=""

    if ! [[ "$ISO_TOKEN" =~ $token_pattern ]]; then
        cbs_isolation_refuse "TOKEN_UNAVAILABLE" "$CBS_RC_ISOLATION_FAILED"
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    snapshot_before="$(cbs_isolation_source_snapshot "$source")"

    # ---- mutations start here: proof first, then the worktree

    if [[ ! -d "$proof_dir" ]]; then
        if ! mkdir -m 700 "$proof_dir" 2>/dev/null; then
            cbs_isolation_refuse "PROOF_DIR_INVALID" "$CBS_RC_WORKTREE_PATH_CONFLICT"
            cbs_isolation_conclude
            return "$ISO_RC"
        fi
    fi

    # Whatever the directory was, it must now be exactly what CBS requires.
    if ! cbs_isolation_check_proof_dir "$proof_dir"; then
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    # Exclusive reservation of the identifier (no-clobber, atomic, mode 600).
    if ! ( umask 077; set -C; : > "$proof_file" ) 2>/dev/null; then
        cbs_isolation_refuse "ID_ALREADY_USED" "$CBS_RC_WORKTREE_PATH_CONFLICT"
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_PROOF_ID="$ISO_TOKEN"
    ISO_PROOF_INODE="$(cbs_isolation_inode "$proof_file")" || ISO_PROOF_INODE=""

    if [[ -z "$ISO_PROOF_INODE" ]] || ! cbs_isolation_store_proof "$proof_file" "CREATING"; then
        cbs_isolation_fail "PROOF_WRITE_FAILED" "$CBS_RC_ISOLATION_FAILED" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    # Atomic reservation of the path: mkdir fails if anything exists.
    if ! mkdir "$path" 2>/dev/null; then
        cbs_isolation_fail "PATH_EXISTS" "$CBS_RC_WORKTREE_PATH_CONFLICT" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_CREATED_DIR=1

    # Identity of the directory this invocation made, kept in the proof.
    ISO_PATH_IDENTITY="$(cbs_isolation_inode "$path")" || ISO_PATH_IDENTITY="NONE"

    if [[ "$ISO_PATH_IDENTITY" == "NONE" ]] || ! cbs_isolation_store_proof "$proof_file" "CREATING"; then
        cbs_isolation_fail "PROOF_WRITE_FAILED" "$CBS_RC_ISOLATION_FAILED" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if ! cbs_isolation_git -C "$source" worktree add --detach "$path" "$commit" >/dev/null 2>&1; then
        cbs_isolation_fail "GIT_WORKTREE_ADD_FAILED" "$CBS_RC_ISOLATION_FAILED" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if ! cbs_isolation_check_checkout "$path" "$commit" "$source"; then
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_WORKTREE_GIT_DIR="$(cbs_isolation_git_abs_path "$path" --git-dir)" || ISO_WORKTREE_GIT_DIR=""

    case "$ISO_WORKTREE_GIT_DIR" in
        "$ISO_SOURCE_COMMON_DIR"/worktrees/?*)
            ;;
        *)
            ISO_WORKTREE_GIT_DIR="NONE"
            cbs_isolation_fail "SOURCE_ASSOCIATION_MISMATCH" "$CBS_RC_ISOLATION_OWNERSHIP" || true
            cbs_isolation_abort_create "$source" || true
            cbs_isolation_conclude
            return "$ISO_RC"
            ;;
    esac

    if ! cbs_isolation_check_association "$path" "$ISO_WORKTREE_GIT_DIR" "$ISO_PATH_IDENTITY" "NONE"; then
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_GIT_DIR_IDENTITY="$(cbs_isolation_inode "$ISO_WORKTREE_GIT_DIR")" || ISO_GIT_DIR_IDENTITY="NONE"

    if [[ "$ISO_GIT_DIR_IDENTITY" == "NONE" ]]; then
        cbs_isolation_fail "GIT_DIR_IDENTITY_UNAVAILABLE" "$CBS_RC_ISOLATION_FAILED" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    snapshot_after="$(cbs_isolation_source_snapshot "$source")"

    if [[ "$snapshot_after" != "$snapshot_before" ]]; then
        cbs_isolation_fail "SOURCE_CHANGED" "$CBS_RC_ISOLATION_STATE_CONFLICT" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    # The lock and the proof must still be ours before READY is recorded.
    if ! cbs_isolation_lock_held; then
        cbs_isolation_fail "LOCK_LOST" "$CBS_RC_ISOLATION_STATE_CONFLICT" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if ! cbs_isolation_proof_intact; then
        cbs_isolation_fail "PROOF_SUBSTITUTED" "$CBS_RC_ISOLATION_OWNERSHIP" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if ! cbs_isolation_store_proof "$proof_file" "READY"; then
        cbs_isolation_fail "PROOF_WRITE_FAILED" "$CBS_RC_ISOLATION_FAILED" || true
        cbs_isolation_abort_create "$source" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_RESULT="$CBS_ISOLATION_RESULT_PASS"
    ISO_REASON="NONE"
    ISO_RC=0

    cbs_isolation_conclude
    return 0
}

# ---------------------------------------------------------------- verify / cleanup

# Read-only. Establishes that the isolated worktree was created by CBS and is
# still exactly what the proof says. Sets ISO_* from the proof.
cbs_isolation_verify_owned() {
    local id="${1:-}"
    local source="${2:-}"
    local root="${3:-}"
    local proof_dir
    local proof_file
    local cleaned_file
    local identity_pattern='^[0-9]+$'

    if [[ -z "$id" || -z "$source" || -z "$root" ]]; then
        cbs_isolation_refuse "USAGE" "$CBS_RC_WORKTREE_USAGE"
        return 1
    fi

    ISO_ID="$id"

    if ! cbs_isolation_id_valid "$id"; then
        cbs_isolation_refuse "ID_INVALID" "$CBS_RC_WORKTREE_USAGE"
        return 1
    fi

    cbs_isolation_check_source "$source" || return 1
    cbs_isolation_check_root "$root" "$source" || return 1

    proof_dir="$root/$CBS_ISOLATION_PROOF_DIR"
    proof_file="$proof_dir/$id.proof"
    cleaned_file="$proof_dir/$id.cleaned"

    ISO_SOURCE_ROOT="$root"
    ISO_PATH="$root/$id"

    if [[ -e "$proof_dir" || -L "$proof_dir" ]]; then
        cbs_isolation_check_proof_dir "$proof_dir" || return 1
    fi

    cbs_isolation_check_proof_file "$proof_file" || return 1

    if [[ -e "$cleaned_file" || -L "$cleaned_file" ]]; then
        cbs_isolation_refuse "ALREADY_CLEANED" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if ! cbs_isolation_load_proof "$proof_file"; then
        cbs_isolation_refuse "PROOF_MALFORMED" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    ISO_PROOF_ID="$P_TOKEN"
    ISO_COMMIT_EXPECTED="$P_COMMIT"
    ISO_ORIGIN_REDACTED="$P_ORIGIN"
    ISO_TOKEN="$P_TOKEN"
    ISO_CREATED_AT="$P_CREATED_AT"
    ISO_SOURCE_REPOSITORY="$source"
    ISO_PROOF_FILE="$proof_file"

    if [[ "$P_PROOF_VERSION" != "$CBS_ISOLATION_CONTRACT_VERSION" ]]; then
        cbs_isolation_refuse "PROOF_MISMATCH_VERSION" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if [[ "$P_CREATED_BY" != "CBS" ]]; then
        cbs_isolation_refuse "PROOF_MISMATCH_CREATED_BY" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if [[ "$P_ID" != "$id" ]]; then
        cbs_isolation_refuse "PROOF_MISMATCH_ID" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    case "$P_STATE" in
        READY)
            ;;
        CREATING|ABORTED)
            cbs_isolation_refuse "PROOF_STATE_$P_STATE" "$CBS_RC_ISOLATION_OWNERSHIP"
            return 1
            ;;
        *)
            cbs_isolation_refuse "PROOF_STATE_INVALID" "$CBS_RC_ISOLATION_OWNERSHIP"
            return 1
            ;;
    esac

    # A READY resource always records the identity of its directory and of
    # its Git directory.
    if [[ ! "$P_PATH_IDENTITY" =~ $identity_pattern || ! "$P_GIT_DIR_IDENTITY" =~ $identity_pattern ]]; then
        cbs_isolation_refuse "PROOF_MALFORMED" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if [[ "$P_ROOT" != "$root" ]]; then
        cbs_isolation_refuse "PROOF_MISMATCH_ROOT" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    # The path is recomputed from the authorized root and the identifier:
    # the path recorded in the proof is never trusted on its own.
    if [[ "$P_PATH" != "$ISO_PATH" ]]; then
        cbs_isolation_refuse "PROOF_MISMATCH_PATH" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if [[ "$P_RESOURCE_PROOF_FILE" != "$proof_file" ]]; then
        cbs_isolation_refuse "PROOF_MISMATCH_PROOF_FILE" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if [[ "$P_SOURCE_REPOSITORY" != "$source" || "$P_SOURCE_COMMON_DIR" != "$ISO_SOURCE_COMMON_DIR" ]]; then
        cbs_isolation_refuse "SOURCE_MISMATCH" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    if ! cbs_isolation_commit_format_valid "$P_COMMIT"; then
        cbs_isolation_refuse "PROOF_MISMATCH_COMMIT" "$CBS_RC_ISOLATION_OWNERSHIP"
        return 1
    fi

    cbs_isolation_observe_origin "$source" || return 1

    if [[ "$(cbs_isolation_redact "$ISO_ORIGIN_OBSERVED")" != "$P_ORIGIN" ]]; then
        cbs_isolation_refuse "ORIGIN_MISMATCH" "$CBS_RC_ISOLATION_ORIGIN_MISMATCH"
        return 1
    fi

    cbs_isolation_git_invariants "$ISO_PATH" "$P_COMMIT" "$source" \
        "$P_WORKTREE_GIT_DIR" "$P_PATH_IDENTITY" "$P_GIT_DIR_IDENTITY" || return 1

    ISO_WORKTREE_GIT_DIR="$P_WORKTREE_GIT_DIR"
    ISO_PATH_IDENTITY="$P_PATH_IDENTITY"
    ISO_GIT_DIR_IDENTITY="$P_GIT_DIR_IDENTITY"

    return 0
}

cbs_isolation_verify() {
    cbs_isolation_reset "verify"

    if cbs_isolation_verify_owned "${1:-}" "${2:-}" "${3:-}"; then
        ISO_RESULT="$CBS_ISOLATION_RESULT_PASS"
        ISO_REASON="NONE"
        ISO_RC=0
    fi

    cbs_isolation_conclude
    return "$ISO_RC"
}

cbs_isolation_cleanup() {
    local id="${1:-}"
    local source="${2:-}"
    local root="${3:-}"
    local cleanup_rc=0

    cbs_isolation_reset "cleanup"

    if [[ -z "$id" || -z "$source" || -z "$root" ]]; then
        cbs_isolation_refuse "USAGE" "$CBS_RC_WORKTREE_USAGE" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_ID="$id"

    if ! cbs_isolation_id_valid "$id"; then
        cbs_isolation_refuse "ID_INVALID" "$CBS_RC_WORKTREE_USAGE" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    # The lock lives in the root: the root is validated first, so that no
    # lock is ever created in a root that was not authorized.
    if ! cbs_isolation_check_source "$source" || ! cbs_isolation_check_root "$root" "$source"; then
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if ! cbs_isolation_lock_acquire "$root"; then
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    cbs_isolation_cleanup_locked "$id" "$source" "$root" || cleanup_rc=$?

    cbs_isolation_lock_release

    return "$cleanup_rc"
}

cbs_isolation_cleanup_locked() {
    local id="${1:-}"
    local source="${2:-}"
    local root="${3:-}"
    local snapshot_before
    local snapshot_after
    local entry
    local cleaned_file
    local first_token

    if ! cbs_isolation_verify_owned "$id" "$source" "$root"; then
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    first_token="$ISO_TOKEN"
    cleaned_file="$(dirname "$ISO_PROOF_FILE")/$ISO_ID.cleaned"
    snapshot_before="$(cbs_isolation_source_snapshot "$source")"

    # Every invariant is established again immediately before the removal:
    # the lock, the proof, the identity of the directory and of the Git
    # directory, HEAD, the detached state and the cleanliness of the worktree.
    if ! cbs_isolation_lock_held; then
        cbs_isolation_refuse "LOCK_LOST" "$CBS_RC_ISOLATION_STATE_CONFLICT" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if ! cbs_isolation_verify_owned "$id" "$source" "$root"; then
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    if [[ "$ISO_TOKEN" != "$first_token" ]]; then
        cbs_isolation_refuse "PROOF_SUBSTITUTED" "$CBS_RC_ISOLATION_OWNERSHIP" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    # Non-forced removal of that exact path: Git itself refuses a modified or
    # locked worktree. A failure never leads to another deletion.
    if ! cbs_isolation_git -C "$source" worktree remove "$ISO_PATH" >/dev/null 2>&1; then
        cbs_isolation_fail "WORKTREE_REMOVE_FAILED" "$CBS_RC_ISOLATION_FAILED" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    entry="$(cbs_isolation_list_entry "$source" "$ISO_PATH")" || entry=""

    if [[ -e "$ISO_PATH" || -L "$ISO_PATH" || -n "$entry" || -e "$ISO_WORKTREE_GIT_DIR" ]]; then
        cbs_isolation_fail "REMOVE_INCOMPLETE" "$CBS_RC_ISOLATION_FAILED" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_REMOVED="$ISO_PATH"

    snapshot_after="$(cbs_isolation_source_snapshot "$source")"

    if [[ "$snapshot_after" != "$snapshot_before" ]]; then
        cbs_isolation_fail "SOURCE_CHANGED" "$CBS_RC_ISOLATION_STATE_CONFLICT" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    # The proof is preserved; the cleanup is recorded next to it (exclusive
    # creation, mode 600: a planted file or symlink is never written through).
    if ! (
        umask 077
        set -C
        {
            printf 'CBS_ISOLATION_PROOF_VERSION=%s\n' "$CBS_ISOLATION_CONTRACT_VERSION"
            printf 'CBS_ISOLATION_ID=%s\n' "$ISO_ID"
            printf 'CBS_ISOLATION_TOKEN=%s\n' "$ISO_TOKEN"
            printf 'CBS_ISOLATION_CLEANED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            printf 'CBS_ISOLATION_PATH=%s\n' "$ISO_PATH"
            printf 'CBS_ISOLATION_WORKTREE_GIT_DIR=%s\n' "$ISO_WORKTREE_GIT_DIR"
        } > "$cleaned_file"
    ) 2>/dev/null; then
        cbs_isolation_fail "CLEANED_RECORD_FAILED" "$CBS_RC_ISOLATION_FAILED" || true
        cbs_isolation_conclude
        return "$ISO_RC"
    fi

    ISO_RESULT="$CBS_ISOLATION_RESULT_PASS"
    ISO_REASON="NONE"
    ISO_RC=0

    cbs_isolation_conclude
    return 0
}

# ---------------------------------------------------------------- entry point

cbs_isolation_main() {
    local command="${1:-}"

    case "$command" in
        create)
            if [[ "$#" -ne 6 ]]; then
                cbs_isolation_reset "create"
                cbs_isolation_refuse "USAGE" "$CBS_RC_WORKTREE_USAGE" || true
                cbs_isolation_conclude
                return "$ISO_RC"
            fi
            cbs_isolation_create "$2" "$3" "$4" "$5" "$6"
            ;;
        verify)
            if [[ "$#" -ne 4 ]]; then
                cbs_isolation_reset "verify"
                cbs_isolation_refuse "USAGE" "$CBS_RC_WORKTREE_USAGE" || true
                cbs_isolation_conclude
                return "$ISO_RC"
            fi
            cbs_isolation_verify "$2" "$3" "$4"
            ;;
        cleanup)
            if [[ "$#" -ne 4 ]]; then
                cbs_isolation_reset "cleanup"
                cbs_isolation_refuse "USAGE" "$CBS_RC_WORKTREE_USAGE" || true
                cbs_isolation_conclude
                return "$ISO_RC"
            fi
            cbs_isolation_cleanup "$2" "$3" "$4"
            ;;
        *)
            cbs_isolation_reset "${command:-$CBS_ISOLATION_NOT_RUN}"
            cbs_isolation_refuse "USAGE" "$CBS_RC_WORKTREE_USAGE" || true
            cbs_isolation_conclude
            return "$ISO_RC"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    ISO_MAIN_RC=0
    cbs_isolation_main "$@" || ISO_MAIN_RC=$?
    exit "$ISO_MAIN_RC"
fi
