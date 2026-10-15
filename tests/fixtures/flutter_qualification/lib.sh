#!/usr/bin/env bash

# TEST ONLY - shared helpers of the Flutter/iOS qualification contract tests.
#
# Sourced by tests/test_flutter_qualification_*.sh, which must define ROOT and
# TEST_PREFIX first. Compatible with Bash 3.2. Nothing here runs Flutter.

FQ_TMP=""
FQ_RC=0

fq_fail() {
    echo "${TEST_PREFIX}_RESULT=FAIL" >&2
    echo "${TEST_PREFIX}_FAILURE=$1" >&2
    exit 1
}

fq_cleanup() {
    # Only the directory created by fq_init, never anything else.
    if [[ -n "$FQ_TMP" && -d "$FQ_TMP" && "$FQ_TMP" == */cbs-flutter-qual.* ]]; then
        rm -rf "$FQ_TMP"
    fi
}

# Creates a private, canonical (symlink-free) temporary directory.
fq_init() {
    local base

    base="$(cd -P "${TMPDIR:-/tmp}" && pwd -P)" || fq_fail "TMPDIR_UNUSABLE"
    FQ_TMP="$(mktemp -d "$base/cbs-flutter-qual.XXXXXX")" || fq_fail "MKTEMP"
    FQ_TMP="$(cd -P "$FQ_TMP" && pwd -P)"
    trap fq_cleanup EXIT
}

# fq_rc <command...> : runs the command in this shell, output discarded,
# return code in FQ_RC (never aborts the test).
fq_rc() {
    set +e
    "$@" >/dev/null 2>&1
    FQ_RC=$?
    set -e
}

# fq_expect_rc <expected> <label> <command...>
fq_expect_rc() {
    local expected="$1"
    local label="$2"

    shift 2
    fq_rc "$@"

    [[ "$FQ_RC" -eq "$expected" ]] ||
        fq_fail "${label}_EXPECTED_${expected}_GOT_${FQ_RC}"
}

# fq_expect_reason <expected-reason> <label> : checks the last validation.
fq_expect_reason() {
    [[ "$CBS_FLUTTER_QUAL_VALIDATION_REASON" == "$1" ]] ||
        fq_fail "${2}_REASON_EXPECTED_${1}_GOT_${CBS_FLUTTER_QUAL_VALIDATION_REASON}"
}

# Reference request: every value is data and satisfies the contract.
# The paths are lexical only: they do not need to exist.
FQ_COMMIT="0123456789abcdef0123456789abcdef01234567"
FQ_REQUEST=()

fq_request_reset() {
    FQ_REQUEST=(
        "contract_version=1"
        "qualification_id=qual-ios-1"
        "isolation_id=iso-ios-1"
        "source_repository=/srv/cbs/source/app"
        "expected_origin=git@example.invalid:org/app.git"
        "commit=$FQ_COMMIT"
        "isolation_root=/srv/cbs/isolation"
        "evidence_root=/srv/cbs/evidence"
        "target=ios-simulator"
        "actions=preflight,analyze,test,build_ios,report"
        "timeout_seconds=600"
        "log_max_bytes=10485760"
        "evidence_retention=keep"
        "cleanup_policy=none"
        "test_scope=unit_widget"
        "test_targets=test/a_test.dart,test/widget/b_test.dart"
    )
}

# fq_request_set <key> <value> : replaces (or appends) one entry.
fq_request_set() {
    local key="$1"
    local value="$2"
    local entry
    local found=0
    local updated=()

    for entry in "${FQ_REQUEST[@]}"; do
        if [[ "${entry%%=*}" == "$key" ]]; then
            updated[${#updated[@]}]="$key=$value"
            found=1
        else
            updated[${#updated[@]}]="$entry"
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        updated[${#updated[@]}]="$key=$value"
    fi

    FQ_REQUEST=("${updated[@]}")
}

# fq_request_unset <key> : removes one entry.
fq_request_unset() {
    local key="$1"
    local entry
    local updated=()

    for entry in "${FQ_REQUEST[@]}"; do
        if [[ "${entry%%=*}" != "$key" ]]; then
            updated[${#updated[@]}]="$entry"
        fi
    done

    FQ_REQUEST=("${updated[@]}")
}

# Validates FQ_REQUEST: return code in FQ_RC, reason in the contract variable.
fq_validate_request() {
    set +e
    cbs_flutter_qual_validate_request "${FQ_REQUEST[@]}" >/dev/null 2>&1
    FQ_RC=$?
    set -e
}

# Installs a "forbidden tool" shim for every tool a qualification will later
# need. Any call is logged and fails with 99: a validator that reaches one of
# them is a defect. Generated at run time, never committed as an executable.
FQ_SHIM_BIN=""
FQ_SHIM_LOG=""
FQ_FORBIDDEN_TOOLS="flutter dart xcrun xcodebuild simctl git ssh scp curl wget open"

fq_shims_install() {
    local tool

    FQ_SHIM_BIN="$FQ_TMP/forbidden-bin"
    FQ_SHIM_LOG="$FQ_TMP/forbidden-calls.log"

    mkdir -p "$FQ_SHIM_BIN"
    : > "$FQ_SHIM_LOG"

    for tool in $FQ_FORBIDDEN_TOOLS; do
        {
            printf '#!/bin/sh\n'
            printf 'echo "%s $*" >> "%s"\n' "$tool" "$FQ_SHIM_LOG"
            printf 'exit 99\n'
        } > "$FQ_SHIM_BIN/$tool"
        chmod 755 "$FQ_SHIM_BIN/$tool"
    done
}

fq_shims_assert_unused() {
    [[ -s "$FQ_SHIM_LOG" ]] && fq_fail "$1_FORBIDDEN_TOOL_CALLED_$(head -n 1 "$FQ_SHIM_LOG" | tr ' ' '_')"

    return 0
}

# Non-comment lines of a file matching an extended regular expression.
# fq_code_matches <file> <regex> : succeeds when at least one line matches.
fq_code_matches() {
    grep -En -e "$2" "$1" |
        grep -Ev '^[0-9]+:[[:space:]]*#' |
        grep -Eq .
}

# =============================================================================
# PREFLIGHT executor helpers (D04b-C.2b step 2). TEST ONLY.
#
# Used by tests/test_flutter_qualification_preflight*.sh, which must define
# ROOT, TEST_PREFIX and PREFLIGHT, source tests/fixtures/worktree_isolation/lib.sh
# (iso_fixture_init creates the source repository, TMP and the cleanup trap),
# then call pf_init. Nothing here runs a real Flutter, Dart, Xcode or simctl:
# the tools are shims generated at run time inside TMP, and the PATH given to
# the executor contains only those shims and links to the system tools it needs.
# Compatible with Bash 3.2.
# =============================================================================

# Code scan without SIGPIPE: "grep -q" ending a pipeline can make the writers
# die with 141, which "pipefail" turns into a false "no match". Every stage
# here reads its whole input.
pf_code_matches() {
    local hits
    hits="$(grep -En -e "$2" "$1" | grep -Ev '^[0-9]+:[[:space:]]*#' || true)"
    [[ -n "$hits" ]]
}

PF_STATE=""
PF_TOOLS=""
PF_SHIMS=""
PF_VIEW=""
PF_LOG=""
PF_BAD=""
PF_GITLOG=""
PF_ERRFILE=""
PF_HANG_PID=""
PF_REAL_GIT=""
PF_LIST=""
PF_FLUTTER_REQUIRED=""
PF_XCODE_MINIMUM=""
PF_OUT=""
PF_ERR=""
PF_RC=0
PF_REQ=()
EVID=""
ISO_ID=""

PF_UDID_SHUTDOWN="11111111-1111-4111-8111-111111111111"
PF_UDID_BOOTED="22222222-2222-4222-8222-222222222222"
PF_UDID_TVOS="33333333-3333-4333-8333-333333333333"
PF_UDID_UNAVAILABLE="44444444-4444-4444-8444-444444444444"
PF_UDID_ABSENT="55555555-5555-4555-8555-555555555555"

PF_SHIM_NAMES="flutter dart xcodebuild xcrun git"

# Tools the executor and the isolation manager need, linked from the host.
PF_SYSTEM_TOOLS="bash env sh git find sed awk ls tr id od cat head tail date dirname basename sleep kill mkdir rm rmdir cksum sort wc grep cp chmod touch ln mv uname printf test true false"

pf_fail() {
    echo "${TEST_PREFIX}_RESULT=FAIL" >&2
    echo "${TEST_PREFIX}_FAILURE=$1" >&2

    # Last answer of the executor, to diagnose (it never holds a secret).
    if [[ -n "${PF_OUT:-}${PF_ERR:-}" ]]; then
        echo "--- last stdout" >&2
        printf '%s\n' "$PF_OUT" >&2
        echo "--- last stderr" >&2
        printf '%s\n' "$PF_ERR" >&2
    fi

    exit 1
}

pf_pass() {
    echo "${TEST_PREFIX}_$1=PASS"
}

pf_init() {
    local tool
    local real

    PF_STATE="$TMP/pf-state"
    PF_TOOLS="$TMP/pf-tools"
    PF_SHIMS="$TMP/pf-shims"
    PF_VIEW="$TMP/pf-view"
    PF_LOG="$PF_STATE/tool-calls.log"
    PF_BAD="$PF_STATE/unexpected-calls.log"
    PF_GITLOG="$PF_STATE/git-calls.log"
    PF_ERRFILE="$PF_STATE/stderr"
    PF_HANG_PID="$PF_STATE/hang.pid"
    PF_LIST="$PF_STATE/simctl-devices.txt"
    EVID="$TMP/evidence"

    mkdir -p "$PF_STATE" "$PF_TOOLS" "$PF_SHIMS" "$PF_VIEW" "$EVID"
    : > "$PF_LOG"
    : > "$PF_BAD"
    : > "$PF_GITLOG"

    # Reference versions: the same two lines the executor reads.
    PF_FLUTTER_REQUIRED="$(sed -n 's/^CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=//p' "$ROOT/stacks/flutter/stack.env")"
    PF_XCODE_MINIMUM="$(sed -n 's/^CBS_STACK_MANAGED_TOOLCHAIN_XCODE_VERSION=//p' "$ROOT/stacks/flutter/stack.env")"
    [[ -n "$PF_FLUTTER_REQUIRED" && -n "$PF_XCODE_MINIMUM" ]] || pf_fail "STACK_REFERENCE_FIXTURE"

    PF_REAL_GIT="$(command -v git)"

    for tool in $PF_SYSTEM_TOOLS; do
        real="$(command -v "$tool" 2>/dev/null || true)"
        case "$real" in
            /*) ln -s "$real" "$PF_TOOLS/$tool" ;;
        esac
    done

    pf_shims_generate
    pf_devices_default
}

pf_devices_default() {
    cat > "$PF_LIST" <<EOF
== Devices ==
-- iOS 17.5 --
    iPhone 15 ($PF_UDID_SHUTDOWN) (Shutdown)
    iPhone 15 Pro ($PF_UDID_BOOTED) (Booted)
-- tvOS 17.5 --
    Apple TV ($PF_UDID_TVOS) (Shutdown)
-- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-16-4 --
    iPhone 14 ($PF_UDID_UNAVAILABLE) (Shutdown) (unavailable, runtime profile not found)
EOF
}

# Shims log every call, refuse (99, logged as unexpected) any call that is not
# in the allow-list of PREFLIGHT, and answer according to PF_*_MODE variables.
pf_shims_generate() {
    local real_git

    real_git="$(command -v git)"

    # The Git shim logs every call and then runs the real Git. Modes (the
    # probes of PREFLIGHT are "--version" and "config --get <key>"):
    #   SHIM_GIT_VERSION_LINE   text printed instead of the real "--version"
    #   SHIM_GIT_IGNORE_COUNT   1: a Git that does not read GIT_CONFIG_COUNT
    #   SHIM_GIT_MODE           fail (--version exits SHIM_GIT_RC) | hang (--version)
    cat > "$PF_SHIMS/git" <<EOF
#!/bin/sh
echo "git \$*" >> "$PF_GITLOG"
if [ "\$*" = "--version" ]; then
    case "\${SHIM_GIT_MODE:-ok}" in
        fail)
            echo "git: simulated failure" >&2
            exit "\${SHIM_GIT_RC:-5}" ;;
        hang)
            sleep 30 &
            echo \$! > "$PF_HANG_PID"
            wait ;;
    esac
    if [ -n "\${SHIM_GIT_VERSION_LINE:-}" ]; then
        echo "\$SHIM_GIT_VERSION_LINE"
        exit 0
    fi
fi
if [ "\${SHIM_GIT_IGNORE_COUNT:-0}" = "1" ]; then
    unset GIT_CONFIG_COUNT
fi
exec "$real_git" "\$@"
EOF

    cat > "$PF_SHIMS/flutter" <<EOF
#!/bin/sh
echo "flutter \$*" >> "$PF_LOG"
if [ "\$*" != "--version" ]; then
    echo "flutter \$*" >> "$PF_BAD"
    exit 99
fi
case "\${SHIM_FLUTTER_MODE:-ok}" in
    ok)
        echo "Flutter \${SHIM_FLUTTER_VERSION:-$PF_FLUTTER_REQUIRED} • channel stable • https://github.com/flutter/flutter.git"
        echo "Framework • revision 0000000000 (1 year ago) • 2025-01-01 00:00:00 +0000"
        echo "Engine • revision 0000000000"
        echo "Tools • Dart 3.9.0 • DevTools 2.40.0"
        exit 0 ;;
    fail)
        echo "flutter: simulated failure" >&2
        exit "\${SHIM_FLUTTER_RC:-3}" ;;
    garbage)
        echo "not a version"
        exit 0 ;;
    hang)
        sleep 30 &
        echo \$! > "$PF_HANG_PID"
        wait ;;
esac
exit 98
EOF

    cat > "$PF_SHIMS/dart" <<EOF
#!/bin/sh
echo "dart \$*" >> "$PF_LOG"
if [ "\$*" != "--version" ]; then
    echo "dart \$*" >> "$PF_BAD"
    exit 99
fi
case "\${SHIM_DART_MODE:-ok}" in
    ok)
        echo "Dart SDK version: \${SHIM_DART_VERSION:-3.9.0} (stable) (Thu Jan 1 00:00:00 2026 +0000) on \"macos_arm64\""
        exit 0 ;;
    fail)
        echo "dart: simulated failure" >&2
        exit "\${SHIM_DART_RC:-4}" ;;
    garbage)
        echo "unknown"
        exit 0 ;;
    hang)
        sleep 30 &
        echo \$! > "$PF_HANG_PID"
        wait ;;
esac
exit 98
EOF

    cat > "$PF_SHIMS/xcodebuild" <<EOF
#!/bin/sh
echo "xcodebuild \$*" >> "$PF_LOG"
if [ "\$*" != "-version" ]; then
    echo "xcodebuild \$*" >> "$PF_BAD"
    exit 99
fi
case "\${SHIM_XCODE_MODE:-ok}" in
    ok)
        echo "Xcode \${SHIM_XCODE_VERSION:-15.4}"
        echo "Build version 15F31d"
        exit 0 ;;
    fail)
        echo "xcode-select: error: tool 'xcodebuild' requires Xcode" >&2
        exit 1 ;;
    garbage)
        echo "Command Line Tools"
        exit 0 ;;
esac
exit 98
EOF

    cat > "$PF_SHIMS/xcrun" <<EOF
#!/bin/sh
echo "xcrun \$*" >> "$PF_LOG"
case "\$*" in
    "--sdk iphoneos --show-sdk-version")
        if [ "\${SHIM_SDK_IPHONEOS_MODE:-ok}" = "missing" ]; then
            echo "xcrun: error: SDK \"iphoneos\" cannot be located" >&2
            exit 1
        fi
        if [ "\${SHIM_SDK_IPHONEOS_MODE:-ok}" = "garbage" ]; then echo "none"; exit 0; fi
        echo "\${SHIM_SDK_IPHONEOS_VERSION:-17.5}"
        exit 0 ;;
    "--sdk iphonesimulator --show-sdk-version")
        if [ "\${SHIM_SDK_IPHONESIMULATOR_MODE:-ok}" = "missing" ]; then
            echo "xcrun: error: SDK \"iphonesimulator\" cannot be located" >&2
            exit 1
        fi
        echo "\${SHIM_SDK_IPHONESIMULATOR_VERSION:-17.5}"
        exit 0 ;;
    "--find simctl")
        if [ "\${SHIM_SIMCTL_MODE:-ok}" = "missing" ]; then
            echo "xcrun: error: unable to find utility \"simctl\"" >&2
            exit 1
        fi
        echo "/fake/Xcode.app/Contents/Developer/usr/bin/simctl"
        exit 0 ;;
    "simctl list devices")
        case "\${SHIM_SIMCTL_MODE:-ok}" in
            listfail) echo "simctl: simulated failure" >&2; exit 2 ;;
            hang) sleep 30 &
                  echo \$! > "$PF_HANG_PID"
                  wait ;;
        esac
        cat "$PF_LIST"
        exit 0 ;;
esac
echo "xcrun \$*" >> "$PF_BAD"
exit 99
EOF

    chmod 755 "$PF_SHIMS/git" "$PF_SHIMS/flutter" "$PF_SHIMS/dart" "$PF_SHIMS/xcodebuild" "$PF_SHIMS/xcrun"
}

pf_modes_reset() {
    unset SHIM_FLUTTER_MODE SHIM_FLUTTER_VERSION SHIM_FLUTTER_RC
    unset SHIM_DART_MODE SHIM_DART_VERSION SHIM_DART_RC
    unset SHIM_XCODE_MODE SHIM_XCODE_VERSION
    unset SHIM_SDK_IPHONEOS_MODE SHIM_SDK_IPHONEOS_VERSION SHIM_SDK_IPHONESIMULATOR_MODE SHIM_SDK_IPHONESIMULATOR_VERSION
    unset SHIM_SIMCTL_MODE
    unset SHIM_GIT_MODE SHIM_GIT_RC SHIM_GIT_IGNORE_COUNT SHIM_GIT_VERSION_LINE
    unset PF_MISSING PF_CWD PF_PATH_PREFIX PF_PREFLIGHT_SCRIPT PF_BASH PF_ENV_ASSIGN PF_NO_FINGERPRINT
    rm -f "$PF_HANG_PID"
    pf_devices_default
}

# Rebuilds the directory seen by the executor: one link per shim, minus the
# tools listed in PF_MISSING (space-separated), which are then absent from PATH.
# "git" is also removed from the links to the system tools when it is missing.
pf_make_view() {
    local name
    local missing=" ${PF_MISSING:-} "

    rm -f "$PF_VIEW"/*

    for name in $PF_SHIM_NAMES; do
        case "$missing" in
            *" $name "*) ;;
            *) ln -s "$PF_SHIMS/$name" "$PF_VIEW/$name" ;;
        esac
    done

    case "$missing" in
        *" git "*) rm -f "$PF_TOOLS/git" ;;
        *) [[ -e "$PF_TOOLS/git" ]] || ln -s "$PF_REAL_GIT" "$PF_TOOLS/git" ;;
    esac
}

# New CBS-owned isolation. Arguments: ID [COMMIT]
pf_new_isolation() {
    ISO_ID="$1"

    iso_run create "$1" "$SOURCE" "$ISO_ORIGIN" "${2:-$C2}" "$ISO_ROOT"
    iso_expect_pass "PF_CREATE_$1"
}

# Observable state of everything the executor must leave untouched.
pf_fingerprint() {
    # Observing must not write either: optional index refreshes are off.
    GIT_OPTIONAL_LOCKS=0 iso_source_state
    iso_tree_fingerprint "$SOURCE"
    iso_tree_fingerprint "$ISO_ROOT"

    if [[ -d "$EVID" ]]; then
        iso_tree_fingerprint "$EVID"
    else
        echo "EVIDENCE_ROOT_ABSENT"
    fi
}

# Reference request. Argument: isolation id.
pf_req_reset() {
    PF_REQ=(
        "contract_version=1"
        "qualification_id=qual-pf-1"
        "isolation_id=$1"
        "source_repository=$SOURCE"
        "expected_origin=$ISO_ORIGIN"
        "commit=$C2"
        "isolation_root=$ISO_ROOT"
        "evidence_root=$EVID"
        "target=ios-simulator"
        "actions=preflight,analyze"
        "timeout_seconds=20"
        "log_max_bytes=1048576"
        "evidence_retention=keep"
        "cleanup_policy=none"
        "simulator_udid=$PF_UDID_SHUTDOWN"
        "simulator_policy=existing_only"
    )
}

pf_req_set() {
    local key="$1"
    local value="$2"
    local entry
    local found=0
    local updated=()

    for entry in "${PF_REQ[@]}"; do
        if [[ "${entry%%=*}" == "$key" ]]; then
            updated[${#updated[@]}]="$key=$value"
            found=1
        else
            updated[${#updated[@]}]="$entry"
        fi
    done

    [[ "$found" -eq 1 ]] || updated[${#updated[@]}]="$key=$value"

    PF_REQ=("${updated[@]}")
}

pf_req_unset() {
    local entry
    local updated=()

    for entry in "${PF_REQ[@]}"; do
        [[ "${entry%%=*}" == "$1" ]] || updated[${#updated[@]}]="$entry"
    done

    PF_REQ=("${updated[@]}")
}

# pf_run <label> <argument...>
# Runs the executor with the hermetic PATH. Sets PF_OUT, PF_ERR, PF_RC and
# fails the test when the source, the isolation root or the evidence root
# changed in any way (names, sizes, contents).
pf_run() {
    local label="$1"
    local before
    local after
    local script="${PF_PREFLIGHT_SCRIPT:-$PREFLIGHT}"

    shift

    pf_make_view
    : > "$PF_LOG"
    : > "$PF_BAD"
    : > "$PF_GITLOG"

    before=""
    [[ -n "${PF_NO_FINGERPRINT:-}" ]] || before="$(pf_fingerprint)"

    # PF_ENV_ASSIGN: words NAME=VALUE (no space) given to the executor only.
    set +e
    # shellcheck disable=SC2086
    PF_OUT="$(cd "${PF_CWD:-$TMP}" && env ${PF_ENV_ASSIGN:-} PATH="${PF_PATH_PREFIX:-}$PF_VIEW:$PF_TOOLS" "${PF_BASH:-$BASH}" "$script" "$@" 2>"$PF_ERRFILE")"
    PF_RC=$?
    set -e

    PF_ERR="$(cat "$PF_ERRFILE")"

    after=""
    [[ -n "${PF_NO_FINGERPRINT:-}" ]] || after="$(pf_fingerprint)"

    [[ "$before" == "$after" ]] || pf_fail "${label}_STATE_MUTATED"
    [[ -z "$(cat "$PF_BAD")" ]] || pf_fail "${label}_UNEXPECTED_TOOL_CALL_$(head -n 1 "$PF_BAD" | tr ' ' '_')"
}

# Value of a full key ("CBS_FLUTTER_QUAL_RESULT") in the output, first match.
pf_kv() {
    printf '%s\n' "$PF_OUT" | sed -n "s/^$1=//p" | head -n 1
}

# Value of CBS_FLUTTER_QUAL_PREFLIGHT_<suffix>.
pf_value() {
    pf_kv "CBS_FLUTTER_QUAL_PREFLIGHT_$1"
}

pf_check() {
    pf_value "CHECK_$1"
}

pf_check_reason() {
    pf_value "CHECK_$1_REASON"
}

# pf_expect <label> <RESULT> <REASON|-> <rc>
# Verifies the whole structured answer: operation, result, reason, return
# codes (and their agreement with the contract), final RESULT line last.
pf_expect() {
    local label="$1"
    local result="$2"
    local reason="$3"
    local rc="$4"
    local last

    [[ "$PF_RC" -eq "$rc" ]] || pf_fail "${label}_RC_EXPECTED_${rc}_GOT_${PF_RC}"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION)" == "PREFLIGHT" ]] || pf_fail "${label}_OPERATION"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)" == "$result" ]] || pf_fail "${label}_OPERATION_RESULT_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "$result" ]] || pf_fail "${label}_RESULT_$(pf_kv CBS_FLUTTER_QUAL_RESULT)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RC)" == "$rc" ]] || pf_fail "${label}_OPERATION_RC_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RC)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_CONTRACT_VERSION)" == "1" ]] || pf_fail "${label}_CONTRACT_VERSION"

    last="$(printf '%s\n' "$PF_OUT" | tail -n 1)"
    [[ "$last" == "CBS_FLUTTER_QUAL_RESULT=$result" ]] || pf_fail "${label}_RESULT_NOT_LAST"

    if [[ "$reason" == "-" ]]; then
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_REASON)" ]] || pf_fail "${label}_UNEXPECTED_REASON"
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" ]] || pf_fail "${label}_UNEXPECTED_OPERATION_REASON"
        [[ -z "$PF_ERR" ]] || pf_fail "${label}_STDERR_ON_PASS"
    else
        [[ "$(pf_kv CBS_FLUTTER_QUAL_REASON)" == "$reason" ]] || pf_fail "${label}_REASON_EXPECTED_${reason}_GOT_$(pf_kv CBS_FLUTTER_QUAL_REASON)"
        [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" == "$reason" ]] || pf_fail "${label}_OPERATION_REASON"
        [[ "$(cbs_flutter_qual_rc_for_reason "$reason")" == "$rc" ]] || pf_fail "${label}_REASON_RC_DISAGREE"
        [[ "$(cbs_flutter_qual_result_for_reason "$reason")" == "$result" ]] || pf_fail "${label}_REASON_CLASS_DISAGREE"
    fi

    # Every stdout line belongs to the CBS_FLUTTER_QUAL_ namespace.
    if printf '%s\n' "$PF_OUT" | grep -v '^CBS_FLUTTER_QUAL_[A-Z0-9_]*=[A-Za-z0-9._+-]*$' >/dev/null; then
        pf_fail "${label}_FOREIGN_OUTPUT_LINE"
    fi
}

# Every call recorded by the shims belongs to the fixed PREFLIGHT list.
pf_assert_tools_allowed() {
    local line
    local allowed="flutter --version
dart --version
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcrun --sdk iphonesimulator --show-sdk-version
xcrun --find simctl
xcrun simctl list devices"

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        case "
$allowed
" in
            *"
$line
"*) ;;
            *) pf_fail "$1_TOOL_CALL_NOT_ALLOWED_$(printf '%s' "$line" | tr ' ' '_')" ;;
        esac
    done < "$PF_LOG"
}

# Every Git call recorded by the shim is read-only.
pf_assert_git_readonly() {
    local label="$1"
    local line
    local sub

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue

        set -f
        # shellcheck disable=SC2086
        set -- $line
        set +f

        shift

        while [[ "${1:-}" == "-c" || "${1:-}" == "-C" ]]; do
            shift 2
        done

        sub="${1:-}"

        case "$sub" in
            rev-parse|status|cat-file|for-each-ref|--version) ;;
            config) [[ "${2:-}" == "--get" ]] || pf_fail "${label}_GIT_CONFIG_${2:-}" ;;
            worktree) [[ "${2:-}" == "list" ]] || pf_fail "${label}_GIT_WORKTREE_${2:-}" ;;
            remote) [[ "${2:-}" == "get-url" ]] || pf_fail "${label}_GIT_REMOTE_${2:-}" ;;
            branch) [[ "${2:-}" == "--show-current" ]] || pf_fail "${label}_GIT_BRANCH_${2:-}" ;;
            *) pf_fail "${label}_GIT_NOT_READONLY_$sub" ;;
        esac
    done < "$PF_GITLOG"
}

pf_tool_calls() {
    wc -l < "$PF_LOG" | tr -d ' '
}

pf_git_calls() {
    wc -l < "$PF_GITLOG" | tr -d ' '
}

# =============================================================================
# Bounded runner helpers (_cbs_flutter_qual_pf_run). TEST ONLY.
# =============================================================================

PF_FN_RC=""
PF_FN_TIMED_OUT=""
PF_FN_OUT=""
PF_FN_ELAPSED=0

# Body of the shell that runs the runner: it sources the executor (functions
# only, nothing runs) and prints "<rc>", "<timed_out>", then the output.
PF_FN_BODY='source "$1"; shift; _cbs_flutter_qual_pf_reset; _cbs_flutter_qual_pf_run "$@"; printf "%s\n%s\n%s" "$PF_RUN_RC" "$PF_RUN_TIMED_OUT" "$PF_RUN_OUT"'

# pf_fn_run <limit> <command> [argument...]
# Runs the runner alone, under the hermetic PATH. Sets PF_FN_RC,
# PF_FN_TIMED_OUT, PF_FN_OUT and PF_FN_ELAPSED (seconds).
pf_fn_run() {
    local started
    local raw

    pf_make_view
    started=$SECONDS

    set +e
    raw="$(cd "$TMP" && env PATH="$PF_VIEW:$PF_TOOLS" "${PF_BASH:-$BASH}" -c "$PF_FN_BODY" fn "${PF_PREFLIGHT_SCRIPT:-$PREFLIGHT}" "$@" 2>/dev/null)"
    set -e

    PF_FN_ELAPSED=$((SECONDS - started))
    PF_FN_RC="${raw%%"
"*}"
    raw="${raw#*"
"}"
    PF_FN_TIMED_OUT="${raw%%"
"*}"
    PF_FN_OUT="${raw#*"
"}"
    [[ "$raw" == *"
"* ]] || PF_FN_OUT=""
}

# pf_ps_lines <extended regex>: lines of "ps" (pid, command) that match.
# The search itself is filtered out. Never fails.
pf_ps_lines() {
    ps -A -ww -o pid= -o command= | grep -E -e "$1" | grep -v -e 'grep -E' || true
}

# pf_ps_count <extended regex>
pf_ps_count() {
    local lines

    lines="$(pf_ps_lines "$1")"

    if [[ -z "$lines" ]]; then
        echo 0
    else
        printf '%s\n' "$lines" | wc -l | tr -d ' '
    fi
}

# pf_pid_gone <pid> [seconds]: waits until the process no longer runs (a
# zombie waiting for its parent does not count as running). Fails otherwise.
pf_pid_gone() {
    local pid="$1"
    local tries="$((${2:-3} * 10))"
    local state

    while [[ "$tries" -gt 0 ]]; do
        state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"

        case "$state" in
            ""|Z*) return 0 ;;
        esac

        sleep 0.1 2>/dev/null || sleep 1
        tries=$((tries - 1))
    done

    return 1
}
