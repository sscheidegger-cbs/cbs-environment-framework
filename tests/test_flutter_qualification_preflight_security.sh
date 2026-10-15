#!/usr/bin/env bash

# D04b-C.2b step 2: hermetic security test of the Flutter/iOS qualification
# PREFLIGHT: inputs are data, the environment is not trusted, the manifest is
# never executed, nothing outside the observation is executed or written.
#
# Same hermetic setup as test_flutter_qualification_preflight.sh: real Git
# repositories and CBS isolations in a private directory, shims for the
# toolchain, a PATH without any real Flutter or Xcode. A "pwned" marker file
# proves that no injected command ever ran.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFLIGHT="$ROOT/cbs/qualification/flutter/preflight.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_PREFLIGHT_SECURITY"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$CONTRACT"

[[ -f "$PREFLIGHT" ]] || pf_fail "PREFLIGHT_MISSING"

iso_fixture_init
pf_init

PWNED="$TMP/pwned"
SECRET_MARK="s3cr3tvalue-do-not-leak"

pf_new_isolation iso-sec
pf_new_isolation iso-other

# security_blocked <label> <min rc> <max rc> <argument...> : refused before any
# tool or Git call, nothing echoed, nothing executed.
security_blocked() {
    local label="$1"
    local min="$2"
    local max="$3"

    shift 3

    pf_run "$label" "$@"

    [[ "$PF_RC" -ge "$min" && "$PF_RC" -le "$max" ]] || pf_fail "${label}_RC_${PF_RC}"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "BLOCKED" ]] || pf_fail "${label}_RESULT_$(pf_kv CBS_FLUTTER_QUAL_RESULT)"
    [[ "$(pf_check PARAMETERS)" == "BLOCKED" ]] || pf_fail "${label}_PARAMETERS"
    [[ ! -e "$PWNED" ]] || pf_fail "${label}_EXECUTED"
    [[ "$(pf_tool_calls)" -eq 0 && "$(pf_git_calls)" -eq 0 ]] || pf_fail "${label}_RAN_SOMETHING"

    if printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e "$SECRET_MARK" -e "$PWNED" -e "touch" >/dev/null; then
        pf_fail "${label}_ECHOED"
    fi
}

# ---------------------------------------------------------------- 1. injection: every value is data

pf_modes_reset

PAYLOADS=(
    "\$(touch $PWNED)"
    "\`touch $PWNED\`"
    ";touch $PWNED;"
    "a[\$(touch $PWNED)]"
    "x' ; touch $PWNED ; '"
    "x\" ; touch $PWNED ; \""
    "| touch $PWNED"
    "&& touch $PWNED"
    "\${IFS}touch\${IFS}$PWNED"
    "$(printf 'x\ntouch %s' "$PWNED")"
    "-oProxyCommand=touch $PWNED"
    "--dart-define=A=\$(touch $PWNED)"
)

KEYS="contract_version qualification_id isolation_id source_repository expected_origin commit isolation_root evidence_root target actions timeout_seconds log_max_bytes evidence_retention cleanup_policy simulator_udid simulator_policy"

# Many runs: the three roots are fingerprinted once around the whole loop.
BEFORE_LOOP="$(pf_fingerprint)"
PF_NO_FINGERPRINT=1

for payload in "${PAYLOADS[@]}"; do
    for key in $KEYS; do
        pf_req_reset iso-sec
        pf_req_set "$key" "$payload"
        security_blocked "INJECT_${key}" 120 125 "${PF_REQ[@]}"
    done

    # The payload as a key, as a bare argument, as an extra entry.
    pf_req_reset iso-sec
    security_blocked INJECT_AS_KEY 120 125 "${PF_REQ[@]}" "${payload}=x"
    security_blocked INJECT_AS_ARGUMENT 120 125 "${PF_REQ[@]}" "$payload"
done

unset PF_NO_FINGERPRINT
[[ "$(pf_fingerprint)" == "$BEFORE_LOOP" ]] || pf_fail "INJECTION_LOOP_MUTATED_STATE"

echo "${TEST_PREFIX}_NO_INJECTION=PASS"

# ---------------------------------------------------------------- 2. no arbitrary command, no arbitrary argument

pf_req_reset iso-sec

for word in "flutter" "pub get" "analyze" "--version" "-c" "--dart-define=API=x" ";id" "\$(id)" "rm -rf /" "bash -c id" "eval" "preflight"; do
    security_blocked "ARG_$word" 123 123 "${PF_REQ[@]}" "$word"
done

for entry in "flutter_args=--verbose" "command=rm" "extra_args=x" "shell=sh" "script=x.sh" "eval=1" "PATH=/evil" "Flutter=1" "flutter-args=1" "x=1"; do
    security_blocked "ENTRY_$entry" 123 123 "${PF_REQ[@]}" "$entry"
done

# Names that look sensitive are refused as secrets, with no echo of the value.
for entry in "dart_define=K=$SECRET_MARK" "dart_define_from_file=/x/$SECRET_MARK" "api_token=$SECRET_MARK" "password=$SECRET_MARK" "github_token=$SECRET_MARK" "authorization=Bearer $SECRET_MARK"; do
    security_blocked "SENSITIVE_${entry%%=*}" 125 125 "${PF_REQ[@]}" "$entry"
done

# A secret smuggled into an accepted parameter.
for key in qualification_id isolation_id source_repository expected_origin commit isolation_root evidence_root actions simulator_udid; do
    for secret in "token=$SECRET_MARK" "password=$SECRET_MARK" "Bearer $SECRET_MARK" "https://u:$SECRET_MARK@h/x" "--dart-define=A=$SECRET_MARK" "ghp_abcdefghijklmnopqrstuvwxyz0123456789"; do
        pf_req_reset iso-sec
        pf_req_set "$key" "$secret"
        security_blocked "SECRET_IN_$key" 120 125 "${PF_REQ[@]}"
    done
done

# A bare dart-define is an argument, and never reaches a log or an output.
pf_req_reset iso-sec
security_blocked DART_DEFINE_BARE 123 123 "${PF_REQ[@]}" "--dart-define=TOKEN=$SECRET_MARK"

echo "${TEST_PREFIX}_NO_ARBITRARY_COMMAND=PASS"

# ---------------------------------------------------------------- 3. paths and links

# link_blocked <label> <reason> <rc> <argument...>
link_blocked() {
    local label="$1"
    local reason="$2"
    local rc="$3"

    shift 3

    pf_run "$label" "$@"
    pf_expect "$label" BLOCKED "$reason" "$rc"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" != "PASS" ]] || pf_fail "${label}_PASS"
    [[ "$(pf_tool_calls)" -eq 0 ]] || pf_fail "${label}_TOOL_CALLED"
    [[ ! -e "$PWNED" ]] || pf_fail "${label}_EXECUTED"
    pf_assert_git_readonly "$label"
}

# isolation root: a symbolic link to the real one.
ln -s "$ISO_ROOT" "$TMP/root-link"
pf_req_reset iso-sec
pf_req_set isolation_root "$TMP/root-link"
link_blocked ROOT_LINK ISOLATION_REJECTED 126 "${PF_REQ[@]}"
[[ "$(pf_value ISOLATION_REASON)" == "ROOT_SYMLINK" ]] || pf_fail "ROOT_LINK_REASON_$(pf_value ISOLATION_REASON)"

# source repository: a symbolic link, a subdirectory (not the top level).
ln -s "$SOURCE" "$TMP/source-link"
pf_req_reset iso-sec
pf_req_set source_repository "$TMP/source-link"
link_blocked SOURCE_LINK ISOLATION_REJECTED 126 "${PF_REQ[@]}"
[[ "$(pf_value ISOLATION_REASON)" == "SOURCE_SYMLINK" ]] || pf_fail "SOURCE_LINK_REASON_$(pf_value ISOLATION_REASON)"

mkdir "$SOURCE/subdir"
pf_req_set source_repository "$SOURCE/subdir"
link_blocked SOURCE_SUBDIR ISOLATION_REJECTED 126 "${PF_REQ[@]}"
rmdir "$SOURCE/subdir"

# source repository of another place than the one of the isolation.
mkdir "$TMP/other-repo"
git -C "$TMP/other-repo" init -q
git -C "$TMP/other-repo" config user.name t
git -C "$TMP/other-repo" config user.email t@example.invalid
git -C "$TMP/other-repo" remote add origin "$ISO_ORIGIN"
printf '%s\n' x > "$TMP/other-repo/f"
git -C "$TMP/other-repo" add f
git -C "$TMP/other-repo" commit -qm x
pf_req_reset iso-sec
pf_req_set source_repository "$TMP/other-repo"
link_blocked SOURCE_OTHER ISOLATION_REJECTED 126 "${PF_REQ[@]}"

# the isolated checkout replaced by a symbolic link to another checkout.
mv "$ISO_ROOT/iso-other" "$TMP/iso-other-moved"
ln -s "$ISO_ROOT/iso-sec" "$ISO_ROOT/iso-other"
pf_req_reset iso-other
link_blocked CHECKOUT_LINK ISOLATION_REJECTED 126 "${PF_REQ[@]}"
[[ "$(pf_value ISOLATION_REASON)" == "PATH_SYMLINK" ]] || pf_fail "CHECKOUT_LINK_REASON_$(pf_value ISOLATION_REASON)"
rm "$ISO_ROOT/iso-other"
mv "$TMP/iso-other-moved" "$ISO_ROOT/iso-other"

# the isolated checkout replaced by a copy (same files, never registered by Git).
pf_new_isolation iso-copy
mv "$ISO_ROOT/iso-copy" "$TMP/iso-copy-original"
cp -R "$TMP/iso-copy-original" "$ISO_ROOT/iso-copy"
pf_req_reset iso-copy
link_blocked CHECKOUT_COPY ISOLATION_REJECTED 126 "${PF_REQ[@]}"
rm -rf "$ISO_ROOT/iso-copy"
mv "$TMP/iso-copy-original" "$ISO_ROOT/iso-copy"

# evidence root: a link towards the source, a place inside the source, inside
# the isolated checkout, or covering the source.
ln -s "$SOURCE" "$TMP/evidence-hijack"
pf_req_reset iso-sec
pf_req_set evidence_root "$TMP/evidence-hijack"
link_blocked EVIDENCE_HIJACK PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"
[[ "$(pf_git_calls)" -eq 0 ]] || pf_fail "EVIDENCE_HIJACK_GIT_CALLED"

pf_req_set evidence_root "$SOURCE/evidence"
link_blocked EVIDENCE_IN_SOURCE PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"

pf_req_set evidence_root "$ISO_ROOT/iso-sec/evidence"
link_blocked EVIDENCE_IN_CHECKOUT PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"
[[ ! -e "$ISO_ROOT/iso-sec/evidence" ]] || pf_fail "EVIDENCE_IN_CHECKOUT_CREATED"

pf_req_set evidence_root "$TMP"
link_blocked EVIDENCE_COVERS_SOURCE PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"

# isolation root covering the source, or equal to it.
pf_req_reset iso-sec
pf_req_set isolation_root "$TMP"
link_blocked ROOT_COVERS_SOURCE PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"
pf_req_set isolation_root "$SOURCE"
link_blocked ROOT_IS_SOURCE PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"

# forbidden components and traversal.
for value in "$SOURCE/../escape" "$ISO_ROOT/./x" "$TMP/.git/x" "$TMP/.ssh/x" "/" "/tmp" "relative"; do
    pf_req_reset iso-sec
    pf_req_set evidence_root "$value"
    link_blocked "EVIDENCE_PATH_$(printf '%s' "$value" | tr -c 'A-Za-z0-9' '_')" PATH_NOT_ALLOWED 124 "${PF_REQ[@]}"
done

# isolation identifiers that name another place.
for value in "iso-sec/../iso-other" ".hidden" "-rf" "iso-sec.lock" "iso sec" "iso-sec/"; do
    pf_req_reset iso-sec
    pf_req_set isolation_id "$value"
    security_blocked "ID_$(printf '%s' "$value" | tr -c 'A-Za-z0-9' '_')" 121 121 "${PF_REQ[@]}"
done

echo "${TEST_PREFIX}_PATHS_AND_LINKS=PASS"

# ---------------------------------------------------------------- 4. the environment is not trusted

pf_modes_reset
pf_req_reset iso-sec

# Guards and bounds of the contract cannot be pre-set from the environment.
PF_ENV_ASSIGN="CBS_FLUTTER_QUAL_CONTRACT_LOADED=1 CBS_ISOLATION_CONTRACT_LOADED=1 CBS_WORKTREE_CONTRACT_LOADED=1"
pf_run ENV_GUARDS "${PF_REQ[@]}"
pf_expect ENV_GUARDS PASS - 0

PF_ENV_ASSIGN="CBS_FLUTTER_QUAL_TIMEOUT_MAX=999999 CBS_FLUTTER_QUAL_PATTERN_PATH=.* CBS_FLUTTER_QUAL_REQUIRED_KEYS="
pf_req_set timeout_seconds 5000
pf_run ENV_BOUNDS "${PF_REQ[@]}"
pf_expect ENV_BOUNDS BLOCKED INPUT_INVALID 121
pf_req_reset iso-sec

# Fixed locations are not taken from the environment.
cat > "$TMP/evil-manager.sh" <<EOF
#!/usr/bin/env bash
touch "$PWNED"
printf 'CBS_FLUTTER_ISOLATION_RESULT=PASS\n'
exit 0
EOF
cat > "$TMP/evil-stack.env" <<EOF
CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=9.9.9
CBS_STACK_MANAGED_TOOLCHAIN_XCODE_VERSION=99
EOF
PF_ENV_ASSIGN="CBS_FLUTTER_QUAL_PREFLIGHT_ISOLATION_MANAGER=$TMP/evil-manager.sh CBS_FLUTTER_QUAL_PREFLIGHT_STACK_MANIFEST=$TMP/evil-stack.env CBS_FLUTTER_QUAL_PREFLIGHT_ROOT=$TMP CBS_FLUTTER_QUAL_PREFLIGHT_DIR=$TMP"
pf_run ENV_LOCATIONS "${PF_REQ[@]}"
pf_expect ENV_LOCATIONS PASS - 0
[[ ! -e "$PWNED" ]] || pf_fail "ENV_LOCATIONS_EXECUTED"
[[ "$(pf_value FLUTTER_REQUIRED_VERSION)" == "$PF_FLUTTER_REQUIRED" ]] || pf_fail "ENV_LOCATIONS_MANIFEST_FROM_ENV"

# Internal state variables inherited from the environment are overwritten.
PF_ENV_ASSIGN="PF_R_COMMIT=PASS PF_R_FLUTTER=PASS PF_X_FLUTTER= PF_FLUTTER_VERSION=$PF_FLUTTER_REQUIRED PF_TIMEOUT=99999 PF_OUTPUT_CAP=0"
SHIM_FLUTTER_MODE=garbage
export SHIM_FLUTTER_MODE
pf_run ENV_STATE "${PF_REQ[@]}"
pf_expect ENV_STATE BLOCKED TOOLCHAIN_INCOMPATIBLE 128
[[ "$(pf_check FLUTTER)" == "BLOCKED" ]] || pf_fail "ENV_STATE_FLUTTER_PREPASSED"
pf_modes_reset
pf_req_reset iso-sec

# Git redirection variables do not reach the checks.
mkdir "$TMP/decoy"
git -C "$TMP/decoy" init -q
DECOY_BEFORE="$(iso_tree_fingerprint "$TMP/decoy")"
PF_ENV_ASSIGN="GIT_DIR=$TMP/decoy/.git GIT_WORK_TREE=$TMP/decoy GIT_INDEX_FILE=$TMP/decoy/.git/index GIT_COMMON_DIR=$TMP/decoy/.git GIT_CEILING_DIRECTORIES=$TMP CDPATH=$TMP:/tmp"
pf_run ENV_GIT "${PF_REQ[@]}"
pf_expect ENV_GIT PASS - 0
[[ "$(iso_tree_fingerprint "$TMP/decoy")" == "$DECOY_BEFORE" ]] || pf_fail "ENV_GIT_DECOY_TOUCHED"
[[ "$(pf_value COMMIT_OBSERVED)" == "$C2" ]] || pf_fail "ENV_GIT_COMMIT"

# Git hooks of the source are never executed by the observation.
mkdir -p "$SOURCE/.git/hooks"
for hook in post-checkout reference-transaction fsmonitor-watchman; do
    printf '#!/bin/sh\ntouch "%s"\n' "$PWNED" > "$SOURCE/.git/hooks/$hook"
    chmod 755 "$SOURCE/.git/hooks/$hook"
done
git -C "$SOURCE" config core.hooksPath "$SOURCE/.git/hooks"
git -C "$SOURCE" config core.fsmonitor "$SOURCE/.git/hooks/fsmonitor-watchman"
pf_modes_reset
PF_NO_FINGERPRINT=1
pf_run HOOKS "${PF_REQ[@]}"
unset PF_NO_FINGERPRINT
pf_expect HOOKS PASS - 0
[[ ! -e "$PWNED" ]] || pf_fail "HOOK_EXECUTED"
git -C "$SOURCE" config --unset core.hooksPath
git -C "$SOURCE" config --unset core.fsmonitor
rm -f "$SOURCE/.git/hooks/post-checkout" "$SOURCE/.git/hooks/reference-transaction" "$SOURCE/.git/hooks/fsmonitor-watchman"
iso_snapshot_source

# No temporary file is left or needed: TMPDIR stays empty.
mkdir "$TMP/tmpdir-empty"
PF_ENV_ASSIGN="TMPDIR=$TMP/tmpdir-empty"
pf_run ENV_TMPDIR "${PF_REQ[@]}"
pf_expect ENV_TMPDIR PASS - 0
[[ -z "$(ls -A "$TMP/tmpdir-empty")" ]] || pf_fail "TMPDIR_USED"

pf_modes_reset
echo "${TEST_PREFIX}_ENVIRONMENT_NOT_TRUSTED=PASS"

# ---------------------------------------------------------------- 5. PATH: relative entries are never used

mkdir "$TMP/evil-cwd"
for tool in flutter dart xcodebuild xcrun git; do
    printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWNED" > "$TMP/evil-cwd/$tool"
    chmod 755 "$TMP/evil-cwd/$tool"
done
mkdir "$TMP/evil-cwd/relative"
cp "$TMP/evil-cwd/flutter" "$TMP/evil-cwd/relative/flutter"

pf_req_reset iso-sec

# Relative and empty entries before the shims: the shims are used.
PF_CWD="$TMP/evil-cwd"
PF_PATH_PREFIX=".:relative::"
pf_run PATH_RELATIVE "${PF_REQ[@]}"
pf_expect PATH_RELATIVE PASS - 0
[[ ! -e "$PWNED" ]] || pf_fail "PATH_RELATIVE_EXECUTED"
[[ "$(pf_tool_calls)" -eq 7 ]] || pf_fail "PATH_RELATIVE_SHIMS_NOT_USED"

# A tool reachable only through a relative entry does not exist.
PF_MISSING="flutter"
pf_run PATH_RELATIVE_ONLY "${PF_REQ[@]}"
pf_expect PATH_RELATIVE_ONLY BLOCKED TOOL_UNAVAILABLE 127
[[ "$(pf_check FLUTTER)" == "BLOCKED" ]] || pf_fail "PATH_RELATIVE_ONLY_CHECK"
[[ ! -e "$PWNED" ]] || pf_fail "PATH_RELATIVE_ONLY_EXECUTED"

# A file that is not executable is not a tool.
mkdir "$TMP/not-exec"
printf '#!/bin/sh\ntouch "%s"\n' "$PWNED" > "$TMP/not-exec/dart"
chmod 644 "$TMP/not-exec/dart"
PF_MISSING="dart"
PF_CWD="$TMP"
PF_PATH_PREFIX="$TMP/not-exec:"
pf_run PATH_NOT_EXECUTABLE "${PF_REQ[@]}"
pf_expect PATH_NOT_EXECUTABLE BLOCKED TOOL_UNAVAILABLE 127
[[ ! -e "$PWNED" ]] || pf_fail "PATH_NOT_EXECUTABLE_EXECUTED"

# Tools run from "/" whatever the working directory of the caller.
pf_modes_reset
echo "${TEST_PREFIX}_PATH_NOT_TRUSTED=PASS"

# ---------------------------------------------------------------- 6. manifest and manager: data, never executed

COPY="$TMP/copy-root"
mkdir -p "$COPY/stacks/flutter"
cp -R "$ROOT/cbs" "$COPY/cbs"
cp "$ROOT/stacks/flutter/stack.env" "$COPY/stacks/flutter/stack.env"
COPY_PREFLIGHT="$COPY/cbs/qualification/flutter/preflight.sh"
COPY_STACK="$COPY/stacks/flutter/stack.env"
GOOD_STACK="$ROOT/stacks/flutter/stack.env"

pf_modes_reset
PF_PREFLIGHT_SCRIPT="$COPY_PREFLIGHT"
pf_req_reset iso-sec

pf_run COPY_PASS "${PF_REQ[@]}"
pf_expect COPY_PASS PASS - 0

# stack_blocked <label> : the manifest of the copy was altered.
stack_blocked() {
    pf_run "$1" "${PF_REQ[@]}"
    pf_expect "$1" BLOCKED TOOLCHAIN_INCOMPATIBLE 128
    [[ "$(pf_check STACK_REFERENCE)" == "BLOCKED" ]] || pf_fail "${1}_CHECK"
    [[ "$(pf_check FLUTTER)" == "NOT_RUN" && "$(pf_check XCODE)" == "NOT_RUN" && "$(pf_check SIMULATOR)" == "NOT_RUN" ]] || pf_fail "${1}_TOOLS_RAN"
    [[ "$(pf_tool_calls)" -eq 0 ]] || pf_fail "${1}_TOOL_CALLED"
    [[ ! -e "$PWNED" ]] || pf_fail "${1}_EXECUTED"
}

printf '%s\n' \
    'CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=$(touch '"$PWNED"')' \
    'CBS_STACK_MANAGED_TOOLCHAIN_XCODE_VERSION=15' > "$COPY_STACK"
stack_blocked MANIFEST_SUBSTITUTION

printf '%s\n' \
    'CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=3.47.6; touch '"$PWNED" \
    'CBS_STACK_MANAGED_TOOLCHAIN_XCODE_VERSION=15' > "$COPY_STACK"
stack_blocked MANIFEST_SEMICOLON

printf '%s\n' \
    'CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=3.47.6' \
    'CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=3.47.7' \
    'CBS_STACK_MANAGED_TOOLCHAIN_XCODE_VERSION=15' > "$COPY_STACK"
stack_blocked MANIFEST_DUPLICATE

printf '%s\n' 'CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=3.47.6' > "$COPY_STACK"
stack_blocked MANIFEST_INCOMPLETE

printf '%s\n' \
    'CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=3.47.6' \
    'CBS_STACK_MANAGED_TOOLCHAIN_XCODE_VERSION=15 16' > "$COPY_STACK"
stack_blocked MANIFEST_BAD_XCODE

rm "$COPY_STACK"
stack_blocked MANIFEST_MISSING

cp "$GOOD_STACK" "$TMP/real-stack.env"
ln -s "$TMP/real-stack.env" "$COPY_STACK"
stack_blocked MANIFEST_SYMLINK
rm "$COPY_STACK"

# Executable-looking lines around valid keys are text: never executed.
{
    printf '%s\n' '$(touch '"$PWNED"')'
    printf '%s\n' '`touch '"$PWNED"'`'
    printf '%s\n' "source $TMP/evil-manager.sh"
    printf '%s\n' "touch $PWNED"
    printf '%s\n' "export CBS_FLUTTER_QUAL_TIMEOUT_MAX=999999"
    printf '%s\n' "CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION_EXTRA=1.0.0"
    cat "$GOOD_STACK"
} > "$COPY_STACK"
pf_run MANIFEST_NOISE "${PF_REQ[@]}"
pf_expect MANIFEST_NOISE PASS - 0
[[ ! -e "$PWNED" ]] || pf_fail "MANIFEST_NOISE_EXECUTED"
cp "$GOOD_STACK" "$COPY_STACK"

# The reference of the manifest is what decides compatibility.
printf '%s\n' \
    'CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=3.99.0' \
    'CBS_STACK_MANAGED_TOOLCHAIN_XCODE_VERSION=15' > "$COPY_STACK"
pf_run MANIFEST_OTHER_VERSION "${PF_REQ[@]}"
pf_expect MANIFEST_OTHER_VERSION BLOCKED TOOLCHAIN_INCOMPATIBLE 128
[[ "$(pf_check FLUTTER)" == "BLOCKED" ]] || pf_fail "MANIFEST_OTHER_VERSION_CHECK"
cp "$GOOD_STACK" "$COPY_STACK"

# The isolation manager is a fixed component and its answer is checked as a whole.
MANAGER_COPY="$COPY/cbs/worktree/isolation_manager.sh"
cp "$ROOT/cbs/worktree/isolation_manager.sh" "$TMP/manager.orig"

# manager_blocked <label> <isolation reason> : a replaced manager is not believed.
manager_blocked() {
    pf_run "$1" "${PF_REQ[@]}"
    pf_expect "$1" BLOCKED ISOLATION_REJECTED 126
    [[ "$(pf_value ISOLATION_REASON)" == "$2" ]] || pf_fail "${1}_REASON_$(pf_value ISOLATION_REASON)"
    [[ "$(pf_check OWNERSHIP)" == "BLOCKED" ]] || pf_fail "${1}_OWNERSHIP"
    [[ "$(pf_check FLUTTER)" == "NOT_RUN" ]] || pf_fail "${1}_FLUTTER_RAN"
    [[ "$(pf_tool_calls)" -eq 0 ]] || pf_fail "${1}_TOOL_CALLED"
}

rm "$MANAGER_COPY"
manager_blocked MANAGER_MISSING MANAGER_UNAVAILABLE

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$MANAGER_COPY"
manager_blocked MANAGER_SILENT OUTPUT_INVALID

# A PASS printed with a failing exit status is not a PASS.
cat > "$MANAGER_COPY" <<EOF
#!/usr/bin/env bash
printf 'CBS_FLUTTER_ISOLATION_VERSION=1\n'
printf 'CBS_FLUTTER_ISOLATION_COMMIT_EXPECTED=$C2\n'
printf 'CBS_FLUTTER_ISOLATION_COMMIT_OBSERVED=$C2\n'
printf 'CBS_FLUTTER_ISOLATION_ORIGIN=$ISO_ORIGIN\n'
printf 'CBS_FLUTTER_ISOLATION_REASON=NONE\n'
printf 'CBS_FLUTTER_ISOLATION_RC=0\n'
printf 'CBS_FLUTTER_ISOLATION_RESULT=PASS\n'
exit 3
EOF
manager_blocked MANAGER_PASS_WITH_FAILURE OUTPUT_INVALID

# A PASS whose RC or REASON disagree is not a PASS.
sed -i.bak 's/^exit 3$/exit 0/; s/ISOLATION_RC=0/ISOLATION_RC=68/' "$MANAGER_COPY"
rm -f "$MANAGER_COPY.bak"
manager_blocked MANAGER_PASS_WITH_RC OUTPUT_INVALID

# A reason that is not a closed identifier is never printed.
cat > "$MANAGER_COPY" <<EOF
#!/usr/bin/env bash
printf 'CBS_FLUTTER_ISOLATION_REASON=x; touch $PWNED\n'
printf 'CBS_FLUTTER_ISOLATION_RESULT=BLOCKED\n'
exit 67
EOF
manager_blocked MANAGER_BAD_REASON OUTPUT_INVALID
[[ ! -e "$PWNED" ]] || pf_fail "MANAGER_BAD_REASON_EXECUTED"

# A manager that does not terminate is stopped by the timeout.
cat > "$MANAGER_COPY" <<EOF
#!/usr/bin/env bash
sleep 30 &
echo \$! > "$PF_HANG_PID"
wait
EOF
pf_req_set timeout_seconds 1
START=$SECONDS
pf_run MANAGER_HANG "${PF_REQ[@]}"
[[ "$((SECONDS - START))" -lt 15 ]] || pf_fail "MANAGER_HANG_NOT_BOUNDED"
pf_expect MANAGER_HANG FAIL TIMEOUT 131
[[ "$(pf_check OWNERSHIP)" == "FAIL" ]] || pf_fail "MANAGER_HANG_CHECK"
sleep 1
if kill -0 "$(cat "$PF_HANG_PID")" 2>/dev/null; then
    kill -KILL "$(cat "$PF_HANG_PID")" 2>/dev/null || true
    pf_fail "MANAGER_HANG_CHILD_SURVIVED"
fi
pf_req_set timeout_seconds 20

cp "$TMP/manager.orig" "$MANAGER_COPY"
pf_run MANAGER_RESTORED "${PF_REQ[@]}"
pf_expect MANAGER_RESTORED PASS - 0

pf_modes_reset
echo "${TEST_PREFIX}_MANIFEST_AND_MANAGER_NOT_TRUSTED=PASS"

# ---------------------------------------------------------------- 7. a Git-tracked file is never modified

pf_req_reset iso-sec
pf_run TRACKED_FILES "${PF_REQ[@]}"
pf_expect TRACKED_FILES PASS - 0

# The tracked files of the isolated checkout and of the source are the commit.
[[ -z "$(git -C "$ISO_ROOT/iso-sec" status --porcelain --untracked-files=no)" ]] || pf_fail "CHECKOUT_MODIFIED"
[[ "$(git -C "$ISO_ROOT/iso-sec" rev-parse HEAD)" == "$C2" ]] || pf_fail "CHECKOUT_HEAD"
[[ "$(cat "$ISO_ROOT/iso-sec/file.txt")" == "second" ]] || pf_fail "CHECKOUT_FILE"
[[ "$(cat "$SOURCE/file.txt")" == "second" ]] || pf_fail "SOURCE_FILE"
[[ -z "$(git -C "$SOURCE" status --porcelain --untracked-files=no)" ]] || pf_fail "SOURCE_MODIFIED"
[[ -f "$SOURCE/.local/note.txt" ]] || pf_fail "SOURCE_UNTRACKED_LOST"
[[ ! -e "$PWNED" ]] || pf_fail "PWNED_AT_END"

echo "${TEST_PREFIX}_NO_MUTATION=PASS"

# ---------------------------------------------------------------- 8. Git: executable configuration neutralised, incompatible Git refused

pf_modes_reset
pf_new_isolation iso-git
pf_new_isolation iso-git-ctl

EVIL_FSMONITOR="$TMP/evil-fsmonitor.sh"
EVIL_HOOKS="$TMP/evil-hooks"
EVIL_HOME="$TMP/evil-home"
mkdir -p "$EVIL_HOOKS" "$EVIL_HOME"

printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWNED" > "$EVIL_FSMONITOR"
chmod 755 "$EVIL_FSMONITOR"
for hook in post-checkout pre-commit reference-transaction post-index-change; do
    printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWNED" > "$EVIL_HOOKS/$hook"
    chmod 755 "$EVIL_HOOKS/$hook"
done

printf '[core]\n\tfsmonitor = %s\n\thooksPath = %s\n' "$EVIL_FSMONITOR" "$EVIL_HOOKS" > "$EVIL_HOME/.gitconfig"
EVIL_PARAMETERS="'core.fsmonitor=$EVIL_FSMONITOR' 'core.hooksPath=$EVIL_HOOKS'"

GIT_NL="
"

# Files only (no Git command: the repository configuration is hostile here).
file_fingerprint() {
    iso_tree_fingerprint "$SOURCE"
    iso_tree_fingerprint "$ISO_ROOT"
    iso_tree_fingerprint "$EVID"
}

# The harness isolates Git from the user configuration (GIT_CONFIG_GLOBAL=/dev/null):
# the hostile user configuration is given explicitly.
EVIL_GLOBAL="$EVIL_HOME/.gitconfig"

# git_prepared <GIT_CONFIG_GLOBAL> <GIT_CONFIG_PARAMETERS> <git argument...>
# Runs git in the environment prepared by the executor (sourced, nothing else
# executed), without any "-c" option: only the exported variables protect it.
git_prepared() {
    local global="$1"
    local parameters="$2"

    shift 2

    set +e
    (cd "$TMP" && env "GIT_CONFIG_GLOBAL=$global" "GIT_CONFIG_PARAMETERS=$parameters" PATH="$PF_VIEW:$PF_TOOLS" \
        "$BASH" -c 'source "$1"; shift; git "$@"' prepared "$PREFLIGHT" "$@" >/dev/null 2>&1)
    set -e
}

# git_raw <GIT_CONFIG_GLOBAL> <GIT_CONFIG_PARAMETERS> <git argument...>: the same Git, with
# no protection at all (control: it proves that the traps are armed).
git_raw() {
    local global="$1"
    local parameters="$2"

    shift 2

    set +e
    (cd "$TMP" && env "GIT_CONFIG_GLOBAL=$global" "GIT_CONFIG_PARAMETERS=$parameters" git "$@" >/dev/null 2>&1)
    set -e
}

# --- hostile configuration, at the three levels the checkout reads

git -C "$SOURCE" config core.fsmonitor "$EVIL_FSMONITOR"
git -C "$SOURCE" config core.hooksPath "$EVIL_HOOKS"
CTL="$ISO_ROOT/iso-git-ctl"

# Controls: unprotected, each configuration does execute the planted command.
# Without them a green test would prove nothing.
rm -f "$PWNED"
git_raw "$GIT_CONFIG_GLOBAL" "" -C "$CTL" status
[[ -e "$PWNED" ]] || pf_fail "CONTROL_FSMONITOR_NOT_ARMED"
rm -f "$PWNED"
git_raw "$GIT_CONFIG_GLOBAL" "" -C "$CTL" checkout --detach "$C2"
[[ -e "$PWNED" ]] || pf_fail "CONTROL_HOOKSPATH_NOT_ARMED"
rm -f "$PWNED"

git -C "$SOURCE" config --unset core.fsmonitor
git -C "$SOURCE" config --unset core.hooksPath
git_raw "$EVIL_GLOBAL" "" -C "$CTL" status
[[ -e "$PWNED" ]] || pf_fail "CONTROL_GLOBAL_FSMONITOR_NOT_ARMED"
rm -f "$PWNED"

git_raw "$GIT_CONFIG_GLOBAL" "$EVIL_PARAMETERS" -C "$CTL" status
[[ -e "$PWNED" ]] || pf_fail "CONTROL_PARAMETERS_FSMONITOR_NOT_ARMED"
rm -f "$PWNED"

# GIT_CONFIG_COUNT alone does not beat GIT_CONFIG_PARAMETERS: this is why the
# executor removes the latter from the environment.
set +e
(cd "$TMP" && env "GIT_CONFIG_PARAMETERS=$EVIL_PARAMETERS" GIT_CONFIG_COUNT=2 \
    GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false \
    GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null \
    git -C "$CTL" status >/dev/null 2>&1)
set -e
[[ -e "$PWNED" ]] || pf_fail "CONTROL_COUNT_DOES_NOT_BEAT_PARAMETERS_NOT_OBSERVED"
rm -f "$PWNED"

# Protected by the environment of the executor alone (no "-c" option): nothing
# runs, for a repository configuration, a user configuration and an inherited
# GIT_CONFIG_PARAMETERS.
git -C "$SOURCE" config core.fsmonitor "$EVIL_FSMONITOR"
git -C "$SOURCE" config core.hooksPath "$EVIL_HOOKS"

git_prepared "$EVIL_GLOBAL" "$EVIL_PARAMETERS" -C "$CTL" status
[[ ! -e "$PWNED" ]] || pf_fail "PREPARED_ENV_STATUS_EXECUTED"
git_prepared "$EVIL_GLOBAL" "$EVIL_PARAMETERS" -C "$CTL" checkout --detach "$C2"
[[ ! -e "$PWNED" ]] || pf_fail "PREPARED_ENV_CHECKOUT_EXECUTED"

# The effective values are the neutral ones.
EFFECTIVE="$(cd "$TMP" && env "GIT_CONFIG_GLOBAL=$EVIL_GLOBAL" "GIT_CONFIG_PARAMETERS=$EVIL_PARAMETERS" PATH="$PF_VIEW:$PF_TOOLS" "$BASH" -c 'source "$1"; git -C "$2" config --get core.fsmonitor; git -C "$2" config --get core.hooksPath' effective "$PREFLIGHT" "$CTL")"
[[ "$EFFECTIVE" == "false${GIT_NL}/dev/null" ]] || pf_fail "EFFECTIVE_CONFIG_NOT_NEUTRAL"

# The whole executor, hostile configuration everywhere: PASS, nothing executed,
# nothing written, only read-only Git commands.
pf_req_reset iso-git
PF_NO_FINGERPRINT=1

hostile_pass() {
    local label="$1"
    local before
    local after

    before="$(file_fingerprint)"
    pf_run "$label" "${PF_REQ[@]}"
    after="$(file_fingerprint)"

    pf_expect "$label" PASS - 0
    [[ "$before" == "$after" ]] || pf_fail "${label}_STATE_MUTATED"
    [[ ! -e "$PWNED" ]] || pf_fail "${label}_EXECUTED"
    [[ "$(pf_check GIT_CONFIG_GUARD)" == "PASS" ]] || pf_fail "${label}_GIT_GUARD"
    pf_assert_git_readonly "$label"
}

hostile_pass HOSTILE_REPOSITORY

PF_ENV_ASSIGN="GIT_CONFIG_GLOBAL=$EVIL_GLOBAL"
hostile_pass HOSTILE_USER_CONFIG

GIT_CONFIG_PARAMETERS="$EVIL_PARAMETERS"
export GIT_CONFIG_PARAMETERS
PF_ENV_ASSIGN="GIT_CONFIG_GLOBAL=$EVIL_GLOBAL"
hostile_pass HOSTILE_PARAMETERS
unset GIT_CONFIG_PARAMETERS

# Variables of the caller cannot replace the guard: count, keys, sentinel.
PF_ENV_ASSIGN="GIT_CONFIG_COUNT=0 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=$EVIL_FSMONITOR GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=$EVIL_HOOKS GIT_CONFIG_KEY_3=cbs.preflightconfigcount GIT_CONFIG_VALUE_3=forged"
hostile_pass HOSTILE_COUNT_VARIABLES
unset PF_ENV_ASSIGN

# A startup file named by the caller is not read by the bash processes of the
# executor (the manager, the supervisor): only the first shell, which started
# before the executor could do anything, can read it.
#
# The first shell always reads it, so exactly one record means "the first shell
# only". The value of "$0" at that moment is not portable: Bash 5 already holds
# the script path, Bash 3.2 (macOS) was observed to hold the name of the
# interpreter ("/bin/bash"; the startup file is read before $0 is set to the
# script). It is therefore never
# compared with a constant: the reference is MEASURED, with the same hook, on a
# run that stops at the usage check, before any other bash can exist.
printf 'echo "$$ $0" >> "%s"\n' "$TMP/bash-env.log" > "$TMP/bash-env.sh"

# bash_env_records : number of records of the hook
bash_env_records() {
    wc -l < "$TMP/bash-env.log" | tr -d ' '
}

# bash_env_zero <line> : the "$0" of a record ("<pid> <$0>")
bash_env_zero() {
    printf '%s\n' "${1#* }"
}

# Reference: the first shell alone (no request: usage refusal, no child bash).
: > "$TMP/bash-env.log"
PF_ENV_ASSIGN="BASH_ENV=$TMP/bash-env.sh"
pf_run BASH_ENV_REFERENCE
unset PF_ENV_ASSIGN
[[ "$(bash_env_records)" -eq 1 ]] || pf_fail "BASH_ENV_REFERENCE_RECORDS_$(bash_env_records)"
BASH_ENV_FIRST_LINE="$(head -n 1 "$TMP/bash-env.log")"
[[ "$BASH_ENV_FIRST_LINE" =~ ^[0-9]+\ .+$ ]] || pf_fail "BASH_ENV_REFERENCE_FORMAT_$BASH_ENV_FIRST_LINE"
BASH_ENV_FIRST_ZERO="$(bash_env_zero "$BASH_ENV_FIRST_LINE")"

# Full run: one single record, the one of the first shell (same "$0" as the
# reference); any other record is a child bash that read the startup file.
: > "$TMP/bash-env.log"
PF_ENV_ASSIGN="BASH_ENV=$TMP/bash-env.sh"
hostile_pass BASH_ENV_NOT_INHERITED
unset PF_ENV_ASSIGN
[[ "$(bash_env_records)" -eq 1 ]] || pf_fail "BASH_ENV_READ_BY_CHILDREN_$(tr '\n' ' ' < "$TMP/bash-env.log")"
BASH_ENV_LINE="$(head -n 1 "$TMP/bash-env.log")"
[[ "$BASH_ENV_LINE" =~ ^[0-9]+\ .+$ ]] || pf_fail "BASH_ENV_FORMAT_$BASH_ENV_LINE"
[[ "$(bash_env_zero "$BASH_ENV_LINE")" == "$BASH_ENV_FIRST_ZERO" ]] || pf_fail "BASH_ENV_READER_$BASH_ENV_LINE"

# Sensitivity: the same hook, on a copy of the executor without its
# "unset BASH_ENV", must be read by the child bash processes as well (at least
# the first shell and one child), otherwise the check above proves nothing.
BASH_ENV_MUT="$TMP/bash-env-mutant"
mkdir -p "$BASH_ENV_MUT/stacks/flutter"
cp -R "$ROOT/cbs" "$BASH_ENV_MUT/cbs"
cp "$ROOT/stacks/flutter/stack.env" "$BASH_ENV_MUT/stacks/flutter/stack.env"
BASH_ENV_MUT_SCRIPT="$BASH_ENV_MUT/cbs/qualification/flutter/preflight.sh"
grep -v '^unset BASH_ENV$' "$BASH_ENV_MUT_SCRIPT" > "$BASH_ENV_MUT_SCRIPT.new"
[[ "$(wc -l < "$BASH_ENV_MUT_SCRIPT" | tr -d ' ')" -eq $(( $(wc -l < "$BASH_ENV_MUT_SCRIPT.new" | tr -d ' ') + 1 )) ]] || pf_fail "BASH_ENV_MUTANT_NOT_SINGLE_LINE_REMOVAL"
mv "$BASH_ENV_MUT_SCRIPT.new" "$BASH_ENV_MUT_SCRIPT"
chmod +x "$BASH_ENV_MUT_SCRIPT"

: > "$TMP/bash-env.log"
pf_modes_reset
pf_req_reset iso-git
PF_PREFLIGHT_SCRIPT="$BASH_ENV_MUT_SCRIPT"
PF_ENV_ASSIGN="BASH_ENV=$TMP/bash-env.sh"
PF_NO_FINGERPRINT=1
pf_run BASH_ENV_MUTANT "${PF_REQ[@]}"
unset PF_NO_FINGERPRINT
pf_modes_reset
pf_req_reset iso-git
[[ "$(bash_env_records)" -gt 1 ]] || pf_fail "BASH_ENV_CHECK_BLIND_TO_REGRESSION_RECORDS_$(bash_env_records)"
unset PF_NO_FINGERPRINT

# --- Git that cannot apply GIT_CONFIG_COUNT: refused before any repository is touched

# git_gate <label> <RESULT> <REASON> <rc> <git calls> : the answer of a refusal
git_gate() {
    local label="$1"
    local name
    local before
    local after

    # The harness itself must not run Git on the hostile repository: files only.
    before="$(file_fingerprint)"
    PF_NO_FINGERPRINT=1
    pf_run "$label" "${PF_REQ[@]}"
    unset PF_NO_FINGERPRINT
    after="$(file_fingerprint)"

    pf_expect "$label" "$2" "$3" "$4"
    [[ "$before" == "$after" ]] || pf_fail "${label}_STATE_MUTATED"
    [[ ! -e "$PWNED" ]] || pf_fail "${label}_EXECUTED"
    [[ "$(pf_check GIT_CONFIG_GUARD)" == "$2" ]] || pf_fail "${label}_CHECK_$(pf_check GIT_CONFIG_GUARD)"
    [[ "$(pf_check_reason GIT_CONFIG_GUARD)" == "$3" ]] || pf_fail "${label}_CHECK_REASON"
    [[ "$(pf_check PARAMETERS)" == "PASS" && "$(pf_check EVIDENCE_ROOT)" == "PASS" ]] || pf_fail "${label}_EARLY_CHECKS"

    # Nothing else ran: no isolation check, no toolchain probe, no repository.
    for name in OWNERSHIP COMMIT ORIGIN DETACHED_HEAD GIT_STATE STACK_REFERENCE FLUTTER DART XCODE SDK_IPHONEOS SDK_IPHONESIMULATOR SIMCTL SIMULATOR; do
        [[ "$(pf_check "$name")" == "NOT_RUN" ]] || pf_fail "${label}_${name}_RAN"
    done

    [[ "$(pf_tool_calls)" -eq 0 ]] || pf_fail "${label}_TOOL_CALLED"
    [[ "$(pf_git_calls)" -eq "$5" ]] || pf_fail "${label}_GIT_CALLS_$(pf_git_calls)"

    if grep -E -e ' -[cC] ' -e ' (status|rev-parse|worktree|checkout|remote|cat-file|for-each-ref|branch) ' "$PF_GITLOG" >/dev/null; then
        pf_fail "${label}_REPOSITORY_TOUCHED"
    fi

    pf_assert_git_readonly "$label"
    [[ -z "$(pf_value COMMIT_OBSERVED)" ]] || pf_fail "${label}_COMMIT_OBSERVED_PRINTED"
}

pf_req_reset iso-git

# Hostile configuration in the source repository (still set): a refusal means
# that no command touched it.
pf_modes_reset
export SHIM_GIT_VERSION_LINE="git version 2.30.2"
export SHIM_GIT_IGNORE_COUNT=1
git_gate GIT_OLD BLOCKED TOOLCHAIN_INCOMPATIBLE 128 1
[[ "$(pf_value GIT_VERSION)" == "2.30.2" ]] || pf_fail "GIT_OLD_VERSION_FACT"

# Recent version claimed, but the variables are ignored: the sentinel is not
# read back (two probes: version, then sentinel).
pf_modes_reset
export SHIM_GIT_IGNORE_COUNT=1
git_gate GIT_IGNORES_COUNT BLOCKED TOOLCHAIN_INCOMPATIBLE 128 2

# The same Git, with a user configuration that already answers for the
# sentinel key: the answer (status 0) is not the sentinel, so it is refused.
printf '[cbs]\n\tpreflightconfigcount = planted\n' > "$TMP/planted.gitconfig"
pf_modes_reset
export SHIM_GIT_IGNORE_COUNT=1
PF_ENV_ASSIGN="GIT_CONFIG_GLOBAL=$TMP/planted.gitconfig"
git_gate GIT_IGNORES_COUNT_PLANTED BLOCKED TOOLCHAIN_INCOMPATIBLE 128 2
unset PF_ENV_ASSIGN

# Old version number although the variables are applied: refused all the same.
pf_modes_reset
export SHIM_GIT_VERSION_LINE="git version 2.30.2"
git_gate GIT_VERSION_TOO_OLD BLOCKED TOOLCHAIN_INCOMPATIBLE 128 1

# Numeric comparison, not text comparison.
for line in "git version 2.9.5" "git version 2.4" "git version 1.99.0" "git version 0.1" "git version 2.30.99"; do
    pf_modes_reset
    export SHIM_GIT_VERSION_LINE="$line"
    git_gate "GIT_REFUSED_$(printf '%s' "$line" | tr -c 'A-Za-z0-9' '_')" BLOCKED TOOLCHAIN_INCOMPATIBLE 128 1
done

# A version that cannot be read is not accepted.
for line in "git version" "git version unknown" "hello" "git version x.y.z" "git version 2" "git  version 2.43.0"; do
    pf_modes_reset
    export SHIM_GIT_VERSION_LINE="$line"
    git_gate "GIT_UNREADABLE_$(printf '%s' "$line" | tr -c 'A-Za-z0-9' '_')" BLOCKED TOOLCHAIN_INCOMPATIBLE 128 1
    [[ -z "$(pf_value GIT_VERSION)" ]] || pf_fail "GIT_UNREADABLE_VERSION_PRINTED"
done

# Git absent from PATH.
pf_modes_reset
PF_MISSING="git"
export PF_MISSING
git_gate GIT_ABSENT BLOCKED TOOL_UNAVAILABLE 127 0
unset PF_MISSING

# "git --version" fails: a probe that ran and went wrong, status reported.
pf_modes_reset
export SHIM_GIT_MODE=fail SHIM_GIT_RC=5
git_gate GIT_FAILS FAIL COMMAND_FAILED 130 1
[[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "5" ]] || pf_fail "GIT_FAILS_TOOL_RC"

# "git --version" hangs: stopped by the timeout, nothing left behind.
pf_modes_reset
export SHIM_GIT_MODE=hang
pf_req_set timeout_seconds 1
git_gate GIT_HANGS FAIL TIMEOUT 131 1
pf_pid_gone "$(cat "$PF_HANG_PID")" 3 || pf_fail "GIT_HANGS_CHILD_SURVIVED"
pf_req_set timeout_seconds 20

# --- Git versions accepted at the boundary and beyond, repository clean again

git -C "$SOURCE" config --unset core.fsmonitor
git -C "$SOURCE" config --unset core.hooksPath
pf_modes_reset
iso_snapshot_source

version_accepted() {
    pf_modes_reset
    export SHIM_GIT_VERSION_LINE="$1"
    pf_run "$3" "${PF_REQ[@]}"
    pf_expect "$3" PASS - 0
    [[ "$(pf_check GIT_CONFIG_GUARD)" == "PASS" ]] || pf_fail "${3}_GUARD"
    [[ "$(pf_value GIT_VERSION)" == "$2" ]] || pf_fail "${3}_VERSION_FACT_$(pf_value GIT_VERSION)"
}

version_accepted "git version 2.31.0" "2.31.0" GIT_BOUNDARY
version_accepted "git version 2.31" "2.31" GIT_BOUNDARY_SHORT
version_accepted "git version 2.100.1" "2.100.1" GIT_MINOR_100
version_accepted "git version 3.0.0" "3.0.0" GIT_MAJOR_3
version_accepted "git version 2.39.5 (Apple Git-154)" "2.39.5" GIT_APPLE

pf_modes_reset
pf_run GIT_COMPATIBLE "${PF_REQ[@]}"
pf_expect GIT_COMPATIBLE PASS - 0
[[ "$(pf_check GIT_CONFIG_GUARD)" == "PASS" && "$(pf_check OWNERSHIP)" == "PASS" ]] || pf_fail "GIT_COMPATIBLE_CHECKS"
[[ ! -e "$PWNED" ]] || pf_fail "GIT_SECTION_PWNED_AT_END"
iso_assert_source_untouched "GIT_SECTION_SOURCE"

echo "${TEST_PREFIX}_GIT_CONFIGURATION=PASS"

# ---------------------------------------------------------------- 9. static scan of the executor

[[ -f "$PREFLIGHT" ]] || pf_fail "STATIC_MISSING"

# The executor is read in two parts: the supervisor (a fixed text run by a
# fresh bash, with its own rules below) and everything else (the strict rules).
OUTSIDE="$TMP/preflight-outside.sh"
SUPERVISOR="$TMP/preflight-supervisor.sh"
sed -e "/^CBS_FLUTTER_QUAL_PREFLIGHT_SUPERVISOR='\$/,/^'\$/d" "$PREFLIGHT" > "$OUTSIDE"
sed -n -e "/^CBS_FLUTTER_QUAL_PREFLIGHT_SUPERVISOR='\$/,/^'\$/p" "$PREFLIGHT" | sed -e '1d' -e '$d' > "$SUPERVISOR"
[[ -s "$SUPERVISOR" ]] || pf_fail "STATIC_SUPERVISOR_NOT_FOUND"
[[ "$(grep -c "CBS_FLUTTER_QUAL_PREFLIGHT_SUPERVISOR='" "$PREFLIGHT")" -eq 1 ]] || pf_fail "STATIC_SUPERVISOR_DEFINED_ONCE"
! grep -q "SUPERVISOR='" "$OUTSIDE" || pf_fail "STATIC_SUPERVISOR_SPLIT"
bash -n "$SUPERVISOR" || pf_fail "STATIC_SUPERVISOR_SYNTAX"

if pf_code_matches "$OUTSIDE" '(^|[;&|({[:space:]])eval([[:space:]]|$)'; then
    pf_fail "STATIC_EVAL"
fi

if pf_code_matches "$SUPERVISOR" '(^|[;&|({[:space:]])(eval|source|alias|enable|builtin)([[:space:]]|$)|(^|[[:space:]])\.[[:space:]]'; then
    pf_fail "STATIC_SUPERVISOR_EVAL"
fi

# A single sourced file: the contract, at a path derived from this file.
SOURCED="$(grep -En '^[[:space:]]*(source|\.)[[:space:]]' "$PREFLIGHT" |
    grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$SOURCED" == 'source "$CBS_FLUTTER_QUAL_PREFLIGHT_DIR/contract.sh"' ]] || pf_fail "STATIC_SOURCED_FILES"

# No command that writes, removes, moves, links, changes a mode or makes a
# temporary file; no network, no privilege, no interpreter.
STATIC_FORBIDDEN='(^|[;&|({]|\$\()[[:space:]]*(rm|rmdir|mv|cp|mkdir|touch|chmod|chown|ln|tee|dd|install|mktemp|truncate|sync|sudo|su|ssh|scp|sftp|rsync|curl|wget|nc|open|python|python3|perl|ruby|node|osascript|brew|nohup|xargs|find|sed|awk|tar|unzip)[[:space:]]'
if pf_code_matches "$OUTSIDE" "$STATIC_FORBIDDEN"; then
    pf_fail "STATIC_EXTERNAL_COMMAND"
fi
if pf_code_matches "$SUPERVISOR" "$STATIC_FORBIDDEN"; then
    pf_fail "STATIC_SUPERVISOR_EXTERNAL_COMMAND"
fi

# Git is reached only through the isolation manager and the two fixed probes.
if pf_code_matches "$PREFLIGHT" '(^|[;&|({]|\$\()[[:space:]]*git[[:space:]]'; then
    pf_fail "STATIC_GIT_COMMAND"
fi

if pf_code_matches "$PREFLIGHT" 'git[[:space:]]+(clean|reset|checkout|switch|restore|add|commit|fetch|pull|push|clone|worktree|stash|gc|prune|remote[[:space:]]+(add|set-url|remove))'; then
    pf_fail "STATIC_GIT_MUTATION"
fi

# "git config" is only ever the read-only "git config --get".
GIT_CONFIG_USES="$(grep -En 'git[[:space:]]+config' "$PREFLIGHT" | grep -Ev '^[0-9]+:[[:space:]]*#' | grep -Ev 'git[[:space:]]+config[[:space:]]+--get[[:space:]]' || true)"
[[ -z "$GIT_CONFIG_USES" ]] || pf_fail "STATIC_GIT_CONFIG_WRITE"

# No Flutter, Dart, Xcode or simulator action beyond the probes.
if pf_code_matches "$PREFLIGHT" 'flutter[[:space:]]+(pub|analyze|test|build|clean|upgrade|doctor|config|create|run|precache|devices|emulators|install)|pub[[:space:]]+get|dart[[:space:]]+(pub|run|analyze|test|compile|fix|format)|xcodebuild[[:space:]]+-?(build|archive|clean|test|install|runFirstLaunch|license)|xcode-select[[:space:]]+--install|simctl[[:space:]]+(boot|create|erase|shutdown|install|uninstall|delete|launch|spawn|clone|rename|upgrade|shutdown)|ENSURE'; then
    pf_fail "STATIC_TOOL_ACTION"
fi

# The probes are exactly the fixed list: nothing else is ever executed.
PROBES="$(grep -E '_cbs_flutter_qual_pf_probe "' "$PREFLIGHT" | grep -Ev '^[[:space:]]*#' | sed -e 's/^[[:space:]]*//' -e 's/ || return [01]$//')"
EXPECTED_PROBES='_cbs_flutter_qual_pf_probe "GIT_CONFIG_GUARD" "COMMAND_FAILED" git --version
_cbs_flutter_qual_pf_probe "GIT_CONFIG_GUARD" "TOOLCHAIN_INCOMPATIBLE" git config --get "$CBS_FLUTTER_QUAL_PREFLIGHT_GIT_PROBE_KEY"
_cbs_flutter_qual_pf_probe "FLUTTER" "COMMAND_FAILED" flutter --version
_cbs_flutter_qual_pf_probe "DART" "COMMAND_FAILED" dart --version
_cbs_flutter_qual_pf_probe "XCODE" "COMMAND_FAILED" xcodebuild -version
_cbs_flutter_qual_pf_probe "$check" "TOOLCHAIN_INCOMPATIBLE" xcrun --sdk "$sdk" --show-sdk-version
_cbs_flutter_qual_pf_probe "SIMCTL" "TOOL_UNAVAILABLE" xcrun --find simctl
_cbs_flutter_qual_pf_probe "SIMULATOR" "COMMAND_FAILED" xcrun simctl list devices'
[[ "$PROBES" == "$EXPECTED_PROBES" ]] || pf_fail "STATIC_PROBE_LIST"

SDKS="$(grep -E '_cbs_flutter_qual_pf_check_sdk "' "$PREFLIGHT" | grep -Ev '^[[:space:]]*#|\(\) \{' | sed -e 's/^[[:space:]]*//')"
EXPECTED_SDKS='_cbs_flutter_qual_pf_check_sdk "SDK_IPHONEOS" "iphoneos"
_cbs_flutter_qual_pf_check_sdk "SDK_IPHONESIMULATOR" "iphonesimulator"'
[[ "$SDKS" == "$EXPECTED_SDKS" ]] || pf_fail "STATIC_SDK_LIST"

# The only other execution points: the bounded runner and the isolation manager.
RUNS="$(grep -E '_cbs_flutter_qual_pf_run ' "$PREFLIGHT" | grep -Ev '^[[:space:]]*#|\(\) \{' | sed -e 's/^[[:space:]]*//')"
EXPECTED_RUNS='_cbs_flutter_qual_pf_run "$PF_TIMEOUT" "$path" "$@"
_cbs_flutter_qual_pf_run "$PF_TIMEOUT" "${BASH:-bash}" "$manager" verify \'
[[ "$RUNS" == "$EXPECTED_RUNS" ]] || pf_fail "STATIC_RUN_LIST"

# Outside the supervisor nothing is "exec"'"'"'d, trapped or waited for; the runner
# starts one fresh bash, with the supervisor text and the command as data.
EXECS="$(grep -E '(^|[^A-Za-z_])exec([[:space:]]|$)' "$OUTSIDE" | grep -Ev '^[[:space:]]*#' | sed -e 's/^[[:space:]]*//' || true)"
[[ -z "$EXECS" ]] || pf_fail "STATIC_EXEC_OUTSIDE_SUPERVISOR"

if pf_code_matches "$OUTSIDE" '(^|[;&|({[:space:]])(trap|alias|enable|builtin|wait|set[[:space:]]+-m)([[:space:]]|$)'; then
    pf_fail "STATIC_SHELL_STATE"
fi

BASH_STARTS="$(grep -En '"\$\{BASH:-bash\}"' "$OUTSIDE" | grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
EXPECTED_BASH_STARTS='raw="$("${BASH:-bash}" -c "$CBS_FLUTTER_QUAL_PREFLIGHT_SUPERVISOR" \
_cbs_flutter_qual_pf_run "$PF_TIMEOUT" "${BASH:-bash}" "$manager" verify \'
[[ "$BASH_STARTS" == "$EXPECTED_BASH_STARTS" ]] || pf_fail "STATIC_BASH_START_LIST"

# Inside the supervisor: the exact list of exec, trap and kill, and no other
# process creation than the command, the timer and sleep.
SUP_EXECS="$(grep -E '(^|[^A-Za-z_])exec([[:space:]]|$)' "$SUPERVISOR" | sed -e 's/^[[:space:]]*//')"
EXPECTED_SUP_EXECS='exec 2>/dev/null
( cd / && LC_ALL=C exec "$@" ) </dev/null 2>&1 &
( sleep "$limit"; kill -USR1 "$$"; exec sleep 86400 ) </dev/null >/dev/null 2>&1 &'
[[ "$SUP_EXECS" == "$EXPECTED_SUP_EXECS" ]] || pf_fail "STATIC_SUPERVISOR_EXEC_LIST"

SUP_TRAPS="$(grep -E '(^|[;&|({[:space:]])trap([[:space:]]|$)' "$SUPERVISOR" | sed -e 's/^[[:space:]]*//')"
EXPECTED_SUP_TRAPS='trap "" USR1
trap "" INT TERM HUP USR1
trap on_interrupt INT TERM HUP
trap on_timeout USR1'
[[ "$SUP_TRAPS" == "$EXPECTED_SUP_TRAPS" ]] || pf_fail "STATIC_SUPERVISOR_TRAP_LIST"

SUP_KILLS="$(grep -E '(^|[;&|({[:space:]])kill([[:space:]]|$)' "$SUPERVISOR" | sed -e 's/^[[:space:]]*//')"
EXPECTED_SUP_KILLS='kill -KILL -- "-$timer"
kill -KILL -- "-$child"
kill -TERM -- "-$child"
kill -KILL -- "-$child"
( sleep "$limit"; kill -USR1 "$$"; exec sleep 86400 ) </dev/null >/dev/null 2>&1 &'
[[ "$SUP_KILLS" == "$EXPECTED_SUP_KILLS" ]] || pf_fail "STATIC_SUPERVISOR_KILL_LIST"

# The timer never signals the command (only the supervisor, once).
TIMER_LINE="$(grep -F 'sleep "$limit"' "$SUPERVISOR")"
[[ "$TIMER_LINE" == *'kill -USR1 "$$"'* && "$TIMER_LINE" != *'$child'* ]] || pf_fail "STATIC_SUPERVISOR_TIMER_SIGNALS_COMMAND"

# The only redirections are the null device, standard error and reading a
# file: no file is ever written (supervisor included).
for scanned in "$OUTSIDE" "$SUPERVISOR"; do
    STRIPPED="$(grep -Ev '^[[:space:]]*#' "$scanned" | sed -e 's#2>/dev/null##g' -e 's#>/dev/null##g' -e 's#2>&1##g' -e 's#>&2##g' -e 's#</dev/null##g' -e 's#done < "\$file"##')"
    if printf '%s\n' "$STRIPPED" | grep -v -e '\[\[' -e "'[^']*>[^']*'" -e '^[[:space:]]*"' | grep -F '>' >/dev/null; then
        pf_fail "STATIC_FILE_WRITE_$(basename "$scanned")"
    fi
done

# No backtick substitution, no dependency on a business application, no
# coupling to the remote transport.
if pf_code_matches "$PREFLIGHT" '`'; then
    pf_fail "STATIC_BACKTICK"
fi

APP_PATTERN="AMH""-USR"
if grep -Eiq -e "$APP_PATTERN" -e "amh[_-]usr" "$PREFLIGHT"; then
    pf_fail "STATIC_APPLICATION_DEPENDENCY"
fi

if pf_code_matches "$PREFLIGHT" 'remote_(runner|transport|checker|verifier|manifest)|worktree_manager|toolchain_manager|stack_environment|bin/cbs|provider_contract|providers/'; then
    pf_fail "STATIC_COMPONENT_COUPLING"
fi

echo "${TEST_PREFIX}_STATIC_SCAN=PASS"
echo "${TEST_PREFIX}_RESULT=PASS"
