#!/usr/bin/env bash

# CBS Remote transport.
#
# Builds and runs SSH invocations. No remote shell text is ever composed from
# user input: the only remote programs are the two fixed scripts below, run
# through /bin/sh -c, and the declared CBS entrypoint. Every value that
# reaches the remote command line is individually single-quoted, so the remote
# login shell can neither split nor interpret it.

REMOTE_TRANSPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REMOTE_TRANSPORT_DIR/contract.sh"

CBS_REMOTE_SSH_ARGV=()
CBS_REMOTE_SSH_DESTINATION=""
CBS_REMOTE_SSH_STDOUT=""
CBS_REMOTE_SSH_RC=0

# Fixed, read-only probe. It must not contain any single quote character.
# Positional arguments: PATH_PREPEND REPOSITORY EXPECTED_COMMIT ENTRYPOINT
# It always exits 0 once it started; ssh failures are reported by ssh itself.
read -r -d '' CBS_REMOTE_PROBE_SCRIPT <<'CBS_REMOTE_PROBE_EOF' || true
if [ -n "$1" ]; then PATH="$1:$PATH"; export PATH; fi
repo="$2"
expected="$3"
entry="$4"
p="CBS_REMOTE_PROBE_"
finish() { echo "${p}COMPLETE=YES"; exit 0; }
if ! command -v git >/dev/null 2>&1; then
  echo "${p}GIT=UNAVAILABLE"
  finish
fi
echo "${p}GIT=AVAILABLE"
if [ ! -e "$repo" ]; then
  echo "${p}REPOSITORY=MISSING"
  finish
fi
if [ ! -d "$repo" ]; then
  echo "${p}REPOSITORY=NOT_GIT"
  finish
fi
physical=$(cd "$repo" 2>/dev/null && pwd -P)
if [ -z "$physical" ]; then
  echo "${p}REPOSITORY=MISSING"
  finish
fi
if ! git -C "$physical" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "${p}REPOSITORY=NOT_GIT"
  finish
fi
top=$(git -C "$physical" rev-parse --show-toplevel 2>/dev/null)
if [ "$top" != "$physical" ]; then
  echo "${p}REPOSITORY=NOT_GIT"
  finish
fi
echo "${p}REPOSITORY=READY"
echo "${p}ORIGIN=$(git -C "$physical" remote get-url origin 2>/dev/null)"
echo "${p}BRANCH=$(git -C "$physical" branch --show-current 2>/dev/null)"
head=$(git -C "$physical" rev-parse HEAD 2>/dev/null)
echo "${p}HEAD=$head"
if [ -z "$head" ]; then
  relation=UNKNOWN_OBJECT
elif [ "$head" = "$expected" ]; then
  relation=EQUAL
elif ! git -C "$physical" cat-file -e "${expected}^{commit}" >/dev/null 2>&1; then
  relation=UNKNOWN_OBJECT
elif git -C "$physical" merge-base --is-ancestor "$expected" "$head" >/dev/null 2>&1; then
  relation=AHEAD
elif git -C "$physical" merge-base --is-ancestor "$head" "$expected" >/dev/null 2>&1; then
  relation=BEHIND
else
  relation=DIVERGED
fi
echo "${p}COMMIT_RELATION=$relation"
if status=$(git -C "$physical" status --porcelain 2>/dev/null); then
  if [ -n "$status" ]; then
    echo "${p}WORKTREE=DIRTY"
  else
    echo "${p}WORKTREE=CLEAN"
  fi
else
  echo "${p}WORKTREE=UNKNOWN"
fi
case "$entry" in
  /*) entrypoint="$entry" ;;
  *) entrypoint="$physical/$entry" ;;
esac
if [ ! -e "$entrypoint" ]; then
  echo "${p}ENTRYPOINT=MISSING"
elif [ ! -f "$entrypoint" ] || [ ! -x "$entrypoint" ]; then
  echo "${p}ENTRYPOINT=NOT_EXECUTABLE"
else
  echo "${p}ENTRYPOINT=PRESENT"
fi
finish
CBS_REMOTE_PROBE_EOF
readonly CBS_REMOTE_PROBE_SCRIPT

# Fixed launcher. It must not contain any single quote character.
# Positional arguments:
#   PATH_PREPEND REPOSITORY EXPECTED_ORIGIN EXPECTED_BRANCH EXPECTED_COMMIT
#   ENTRYPOINT [ARGUMENT...]
#
# The launcher re-validates the remote repository in the same SSH session,
# immediately before exec, with the same observations as the probe: Git
# availability, repository identity and origin, branch, commit, worktree
# cleanliness and CBS entrypoint. On any difference it prints the reason and
# refuses (exit 97) without starting the entrypoint. It never repairs
# anything: no fetch, checkout, reset, clean or stash.
#
# Verdict protocol on standard output, always printed before exec:
#   CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=<branch>   (when observed)
#   CBS_REMOTE_LAUNCH_OBSERVED_COMMIT=<commit>   (when observed)
#   CBS_REMOTE_LAUNCH_REASON=<REASON>            (refusal only)
#   CBS_REMOTE_LAUNCH_PREFLIGHT=PASS|REFUSED     (always the last protocol line)
#
# The entrypoint is executed directly (exec) with its arguments as separate
# words: nothing is ever re-parsed by a shell.
read -r -d '' CBS_REMOTE_LAUNCH_SCRIPT <<'CBS_REMOTE_LAUNCH_EOF' || true
if [ -n "$1" ]; then PATH="$1:$PATH"; export PATH; fi
repo="$2"
expected_origin="$3"
expected_branch="$4"
expected_commit="$5"
entry="$6"
shift 6
p="CBS_REMOTE_LAUNCH_"
refuse() {
  echo "${p}REASON=$1"
  echo "${p}PREFLIGHT=REFUSED"
  exit 97
}
if ! command -v git >/dev/null 2>&1; then
  refuse REMOTE_GIT_UNAVAILABLE
fi
if [ ! -e "$repo" ]; then
  refuse REPOSITORY_MISSING
fi
if [ ! -d "$repo" ]; then
  refuse REPOSITORY_NOT_GIT
fi
cd "$repo" 2>/dev/null || refuse REPOSITORY_MISSING
physical=$(pwd -P)
if ! git -C "$physical" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  refuse REPOSITORY_NOT_GIT
fi
top=$(git -C "$physical" rev-parse --show-toplevel 2>/dev/null)
if [ "$top" != "$physical" ]; then
  refuse REPOSITORY_NOT_GIT
fi
origin=$(git -C "$physical" remote get-url origin 2>/dev/null)
if [ "$origin" != "$expected_origin" ]; then
  refuse REPOSITORY_ORIGIN_MISMATCH
fi
branch=$(git -C "$physical" branch --show-current 2>/dev/null)
echo "${p}OBSERVED_BRANCH=$branch"
if [ "$branch" != "$expected_branch" ]; then
  refuse BRANCH_MISMATCH
fi
head=$(git -C "$physical" rev-parse HEAD 2>/dev/null)
echo "${p}OBSERVED_COMMIT=$head"
if [ -z "$head" ]; then
  refuse PROBE_FAILED
fi
if [ "$head" != "$expected_commit" ]; then
  refuse COMMIT_MISMATCH
fi
if status=$(git -C "$physical" status --porcelain 2>/dev/null); then
  if [ -n "$status" ]; then
    refuse WORKTREE_DIRTY
  fi
else
  refuse WORKTREE_UNKNOWN
fi
case "$entry" in
  /*) entrypoint="$entry" ;;
  *) entrypoint="$physical/$entry" ;;
esac
if [ ! -f "$entrypoint" ] || [ ! -x "$entrypoint" ]; then
  refuse ENTRYPOINT_UNAVAILABLE
fi
case "$entry" in
  /*) ;;
  *) entry="./$entry" ;;
esac
echo "${p}PREFLIGHT=PASS"
exec "$entry" "$@"
CBS_REMOTE_LAUNCH_EOF
readonly CBS_REMOTE_LAUNCH_SCRIPT

# POSIX single-quote quoting, valid for sh, bash and zsh.
# Every byte, including quotes, spaces, newlines and shell metacharacters,
# is transmitted literally.
cbs_remote_quote() {
    local value="${1-}"
    local quote="'"
    local replacement="'\\''"

    # The pattern and the replacement are deliberately not quoted: with Bash
    # 3.2, quotes inside a double-quoted substitution are kept literally.
    # Neither contains a glob character or a space, so nothing else changes.
    printf "'%s'" "${value//$quote/$replacement}"
}

# Quotes every argument and joins them with single spaces.
cbs_remote_quote_join() {
    local argument
    local separator=""

    for argument in "$@"; do
        printf '%s' "$separator"
        cbs_remote_quote "$argument"
        separator=" "
    done
}

cbs_remote_ssh_is_available() {
    command -v ssh >/dev/null 2>&1
}

# Builds the fixed SSH argument vector from the loaded manifest.
cbs_remote_ssh_prepare() {
    local timeout
    local port

    timeout="$(cbs_remote_cfg_get CBS_REMOTE_SSH_CONNECT_TIMEOUT "$CBS_REMOTE_DEFAULT_CONNECT_TIMEOUT")"

    CBS_REMOTE_SSH_DESTINATION="$(cbs_remote_cfg_get CBS_REMOTE_SSH_DESTINATION)"

    CBS_REMOTE_SSH_ARGV=(
        ssh
        -T
        -n
        -o BatchMode=yes
        -o StrictHostKeyChecking=yes
        -o PasswordAuthentication=no
        -o KbdInteractiveAuthentication=no
        -o ConnectionAttempts=1
        -o "ConnectTimeout=$((10#$timeout))"
        -o ServerAliveInterval=15
        -o ServerAliveCountMax=3
        -o ClearAllForwardings=yes
        -o ForwardAgent=no
        -o ForwardX11=no
        -o PermitLocalCommand=no
    )

    if cbs_remote_cfg_has CBS_REMOTE_SSH_PORT; then
        port="$(cbs_remote_cfg_get CBS_REMOTE_SSH_PORT)"
        CBS_REMOTE_SSH_ARGV+=(-p "$((10#$port))")
    fi

    if cbs_remote_cfg_has CBS_REMOTE_SSH_IDENTITY_FILE; then
        CBS_REMOTE_SSH_ARGV+=(
            -o IdentitiesOnly=yes
            -i "$(cbs_remote_cfg_get CBS_REMOTE_SSH_IDENTITY_FILE)"
        )
    fi
}

# Remote command line for the read-only probe.
cbs_remote_probe_command() {
    local expected_commit="$1"

    printf '/bin/sh -c %s sh %s' \
        "$(cbs_remote_quote "$CBS_REMOTE_PROBE_SCRIPT")" \
        "$(cbs_remote_quote_join \
            "$(cbs_remote_cfg_get CBS_REMOTE_PATH_PREPEND)" \
            "$(cbs_remote_cfg_get CBS_REMOTE_REPOSITORY_PATH)" \
            "$expected_commit" \
            "$(cbs_remote_resolved_get ENTRYPOINT)")"
}

# Remote command line for a declared action.
# Arguments: EXPECTED_COMMIT, then the action words.
# Origin and branch come from the loaded manifest.
cbs_remote_launch_command() {
    local expected_commit="$1"

    shift

    printf '/bin/sh -c %s sh %s' \
        "$(cbs_remote_quote "$CBS_REMOTE_LAUNCH_SCRIPT")" \
        "$(cbs_remote_quote_join \
            "$(cbs_remote_cfg_get CBS_REMOTE_PATH_PREPEND)" \
            "$(cbs_remote_cfg_get CBS_REMOTE_REPOSITORY_PATH)" \
            "$(cbs_remote_cfg_get CBS_REMOTE_REPOSITORY_ORIGIN)" \
            "$(cbs_remote_cfg_get CBS_REMOTE_EXPECTED_BRANCH)" \
            "$expected_commit" \
            "$(cbs_remote_resolved_get ENTRYPOINT)" \
            "$@")"
}

# Runs a remote command and captures its standard output in
# CBS_REMOTE_SSH_STDOUT. Standard error is forwarded unchanged to the
# standard error of the caller. The exit status goes to CBS_REMOTE_SSH_RC.
cbs_remote_ssh_capture() {
    local remote_command="$1"
    local error_file
    local rc=0

    error_file="$(mktemp)" || return 1

    CBS_REMOTE_SSH_STDOUT="$(
        "${CBS_REMOTE_SSH_ARGV[@]}" \
            -- \
            "$CBS_REMOTE_SSH_DESTINATION" \
            "$remote_command" \
            2>"$error_file"
    )" || rc=$?

    cat "$error_file" >&2
    rm -f "$error_file"

    CBS_REMOTE_SSH_RC="$rc"
    return 0
}

# --- Launcher verdict ------------------------------------------------------

CBS_REMOTE_LAUNCH_PREFLIGHT="$CBS_REMOTE_LAUNCH_PREFLIGHT_NOT_REPORTED"
CBS_REMOTE_LAUNCH_REASON=""
CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=""
CBS_REMOTE_LAUNCH_OBSERVED_COMMIT=""

# Loads the verdict recorded in a state file. Only the documented keys are
# accepted, and only values of the documented shape: whatever else the remote
# host sends is ignored. The first occurrence of a key wins.
cbs_remote_launch_state_load() {
    local file="$1"
    local line
    local key
    local value
    local seen_preflight=0
    local seen_reason=0
    local seen_branch=0
    local seen_commit=0

    CBS_REMOTE_LAUNCH_PREFLIGHT="$CBS_REMOTE_LAUNCH_PREFLIGHT_NOT_REPORTED"
    CBS_REMOTE_LAUNCH_REASON=""
    CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=""
    CBS_REMOTE_LAUNCH_OBSERVED_COMMIT=""

    [[ -s "$file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^CBS_REMOTE_LAUNCH_([A-Z_]+)=(.*)$ ]] || continue

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        case "$key" in
            PREFLIGHT)
                if [[ "$seen_preflight" -eq 0 ]] &&
                    [[ "$value" == "$CBS_REMOTE_LAUNCH_PREFLIGHT_PASS" ||
                        "$value" == "$CBS_REMOTE_LAUNCH_PREFLIGHT_REFUSED" ]]
                then
                    CBS_REMOTE_LAUNCH_PREFLIGHT="$value"
                    seen_preflight=1
                fi
                ;;
            REASON)
                if [[ "$seen_reason" -eq 0 && "$value" =~ ^[A-Z_]{1,40}$ ]]; then
                    CBS_REMOTE_LAUNCH_REASON="$value"
                    seen_reason=1
                fi
                ;;
            OBSERVED_BRANCH)
                if [[ "$seen_branch" -eq 0 &&
                    ( -z "$value" || "$value" =~ $CBS_REMOTE_PATTERN_BRANCH ) ]]
                then
                    CBS_REMOTE_LAUNCH_OBSERVED_BRANCH="$value"
                    seen_branch=1
                fi
                ;;
            OBSERVED_COMMIT)
                if [[ "$seen_commit" -eq 0 &&
                    ( -z "$value" || "$value" =~ $CBS_REMOTE_PATTERN_COMMIT ) ]]
                then
                    CBS_REMOTE_LAUNCH_OBSERVED_COMMIT="$value"
                    seen_commit=1
                fi
                ;;
        esac
    done <"$file"
}

# Prints the loaded verdict as CBS_REMOTE_* lines.
cbs_remote_launch_state_print() {
    printf 'CBS_REMOTE_LAUNCH_PREFLIGHT=%s\n' "$CBS_REMOTE_LAUNCH_PREFLIGHT"

    if [[ "$CBS_REMOTE_LAUNCH_PREFLIGHT" == "$CBS_REMOTE_LAUNCH_PREFLIGHT_NOT_REPORTED" ]]; then
        return 0
    fi

    printf 'CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=%s\n' \
        "${CBS_REMOTE_LAUNCH_OBSERVED_BRANCH:-DETACHED}"
    printf 'CBS_REMOTE_LAUNCH_OBSERVED_COMMIT=%s\n' \
        "${CBS_REMOTE_LAUNCH_OBSERVED_COMMIT:-NONE}"

    if [[ "$CBS_REMOTE_LAUNCH_PREFLIGHT" == "$CBS_REMOTE_LAUNCH_PREFLIGHT_REFUSED" ]]; then
        printf 'CBS_REMOTE_LAUNCH_REFUSAL=%s\n' "${CBS_REMOTE_LAUNCH_REASON:-UNKNOWN}"
    fi
}

# Standard-output filter of the launch session.
#
# Everything before the launcher verdict line is forwarded unchanged, except
# the launcher protocol lines, which are recorded in the state file given as
# argument. The verdict line closes the protocol: the filter then reports the
# verdict, announces the action when it passed, and forwards the rest of the
# stream byte for byte, so nothing the action prints can be taken for a
# verdict. The verdict is printed before the action output.
cbs_remote_launch_filter() {
    local state_file="$1"
    local line
    local closed=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^CBS_REMOTE_LAUNCH_[A-Z_]+=.*$ ]]; then
            printf '%s\n' "$line" >>"$state_file"

            if [[ "$line" == "CBS_REMOTE_LAUNCH_PREFLIGHT=$CBS_REMOTE_LAUNCH_PREFLIGHT_PASS" ||
                "$line" == "CBS_REMOTE_LAUNCH_PREFLIGHT=$CBS_REMOTE_LAUNCH_PREFLIGHT_REFUSED" ]]
            then
                closed=1
                break
            fi
        else
            printf '%s\n' "$line"
        fi
    done

    if [[ "$closed" -eq 1 ]]; then
        cbs_remote_launch_state_load "$state_file"
        cbs_remote_launch_state_print

        if [[ "$CBS_REMOTE_LAUNCH_PREFLIGHT" == "$CBS_REMOTE_LAUNCH_PREFLIGHT_PASS" ]]; then
            echo "CBS_REMOTE_ACTION_EXECUTION=START"
        fi

        cat
    fi
}

# Runs the launch command. Standard error is forwarded unchanged; standard
# output goes through cbs_remote_launch_filter. Results:
#   CBS_REMOTE_SSH_RC                    exit status of ssh
#   CBS_REMOTE_LAUNCH_PREFLIGHT, _REASON, _OBSERVED_BRANCH, _OBSERVED_COMMIT
# Returns 1 only when the local state file cannot be created (nothing was
# started).
cbs_remote_ssh_stream_launch() {
    local remote_command="$1"
    local state_file
    local -a statuses=(0 0)

    state_file="$(mktemp)" || return 1

    "${CBS_REMOTE_SSH_ARGV[@]}" \
        -- \
        "$CBS_REMOTE_SSH_DESTINATION" \
        "$remote_command" |
        cbs_remote_launch_filter "$state_file" ||
        statuses=("${PIPESTATUS[@]}")

    CBS_REMOTE_SSH_RC="${statuses[0]}"

    cbs_remote_launch_state_load "$state_file"
    rm -f "$state_file"

    return 0
}
