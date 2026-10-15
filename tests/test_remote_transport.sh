#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/tests/fixtures/remote/lib.sh"
source "$ROOT/cbs/remote/remote_verifier.sh"

REMOTE_TEST_PREFIX="TEST_REMOTE_TRANSPORT"

# --- quoting: every value must survive a round trip through a remote shell

HOSTILE=(
    ""
    " "
    "plain"
    "with space"
    "  leading and trailing  "
    "single'quote"
    "'"
    "''"
    'double"quote'
    '$(touch PWNED)'
    '`touch PWNED`'
    '$HOME'
    '${HOME}'
    'a;touch PWNED'
    'a && touch PWNED'
    'a | touch PWNED'
    'a > PWNED'
    'a < /etc/hostname'
    '*'
    '?'
    '[a-z]*'
    '~'
    '~root'
    '-n'
    '--help'
    '\\'
    'back\slash'
    '!'
    '%s%d'
    '#comment'
    'tab	inside'
    $'line1\nline2'
    $'trailing newline\n'
    'ünïcödé ✓'
    '}{'
    ')('
    "'; touch PWNED; echo '"
    '"; touch PWNED; echo "'
)

SHELLS=(/bin/sh bash)

if command -v dash >/dev/null 2>&1; then
    SHELLS+=(dash)
fi

if command -v zsh >/dev/null 2>&1; then
    SHELLS+=(zsh)
else
    echo "TEST_REMOTE_TRANSPORT_ZSH=SKIPPED_NOT_INSTALLED"
fi

WORK="$TMP/quote-work"
mkdir -p "$WORK"

for shell in "${SHELLS[@]}"; do
    for value in "${HOSTILE[@]}"; do
        quoted="$(cbs_remote_quote "$value")"

        # The remote shell receives the quoted text as a single word.
        got="$(
            cd "$WORK"
            "$shell" -c "printf '%s' $quoted"
            printf x
        )"
        got="${got%x}"

        [[ "$got" == "$value" ]] ||
            remote_test_fail "QUOTE_ROUNDTRIP:$shell:$(printf '%q' "$value")"
    done

    # Joined arguments keep their boundaries.
    joined="$(cbs_remote_quote_join "${HOSTILE[@]}")"

    got="$(
        cd "$WORK"
        "$shell" -c "printf '[%s]' $joined"
        printf x
    )"
    got="${got%x}"

    expected=""
    for value in "${HOSTILE[@]}"; do
        expected+="[$value]"
    done

    [[ "$got" == "$expected" ]] ||
        remote_test_fail "QUOTE_JOIN_ROUNDTRIP:$shell"

    argument_count="$(
        cd "$WORK"
        "$shell" -c "set -- $joined; printf '%s' \"\$#\""
    )"

    [[ "$argument_count" -eq "${#HOSTILE[@]}" ]] ||
        remote_test_fail "QUOTE_JOIN_COUNT:$shell:$argument_count"

    [[ -z "$(ls -A "$WORK")" ]] ||
        remote_test_fail "QUOTE_SIDE_EFFECT:$shell:$(ls -A "$WORK")"
done

echo "TEST_REMOTE_TRANSPORT_QUOTING=PASS"

# --- the fixed remote scripts must stay quotable and shell-neutral

[[ "$CBS_REMOTE_PROBE_SCRIPT" != *"'"* ]] ||
    remote_test_fail "PROBE_SCRIPT_CONTAINS_SINGLE_QUOTE"

[[ "$CBS_REMOTE_LAUNCH_SCRIPT" != *"'"* ]] ||
    remote_test_fail "LAUNCH_SCRIPT_CONTAINS_SINGLE_QUOTE"

[[ -n "$CBS_REMOTE_PROBE_SCRIPT" && -n "$CBS_REMOTE_LAUNCH_SCRIPT" ]] ||
    remote_test_fail "FIXED_SCRIPT_EMPTY"

echo "TEST_REMOTE_TRANSPORT_FIXED_SCRIPTS=PASS"

# --- launcher: revalidation precedes exec, in the same session

# The launcher never mutates the remote repository.
if grep -Eq 'git[^|;]*[[:space:]](fetch|pull|push|clone|checkout|switch|restore|reset|clean|stash|commit|merge|rebase|gc|prune|add|rm|mv|config|init|worktree)([[:space:]]|$)' <<<"$CBS_REMOTE_LAUNCH_SCRIPT"; then
    remote_test_fail "LAUNCHER_CONTAINS_MUTATING_GIT_COMMAND"
fi

# It observes everything the probe observes.
for needle in \
    'rev-parse --is-inside-work-tree' \
    'rev-parse --show-toplevel' \
    'remote get-url origin' \
    'branch --show-current' \
    'rev-parse HEAD' \
    'status --porcelain' \
    'refuse REPOSITORY_MISSING' \
    'refuse REPOSITORY_NOT_GIT' \
    'refuse REPOSITORY_ORIGIN_MISMATCH' \
    'refuse BRANCH_MISMATCH' \
    'refuse COMMIT_MISMATCH' \
    'refuse WORKTREE_DIRTY' \
    'refuse WORKTREE_UNKNOWN' \
    'refuse ENTRYPOINT_UNAVAILABLE' \
    'refuse REMOTE_GIT_UNAVAILABLE'
do
    [[ "$CBS_REMOTE_LAUNCH_SCRIPT" == *"$needle"* ]] ||
        remote_test_fail "LAUNCHER_LACKS:$needle"
done

# exec appears once, and nothing but the verdict line sits between the last
# check and exec.
[[ "$(grep -c '^exec ' <<<"$CBS_REMOTE_LAUNCH_SCRIPT")" -eq 1 ]] ||
    remote_test_fail "LAUNCHER_EXEC_COUNT"

LAST_TWO="$(tail -n 2 <<<"$CBS_REMOTE_LAUNCH_SCRIPT")"
[[ "$LAST_TWO" == $'echo "${p}PREFLIGHT=PASS"\nexec "$entry" "$@"' ]] ||
    remote_test_fail "LAUNCHER_PASS_NOT_IMMEDIATELY_BEFORE_EXEC"

# The probe is read-only and does not execute anything.
if grep -q 'exec ' <<<"$CBS_REMOTE_PROBE_SCRIPT"; then
    remote_test_fail "PROBE_EXECUTES_SOMETHING"
fi

echo "TEST_REMOTE_TRANSPORT_LAUNCHER_STRUCTURE=PASS"

# The launcher, executed by every available remote shell, in one session.
for shell in "${SHELLS[@]}"; do
    remote_test_scenario
    remote_test_write_manifest "$MANIFEST"
    cbs_remote_manifest_load "$MANIFEST"
    remote_test_arm_marker

    LAUNCH="$(cbs_remote_launch_command "$REMOTE_TEST_HEAD" version)"

    remote_test_run "$shell" -c "$LAUNCH"
    remote_test_expect_rc 0 "LAUNCHER_PASS:$shell"
    remote_test_expect_out "CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=main" "LAUNCHER_PASS:$shell"
    remote_test_expect_out "CBS_REMOTE_LAUNCH_OBSERVED_COMMIT=$REMOTE_TEST_HEAD" "LAUNCHER_PASS:$shell"
    remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=PASS" "LAUNCHER_PASS:$shell"
    remote_test_expect_out "FIXTURE_CBS_ARG_0=version" "LAUNCHER_PASS:$shell"
    remote_test_marker_present || remote_test_fail "LAUNCHER_PASS_NOT_EXECUTED:$shell"

    # Wrong expected commit: refusal, rc 97, entrypoint not started.
    remote_test_arm_marker
    WRONG="0000000000000000000000000000000000000001"
    remote_test_run "$shell" -c "$(cbs_remote_launch_command "$WRONG" version)"
    remote_test_expect_rc 97 "LAUNCHER_REFUSES_COMMIT:$shell"
    remote_test_expect_out "CBS_REMOTE_LAUNCH_REASON=COMMIT_MISMATCH" "LAUNCHER_REFUSES_COMMIT:$shell"
    remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED" "LAUNCHER_REFUSES_COMMIT:$shell"
    if remote_test_marker_present || grep -q 'FIXTURE_CBS_' <<<"$OUT"; then
        remote_test_fail "LAUNCHER_REFUSAL_EXECUTED:$shell"
    fi

    # Dirty worktree: refusal, nothing removed.
    printf 'x\n' > "$REMOTE_TEST_REMOTE/dirty.txt"
    remote_test_run "$shell" -c "$LAUNCH"
    remote_test_expect_rc 97 "LAUNCHER_REFUSES_DIRTY:$shell"
    remote_test_expect_out "CBS_REMOTE_LAUNCH_REASON=WORKTREE_DIRTY" "LAUNCHER_REFUSES_DIRTY:$shell"
    [[ -f "$REMOTE_TEST_REMOTE/dirty.txt" ]] ||
        remote_test_fail "LAUNCHER_REMOVED_FILE:$shell"
    rm -f "$REMOTE_TEST_REMOTE/dirty.txt"

    # The verdict line is the last protocol line, always before the action.
    remote_test_run "$shell" -c "$LAUNCH"
    FIRST_LAUNCH_LINE="$(grep -n '^CBS_REMOTE_LAUNCH_PREFLIGHT=' <<<"$OUT" | cut -d: -f1)"
    FIRST_ACTION_LINE="$(grep -n '^FIXTURE_CBS_' <<<"$OUT" | head -n 1 | cut -d: -f1)"
    [[ "$FIRST_LAUNCH_LINE" -lt "$FIRST_ACTION_LINE" ]] ||
        remote_test_fail "LAUNCHER_VERDICT_AFTER_ACTION:$shell"
done

echo "TEST_REMOTE_TRANSPORT_LAUNCHER_EXECUTION=PASS"

# --- launcher verdict filter (standard output of the launch session)

FILTER_STATE="$TMP/filter-state"

run_filter() {
    rm -f "$FILTER_STATE"
    : > "$FILTER_STATE"
    OUT="$(printf '%b' "$1" | cbs_remote_launch_filter "$FILTER_STATE"; printf x)"
    OUT="${OUT%x}"
}

# Passing verdict: protocol consumed, verdict reported, action announced.
run_filter 'CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=main\nCBS_REMOTE_LAUNCH_OBSERVED_COMMIT=0123456789abcdef0123456789abcdef01234567\nCBS_REMOTE_LAUNCH_PREFLIGHT=PASS\naction line 1\naction line 2\n'
EXPECTED=$'CBS_REMOTE_LAUNCH_PREFLIGHT=PASS\nCBS_REMOTE_LAUNCH_OBSERVED_BRANCH=main\nCBS_REMOTE_LAUNCH_OBSERVED_COMMIT=0123456789abcdef0123456789abcdef01234567\nCBS_REMOTE_ACTION_EXECUTION=START\naction line 1\naction line 2\n'
[[ "$OUT" == "$EXPECTED" ]] || remote_test_fail "FILTER_PASS:$(printf '%q' "$OUT")"

# After the verdict the stream is forwarded byte for byte, forged protocol
# lines, missing final newline and carriage returns included.
run_filter 'CBS_REMOTE_LAUNCH_PREFLIGHT=PASS\nCBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED\nCBS_REMOTE_LAUNCH_REASON=WORKTREE_DIRTY\r\npartial'
[[ "$OUT" == *$'CBS_REMOTE_ACTION_EXECUTION=START\nCBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED\nCBS_REMOTE_LAUNCH_REASON=WORKTREE_DIRTY\r\npartial' ]] ||
    remote_test_fail "FILTER_FORWARDS_BYTES:$(printf '%q' "$OUT")"
cbs_remote_launch_state_load "$FILTER_STATE"
[[ "$CBS_REMOTE_LAUNCH_PREFLIGHT" == "PASS" ]] ||
    remote_test_fail "FILTER_FORGED_VERDICT_APPLIED"
[[ -z "$CBS_REMOTE_LAUNCH_REASON" ]] ||
    remote_test_fail "FILTER_FORGED_REASON_APPLIED"

# Refusal: reported, never announced as started, nothing else forwarded.
run_filter 'CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=feature\nCBS_REMOTE_LAUNCH_REASON=BRANCH_MISMATCH\nCBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED\n'
EXPECTED=$'CBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED\nCBS_REMOTE_LAUNCH_OBSERVED_BRANCH=feature\nCBS_REMOTE_LAUNCH_OBSERVED_COMMIT=NONE\nCBS_REMOTE_LAUNCH_REFUSAL=BRANCH_MISMATCH\n'
[[ "$OUT" == "$EXPECTED" ]] || remote_test_fail "FILTER_REFUSED:$(printf '%q' "$OUT")"

# Unexpected output before the verdict is forwarded and ignored as protocol.
run_filter 'login banner\nCBS_REMOTE_LAUNCH_PREFLIGHT=PASS\nok\n'
[[ "$OUT" == $'login banner\nCBS_REMOTE_LAUNCH_PREFLIGHT=PASS\nCBS_REMOTE_LAUNCH_OBSERVED_BRANCH=DETACHED\nCBS_REMOTE_LAUNCH_OBSERVED_COMMIT=NONE\nCBS_REMOTE_ACTION_EXECUTION=START\nok\n' ]] ||
    remote_test_fail "FILTER_BANNER:$(printf '%q' "$OUT")"

# No verdict at all: everything is forwarded, nothing is announced.
run_filter 'plain output\nCBS_REMOTE_LAUNCH_OBSERVED_BRANCH=main\n'
[[ "$OUT" == $'plain output\n' ]] || remote_test_fail "FILTER_NO_VERDICT:$(printf '%q' "$OUT")"
cbs_remote_launch_state_load "$FILTER_STATE"
[[ "$CBS_REMOTE_LAUNCH_PREFLIGHT" == "NOT_REPORTED" ]] ||
    remote_test_fail "FILTER_NO_VERDICT_STATE"

# Values outside the documented shape are ignored.
run_filter 'CBS_REMOTE_LAUNCH_OBSERVED_BRANCH=ma in;$(id)\nCBS_REMOTE_LAUNCH_OBSERVED_COMMIT=nothex\nCBS_REMOTE_LAUNCH_REASON=lower case\nCBS_REMOTE_LAUNCH_PREFLIGHT=MAYBE\nCBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED\n'
cbs_remote_launch_state_load "$FILTER_STATE"
[[ "$CBS_REMOTE_LAUNCH_PREFLIGHT" == "REFUSED" ]] ||
    remote_test_fail "FILTER_SANITIZE_PREFLIGHT"
[[ -z "$CBS_REMOTE_LAUNCH_OBSERVED_BRANCH" && -z "$CBS_REMOTE_LAUNCH_OBSERVED_COMMIT" && -z "$CBS_REMOTE_LAUNCH_REASON" ]] ||
    remote_test_fail "FILTER_SANITIZE_VALUES"

echo "TEST_REMOTE_TRANSPORT_LAUNCH_FILTER=PASS"

# The launch stream keeps the ssh status and the action output.
remote_test_scenario
remote_test_write_manifest "$MANIFEST"
cbs_remote_manifest_load "$MANIFEST"
cbs_remote_ssh_prepare
# Called without a subshell: its results are variables.
cbs_remote_ssh_stream_launch "$(cbs_remote_launch_command "$REMOTE_TEST_HEAD" version)" >/dev/null
[[ "$CBS_REMOTE_SSH_RC" -eq 0 ]] ||
    remote_test_fail "STREAM_LAUNCH_RC_0_GOT_$CBS_REMOTE_SSH_RC"
[[ "$CBS_REMOTE_LAUNCH_PREFLIGHT" == "PASS" ]] ||
    remote_test_fail "STREAM_LAUNCH_VERDICT"

export FIXTURE_CBS_FORCE_EXIT=9
cbs_remote_ssh_stream_launch "$(cbs_remote_launch_command "$REMOTE_TEST_HEAD" version)" >/dev/null
unset FIXTURE_CBS_FORCE_EXIT
[[ "$CBS_REMOTE_SSH_RC" -eq 9 ]] ||
    remote_test_fail "STREAM_LAUNCH_RC_9_GOT_$CBS_REMOTE_SSH_RC"

export FAKE_SSH_MODE=unreachable
cbs_remote_ssh_stream_launch "$(cbs_remote_launch_command "$REMOTE_TEST_HEAD" version)" >/dev/null 2>&1
unset FAKE_SSH_MODE
[[ "$CBS_REMOTE_SSH_RC" -eq 255 && "$CBS_REMOTE_LAUNCH_PREFLIGHT" == "NOT_REPORTED" ]] ||
    remote_test_fail "STREAM_LAUNCH_255_NO_VERDICT"

echo "TEST_REMOTE_TRANSPORT_LAUNCH_STREAM=PASS"

# --- SSH invocation contract

remote_test_scenario
remote_test_write_manifest "$MANIFEST"
cbs_remote_manifest_load "$MANIFEST"
cbs_remote_ssh_prepare

OPTIONS="$(printf '%s\n' "${CBS_REMOTE_SSH_ARGV[@]}")"

for expected in \
    "ssh" \
    "-T" \
    "-n" \
    "BatchMode=yes" \
    "StrictHostKeyChecking=yes" \
    "PasswordAuthentication=no" \
    "KbdInteractiveAuthentication=no" \
    "ConnectionAttempts=1" \
    "ConnectTimeout=10" \
    "ClearAllForwardings=yes" \
    "ForwardAgent=no" \
    "ForwardX11=no" \
    "PermitLocalCommand=no"
do
    grep -Fxq -- "$expected" <<<"$OPTIONS" ||
        remote_test_fail "SSH_OPTION_MISSING:$expected"
done

for forbidden in "-t" "-tt" "-A" "-X" "-Y" "-L" "-R" "-D" "-W" "-i" "-p"; do
    if grep -Fxq -- "$forbidden" <<<"$OPTIONS"; then
        remote_test_fail "SSH_OPTION_UNEXPECTED:$forbidden"
    fi
done

[[ "$CBS_REMOTE_SSH_DESTINATION" == "$REMOTE_TEST_DESTINATION" ]] ||
    remote_test_fail "SSH_DESTINATION"

echo "TEST_REMOTE_TRANSPORT_SSH_OPTIONS=PASS"

# Optional port, timeout and identity file are passed as separate words.
remote_test_scenario
M_EXTRA=$'CBS_REMOTE_SSH_PORT=2222\nCBS_REMOTE_SSH_CONNECT_TIMEOUT=5\nCBS_REMOTE_SSH_IDENTITY_FILE=/home/u/my keys/id_fixture'
remote_test_write_manifest "$MANIFEST"
cbs_remote_manifest_load "$MANIFEST"
cbs_remote_ssh_prepare

OPTIONS="$(printf '%s\n' "${CBS_REMOTE_SSH_ARGV[@]}")"

grep -Fxq -- "-p" <<<"$OPTIONS" || remote_test_fail "SSH_PORT_FLAG"
grep -Fxq -- "2222" <<<"$OPTIONS" || remote_test_fail "SSH_PORT_VALUE"
grep -Fxq -- "ConnectTimeout=5" <<<"$OPTIONS" || remote_test_fail "SSH_TIMEOUT"
grep -Fxq -- "-i" <<<"$OPTIONS" || remote_test_fail "SSH_IDENTITY_FLAG"
grep -Fxq -- "/home/u/my keys/id_fixture" <<<"$OPTIONS" || remote_test_fail "SSH_IDENTITY_VALUE"
grep -Fxq -- "IdentitiesOnly=yes" <<<"$OPTIONS" || remote_test_fail "SSH_IDENTITIES_ONLY"

echo "TEST_REMOTE_TRANSPORT_SSH_OPTIONAL_OPTIONS=PASS"

# What the simulated ssh actually receives through the real CLI: BatchMode,
# option terminator, destination and exactly one remote command word.
remote_test_scenario
remote_test_write_manifest "$MANIFEST"
remote_test_run "$ROOT/bin/cbs" remote check "$MANIFEST"
remote_test_expect_rc 0 "SSH_RECEIVED_CHECK"

[[ "$(cat "$FAKE_SSH_STATE/destination.1")" == "$REMOTE_TEST_DESTINATION" ]] ||
    remote_test_fail "SSH_RECEIVED_DESTINATION"

grep -Fxq 'BatchMode=yes' "$FAKE_SSH_STATE/options.1" ||
    remote_test_fail "SSH_RECEIVED_BATCHMODE"

[[ "$(cat "$FAKE_SSH_STATE/command.1")" == "/bin/sh -c '"* ]] ||
    remote_test_fail "SSH_RECEIVED_COMMAND_SHAPE"

# The repository path (which contains a space) is a single quoted word.
grep -Fq "'$REMOTE_TEST_REMOTE'" "$FAKE_SSH_STATE/command.1" ||
    remote_test_fail "SSH_RECEIVED_QUOTED_REPOSITORY_PATH"

echo "TEST_REMOTE_TRANSPORT_SSH_RECEIVED=PASS"

# --- the simulated ssh itself refuses a caller that forgets BatchMode

set +e
FAKE_SSH_STATE="$TMP/guard-state" ssh -T -o StrictHostKeyChecking=yes -- host 'true' >/dev/null 2>&1
GUARD_RC=$?
set -e

[[ "$GUARD_RC" -eq 97 ]] ||
    remote_test_fail "SIMULATOR_ACCEPTED_MISSING_BATCHMODE_RC_$GUARD_RC"

echo "TEST_REMOTE_TRANSPORT_SIMULATOR_GUARD=PASS"

# --- no real ssh was ever used by these tests

[[ "$(command -v ssh)" == "$REMOTE_TEST_LIB_DIR/bin/ssh" ]] ||
    remote_test_fail "REAL_SSH_REACHABLE_FIRST"

echo "TEST_REMOTE_TRANSPORT_HERMETIC=PASS"

echo "TEST_REMOTE_TRANSPORT_RESULT=PASS"
