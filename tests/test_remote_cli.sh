#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/tests/fixtures/remote/lib.sh"
source "$ROOT/cbs/remote/contract.sh"

REMOTE_TEST_PREFIX="TEST_REMOTE_CLI"

# --- help exposure

HELP="$("$CBS" help)"

for expected in \
    'cbs remote check <manifest>' \
    'cbs remote run <manifest> <action>'
do
    grep -Fq "$expected" <<<"$HELP" ||
        remote_test_fail "HELP_MISSING:$expected"
done

# Nothing that would allow a free-form remote command is advertised.
for forbidden in \
    'cbs remote exec' \
    'cbs remote shell' \
    'cbs remote ssh' \
    'cbs remote sync' \
    'cbs remote deploy'
do
    if grep -Fq "$forbidden" <<<"$HELP"; then
        remote_test_fail "HELP_ADVERTISES:$forbidden"
    fi
done

echo "TEST_REMOTE_CLI_HELP=PASS"

# --- command routing

remote_test_scenario
remote_test_write_manifest "$MANIFEST"

remote_test_run "$CBS" remote check "$MANIFEST"
remote_test_expect_rc 0 "CHECK_ROUTING"
remote_test_expect_out "CBS_REMOTE_OPERATION=check" "CHECK_ROUTING"
remote_test_expect_out "CBS_REMOTE_RESULT=PASS" "CHECK_ROUTING"

remote_test_run "$CBS" remote run "$MANIFEST" show_version
remote_test_expect_rc 0 "RUN_ROUTING"
remote_test_expect_out "CBS_REMOTE_OPERATION=run" "RUN_ROUTING"
remote_test_expect_out "CBS_REMOTE_RESULT=PASS" "RUN_ROUTING"

# The CLI propagates the remote return code unchanged.
remote_test_run "$CBS" remote run "$MANIFEST" show_fail
remote_test_expect_rc 7 "RUN_RC_PROPAGATION"
remote_test_expect_out "CBS_REMOTE_RESULT=FAIL" "RUN_RC_PROPAGATION"

echo "TEST_REMOTE_CLI_ROUTING=PASS"

# A refusal by the launcher (remote change after the probe) goes through the
# CLI with the same result and return code as the initial verification.
remote_test_scenario
remote_test_write_manifest "$MANIFEST"
HOOK_REPO="$REMOTE_TEST_REMOTE"
export HOOK_REPO
export FAKE_SSH_HOOK_ON_CALL=2
export FAKE_SSH_HOOK='printf "late\n" > "$HOOK_REPO/late.txt"'
remote_test_arm_marker

remote_test_run "$CBS" remote run "$MANIFEST" show_version
remote_test_expect_rc "$CBS_RC_REMOTE_WORKTREE_DIRTY" "RUN_LAUNCHER_REFUSAL"
remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "RUN_LAUNCHER_REFUSAL"
remote_test_expect_out "CBS_REMOTE_REASON=WORKTREE_DIRTY" "RUN_LAUNCHER_REFUSAL"
remote_test_expect_out "CBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED" "RUN_LAUNCHER_REFUSAL"
remote_test_expect_no_out "CBS_REMOTE_ACTION_EXECUTION=START" "RUN_LAUNCHER_REFUSAL"
if remote_test_marker_present; then
    remote_test_fail "RUN_LAUNCHER_REFUSAL:ENTRYPOINT_WAS_STARTED"
fi
unset FAKE_SSH_HOOK_ON_CALL FAKE_SSH_HOOK

# Mutating operations cannot be bound to a remote action through the CLI:
# the manifest is refused before any SSH session.
for mutating in \
    "stack toolchains ensure stacks/flutter/stack.env" \
    "platform start platforms/x/platform.env" \
    "platform stop platforms/x/platform.env" \
    "runtime android ensure"
do
    remote_test_scenario
    M_ALLOWED="mutating"
    M_EXTRA="CBS_REMOTE_ACTION_MUTATING_COMMAND=$mutating"
    remote_test_write_manifest "$MANIFEST"
    remote_test_sed_inplace '/^CBS_REMOTE_ACTION_SHOW_/d' "$MANIFEST"

    remote_test_run "$CBS" remote run "$MANIFEST" mutating
    remote_test_expect_rc "$CBS_RC_REMOTE_MANIFEST_INVALID" "MUTATING_REFUSED:$mutating"
    remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "MUTATING_REFUSED:$mutating"
    remote_test_expect_out "CBS_REMOTE_REASON=MANIFEST_INVALID" "MUTATING_REFUSED:$mutating"
    remote_test_expect_err "CBS_REMOTE_MANIFEST_ERROR=COMMAND_NOT_ALLOWED" "MUTATING_REFUSED:$mutating"
    remote_test_expect_ssh_count 0 "MUTATING_REFUSED_NO_NETWORK:$mutating"
done

echo "TEST_REMOTE_CLI_REFUSALS=PASS"

# --- unknown commands

SSH_COUNT_BEFORE_UNKNOWN="$(remote_test_ssh_count)"

remote_test_run "$CBS" remote
remote_test_expect_rc 2 "REMOTE_WITHOUT_SUBCOMMAND"
remote_test_expect_err "CBS_ERROR=UNKNOWN_REMOTE_COMMAND" "REMOTE_WITHOUT_SUBCOMMAND"

for unknown in deploy exec shell ssh sync status; do
    remote_test_run "$CBS" remote "$unknown" "$MANIFEST"
    remote_test_expect_rc 2 "UNKNOWN_$unknown"
    remote_test_expect_err "CBS_ERROR=UNKNOWN_REMOTE_COMMAND" "UNKNOWN_$unknown"
    remote_test_expect_err "CBS_COMMAND=$unknown" "UNKNOWN_$unknown"
done

remote_test_expect_ssh_count "$SSH_COUNT_BEFORE_UNKNOWN" "UNKNOWN_COMMANDS_NO_NETWORK"

echo "TEST_REMOTE_CLI_UNKNOWN_COMMANDS=PASS"

# --- usage

remote_test_run "$CBS" remote check
remote_test_expect_rc "$CBS_RC_REMOTE_USAGE" "CHECK_USAGE"
remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "CHECK_USAGE"
remote_test_expect_out "CBS_REMOTE_REASON=USAGE" "CHECK_USAGE"

remote_test_run "$CBS" remote run "$MANIFEST"
remote_test_expect_rc "$CBS_RC_REMOTE_USAGE" "RUN_USAGE"
remote_test_expect_out "CBS_REMOTE_RESULT=BLOCKED" "RUN_USAGE"

echo "TEST_REMOTE_CLI_USAGE=PASS"

# --- existing commands are unaffected by the extension

for existing in \
    "version" \
    "help" \
    "--version"
do
    remote_test_run "$CBS" $existing
    remote_test_expect_rc 0 "EXISTING_$existing"
done

remote_test_run "$CBS" platform bogus
remote_test_expect_rc 2 "EXISTING_UNKNOWN_PLATFORM_COMMAND"
remote_test_expect_err "CBS_ERROR=UNKNOWN_PLATFORM_COMMAND" "EXISTING_UNKNOWN_PLATFORM_COMMAND"

remote_test_run "$CBS" does-not-exist
remote_test_expect_rc 2 "EXISTING_UNKNOWN_COMMAND"
remote_test_expect_err "CBS_ERROR=UNKNOWN_COMMAND" "EXISTING_UNKNOWN_COMMAND"

for command in \
    "workspace check" \
    "repository ensure" \
    "worktree check" \
    "stack resolve" \
    "instance check" \
    "platform resolve"
do
    # shellcheck disable=SC2086
    if ! grep -Fq "cbs $command" <<<"$HELP"; then
        remote_test_fail "EXISTING_HELP_LOST:$command"
    fi
done

echo "TEST_REMOTE_CLI_EXISTING_COMMANDS=PASS"

# --- structural guarantees of the implementation

# No dynamic evaluation anywhere in the component.
if grep -RnE '(^|[^A-Za-z_])eval([^A-Za-z_]|$)' "$ROOT/cbs/remote" "$ROOT/bin/cbs"; then
    remote_test_fail "EVAL_USED"
fi

# The manifest is parsed, never sourced.
if grep -RnE '^[[:space:]]*(source|\.)[[:space:]]+"?\$\{?(manifest|1|file)' "$ROOT/cbs/remote"; then
    remote_test_fail "MANIFEST_IS_SOURCED"
fi

# No shell is ever started with user-controlled text.
if grep -RnE 'bash -c|sh -c "\$' "$ROOT/cbs/remote"; then
    remote_test_fail "DYNAMIC_SHELL_INVOCATION"
fi

# SSH never falls back to an interactive mode.
grep -Fq 'BatchMode=yes' "$ROOT/cbs/remote/remote_transport.sh" ||
    remote_test_fail "BATCHMODE_NOT_ENFORCED"

# No implicit Git synchronisation or destructive Git operation.
if grep -RnE 'git[^|;&]*[[:space:]](fetch|pull|push|clone|checkout|switch|reset|clean|merge|rebase|stash|commit|restore|rm)([[:space:]]|$)' "$ROOT/cbs/remote"; then
    remote_test_fail "GIT_MUTATION_OR_SYNCHRONISATION"
fi

if grep -RnE '(^|[[:space:]])rm[[:space:]]+-[A-Za-z]*[rR]' "$ROOT/cbs/remote"; then
    remote_test_fail "DESTRUCTIVE_DELETE"
fi

# Bash 3.2 and BSD tool compatibility (macOS): none of the Bash 4+ or GNU-only
# constructs below (associative arrays, the global flag of declare, namerefs,
# case conversion expansions, array-reading builtins, in-place sed) may appear
# in the component, its fixtures or its tests. The patterns are written so that
# they do not match their own text.
PORTABILITY_TARGETS=("$ROOT/cbs/remote" "$ROOT/tests/fixtures/remote")

for portability_test in "$ROOT"/tests/test_remote_*.sh; do
    PORTABILITY_TARGETS+=("$portability_test")
done

if grep -RnE -e 'declare -[a-zA-Z]*[Agn]([[:space:]]|$)' \
    -e 'typeset -[a-zA-Z]*[Agn]([[:space:]]|$)' \
    -e 'local -[a-zA-Z]*[An]([[:space:]]|$)' \
    -e 'readonly -[a-zA-Z]*A' \
    -e '\$\{[^}]*(\^\^|,,)[^}]*\}' \
    -e '\$\{[A-Za-z_][A-Za-z0-9_]*[\^,][^}]*\}' \
    -e '(^|[^A-Za-z_])(map''file|read''array)([^A-Za-z_]|$)' \
    -e 'sed -[a-zA-Z]*i' \
    -e '\[\[ -v ' \
    -e '&>''>|\|''&' \
    "${PORTABILITY_TARGETS[@]}"
then
    remote_test_fail "BASH_4_OR_GNU_ONLY_CONSTRUCT"
fi

echo "TEST_REMOTE_CLI_STRUCTURAL_GUARANTEES=PASS"

# --- no host address and no secret is committed to the framework

ADDRESS_PATTERN='192\.168\.1\.1''33'
USER_PATTERN='cbs_dev''@'

if grep -RIn \
    --exclude-dir=.git \
    --exclude-dir=packages \
    --exclude-dir=node_modules \
    -e "$ADDRESS_PATTERN" \
    -e "$USER_PATTERN" \
    "$ROOT"
then
    remote_test_fail "HOST_ADDRESS_OR_USER_HARDCODED"
fi

if grep -RInE \
    --exclude-dir=.git \
    --exclude-dir=packages \
    '(BEGIN [A-Z ]*PRIVATE KEY|ssh-rsa AAAA|ssh-ed25519 AAAA|CBS_REMOTE_PASSWORD|CBS_REMOTE_TOKEN)' \
    "$ROOT/cbs/remote" "$ROOT/bin" "$ROOT/tests/fixtures/remote"
then
    remote_test_fail "SECRET_MATERIAL_PRESENT"
fi

# The framework ships no remote manifest: they stay outside the repository.
if find "$ROOT" \
    -path "$ROOT/.git" -prune -o \
    -path "$ROOT/packages" -prune -o \
    -type f \( -name 'remote*.env' -o -name '*.remote.env' \) -print |
    grep -q .
then
    remote_test_fail "REMOTE_MANIFEST_VERSIONED"
fi

echo "TEST_REMOTE_CLI_NO_HARDCODED_HOST_OR_SECRET=PASS"

echo "TEST_REMOTE_CLI_RESULT=PASS"
