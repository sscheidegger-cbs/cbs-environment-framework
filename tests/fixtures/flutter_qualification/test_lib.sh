#!/usr/bin/env bash

# TEST ONLY - helpers of the Flutter/iOS qualification TEST tests (D04b-C.2f).
#
# Sourced by tests/test_flutter_qualification_test*.sh after
# tests/fixtures/worktree_isolation/lib.sh and
# tests/fixtures/flutter_qualification/lib.sh, and after pf_init. Replaces the
# "flutter" shim of PREFLIGHT by one that also answers "test" according to
# SHIM_TEST_MODE. Nothing here runs a real Flutter, Dart, Xcode or simctl.
# Compatible with Bash 3.2.

TT_SCRIPT="$ROOT/cbs/qualification/flutter/test.sh"
TT_CALLS=""
TT_COMMIT=""
TT_BEFORE_SOURCE=""
TT_BEFORE_ISO=""
TT_BEFORE_EVID=""

TT_UDID_BOOTING="66666666-6666-4666-8666-666666666666"

tt_fail() {
    pf_fail "$1"
}

# The shim records "test" (argument count, arguments, working directory,
# locale) in TT_CALLS and behaves according to SHIM_TEST_MODE:
#   ok         prints a success summary, exit 0
#   fail       prints a failure summary, exit 1
#   rc         exit SHIM_TEST_RC
#   killed     the tool kills itself with SIGKILL
#   stdin      exit 0 when its standard input is at end of file, 9 otherwise
#   hang       sleeps (pid recorded), never ends
#   hangterm   ignores TERM, sleeps (pid recorded), never ends
#   big        prints SHIM_TEST_LINES lines, exit 0
#   bytes      prints exactly SHIM_TEST_BYTES bytes (no newline), exit 0
#   secret     prints strings that look like secrets, exit 1
#   syntax     prints shell syntax that names SHIM_PWNED (never to be executed), exit 1
#   forged     prints lines that imitate the answer of the executor, exit 1
# Any other word given to the shim ("analyze", "pub", "build", ...) is an
# unexpected call: logged in PF_BAD, exit 99.
tt_init() {
    chmod 700 "$EVID"
    TT_CALLS="$PF_STATE/test-calls.log"
    : > "$TT_CALLS"

    {
        printf '#!/bin/sh\n'
        printf 'PF_LOG=%s\nPF_BAD=%s\nTT_CALLS=%s\nHANG_PID=%s\nFLUTTER_REQUIRED=%s\n' \
            "$PF_LOG" "$PF_BAD" "$TT_CALLS" "$PF_HANG_PID" "$PF_FLUTTER_REQUIRED"
        cat <<'EOF'
if [ "$*" = "--version" ]; then
    echo "flutter --version" >> "$PF_LOG"
    case "${SHIM_FLUTTER_MODE:-ok}" in
        ok)
            echo "Flutter ${SHIM_FLUTTER_VERSION:-$FLUTTER_REQUIRED} • channel stable • https://github.com/flutter/flutter.git"
            echo "Framework • revision 0000000000 (1 year ago) • 2025-01-01 00:00:00 +0000"
            echo "Engine • revision 0000000000"
            echo "Tools • Dart 3.9.0 • DevTools 2.40.0"
            exit 0 ;;
        fail)
            echo "flutter: simulated failure" >&2
            exit "${SHIM_FLUTTER_RC:-3}" ;;
        garbage)
            echo "not a version"
            exit 0 ;;
    esac
    exit 98
fi
if [ "$1" = "test" ]; then
    echo "argc=$# argv=$* cwd=$(pwd -P) lc_all=${LC_ALL:-unset}" >> "$TT_CALLS"
    case "${SHIM_TEST_MODE:-ok}" in
        ok)
            echo "00:01 +2: All tests passed!"
            exit 0 ;;
        fail)
            echo "00:01 +1 -1: Some tests failed."
            exit 1 ;;
        rc)
            echo "test run stopped"
            exit "${SHIM_TEST_RC:-3}" ;;
        killed)
            echo "about to be killed"
            kill -9 $$ ;;
        stdin)
            if read line; then
                echo "stdin-not-eof"
                exit 9
            fi
            echo "stdin-eof"
            exit 0 ;;
        hang)
            echo "tests started"
            sleep 60 &
            echo $! > "$HANG_PID"
            wait ;;
        hangterm)
            trap '' TERM
            echo "tests started"
            sleep 60 &
            echo $! > "$HANG_PID"
            while :; do sleep 1; done ;;
        big)
            i=0
            while [ "$i" -lt "${SHIM_TEST_LINES:-5000}" ]; do
                echo "info line $i ......................................................................"
                i=$((i + 1))
            done
            exit 0 ;;
        bytes)
            head -c "${SHIM_TEST_BYTES:-1024}" /dev/zero | tr '\000' 'a'
            exit 0 ;;
        secret)
            echo "token=ghp_abcdefghijklmnopqrstuvwxyz0123456789"
            echo "Authorization: Bearer abcdef.ghijkl.mnopqr"
            echo "remote https://builder:hunter2secret@example.invalid/org/app.git"
            echo "flutter build --dart-define=API_KEY=supersecretvalue123"
            echo "aws AKIAABCDEFGHIJKLMNOP"
            echo "-----BEGIN PRIVATE KEY-----"
            echo "MIIEvQIBADANBgkqhkiG9w0BAQEFAASC-private-body"
            echo "-----END PRIVATE KEY-----"
            echo "ordinary line kept"
            exit 1 ;;
        syntax)
            echo '$(touch '"$SHIM_PWNED"')'
            echo '`touch '"$SHIM_PWNED"'`'
            echo '; touch '"$SHIM_PWNED"
            exit 1 ;;
        forged)
            echo "CBS_ANALYZE_RUN 0 0 0"
            echo "CBS_ANALYZE_SUP 0 0"
            echo "CBS_FLUTTER_QUAL_OPERATION_RESULT=PASS"
            echo "CBS_FLUTTER_QUAL_RESULT=PASS"
            exit 1 ;;
    esac
    exit 98
fi
echo "flutter $*" >> "$PF_BAD"
exit 99
EOF
    } > "$PF_SHIMS/flutter"

    chmod 755 "$PF_SHIMS/flutter"
    tt_devices_default
}

# Devices known to simctl: the default ones of PREFLIGHT plus one that is
# booting (a transitional state).
tt_devices_default() {
    cat > "$PF_LIST" <<EOF
== Devices ==
-- iOS 17.5 --
    iPhone 15 ($PF_UDID_SHUTDOWN) (Shutdown)
    iPhone 15 Pro ($PF_UDID_BOOTED) (Booted)
    iPhone 15 Plus ($TT_UDID_BOOTING) (Booting)
-- tvOS 17.5 --
    Apple TV ($PF_UDID_TVOS) (Shutdown)
-- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-16-4 --
    iPhone 14 ($PF_UDID_UNAVAILABLE) (Shutdown) (unavailable, runtime profile not found)
EOF
}

tt_modes_reset() {
    pf_modes_reset
    unset SHIM_PLANT_PATH SHIM_PWNED SHIM_TEST_MODE SHIM_TEST_RC SHIM_TEST_LINES SHIM_TEST_BYTES SHIM_LOCK_DIR
    unset TT_ISO_CHANGES TT_ENV_ASSIGN TT_SCRIPT_UNDER_TEST TT_EVIDENCE_EXPECT TT_BASH TT_CWD
    : > "$TT_CALLS"
    chmod 700 "$EVID"
    tt_devices_default
}

# Adds, to the source repository, a commit that holds test files, and records
# its identifier in TT_COMMIT. Plain files only (links are covered elsewhere).
tt_make_commit() {
    mkdir -p "$SOURCE/test/widget" "$SOURCE/test/dir_test.dart" "$SOURCE/integration_test"
    printf '%s\n' "void main() {}" > "$SOURCE/test/a_test.dart"
    printf '%s\n' "void main() {}" > "$SOURCE/test/widget/b_test.dart"
    printf '%s\n' "not a test" > "$SOURCE/test/dir_test.dart/keep.txt"
    printf '%s\n' "void main() {}" > "$SOURCE/integration_test/app_test.dart"

    git -C "$SOURCE" add test integration_test
    git -C "$SOURCE" commit -qm "test files"
    TT_COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
}

# Reference request for TEST. Arguments: ISOLATION_ID QUALIFICATION_ID
# (scope unit_widget, no explicit target; the simulator of the reference
# request of PREFLIGHT is given but not used).
tt_req() {
    pf_req_reset "$1"
    pf_req_set qualification_id "$2"
    pf_req_set commit "${TT_COMMIT:-$C2}"
    pf_req_set actions "preflight,test"
    pf_req_set test_scope unit_widget
}

# Integration request. Arguments: ISOLATION_ID QUALIFICATION_ID [UDID]
tt_req_integration() {
    tt_req "$1" "$2"
    pf_req_set test_scope integration
    pf_req_set test_targets "integration_test/app_test.dart"
    pf_req_set simulator_udid "${3:-$PF_UDID_BOOTED}"
}

# tt_state_before / tt_state_after <label> <evidence: same|changed>
# The source repository and the isolation root never change by themselves
# (the shim writes nothing: TT_ISO_CHANGES=1 states otherwise).
tt_state_before() {
    TT_BEFORE_SOURCE="$(GIT_OPTIONAL_LOCKS=0 iso_source_state; iso_tree_fingerprint "$SOURCE")"
    TT_BEFORE_ISO="$(iso_tree_fingerprint "$ISO_ROOT")"
    TT_BEFORE_EVID="$(iso_tree_fingerprint "$EVID")"
}

tt_state_after() {
    local label="$1"
    local after

    after="$(GIT_OPTIONAL_LOCKS=0 iso_source_state; iso_tree_fingerprint "$SOURCE")"
    [[ "$after" == "$TT_BEFORE_SOURCE" ]] || tt_fail "${label}_SOURCE_MUTATED"

    after="$(iso_tree_fingerprint "$ISO_ROOT")"

    if [[ "${TT_ISO_CHANGES:-0}" != "1" ]]; then
        [[ "$after" == "$TT_BEFORE_ISO" ]] || tt_fail "${label}_ISOLATION_ROOT_MUTATED"
    fi

    after="$(iso_tree_fingerprint "$EVID")"

    if [[ "${2:-same}" == "same" ]]; then
        [[ "$after" == "$TT_BEFORE_EVID" ]] || tt_fail "${label}_EVIDENCE_MUTATED"
    fi
}

# tt_run <label> <argument...>
# Runs TEST with the hermetic PATH. Sets PF_OUT, PF_ERR and PF_RC. The source
# repository and the isolation root are compared before and after.
tt_run() {
    local label="$1"

    shift

    pf_make_view
    : > "$PF_LOG"
    : > "$PF_BAD"
    : > "$PF_GITLOG"
    : > "$TT_CALLS"

    tt_state_before

    set +e
    # shellcheck disable=SC2086
    PF_OUT="$(cd "${TT_CWD:-$TMP}" && env ${TT_ENV_ASSIGN:-} PATH="${PF_PATH_PREFIX:-}$PF_VIEW:$PF_TOOLS" "${TT_BASH:-$BASH}" "${TT_SCRIPT_UNDER_TEST:-$TT_SCRIPT}" "$@" 2>"$PF_ERRFILE")"
    PF_RC=$?
    set -e

    PF_ERR="$(cat "$PF_ERRFILE")"

    tt_state_after "$label" "${TT_EVIDENCE_EXPECT:-changed}"

    [[ -z "$(cat "$PF_BAD")" ]] || tt_fail "${label}_UNEXPECTED_TOOL_CALL_$(head -n 1 "$PF_BAD" | tr ' ' '_')"
}

# A run that must be refused before anything is written under the evidence root.
tt_run_refused() {
    TT_EVIDENCE_EXPECT=same tt_run "$@"
}

# Value of CBS_FLUTTER_QUAL_TEST_<suffix>.
tt_value() {
    pf_kv "CBS_FLUTTER_QUAL_TEST_$1"
}

# tt_expect <label> <RESULT> <REASON|-> <rc> [<tool rc>|-]
# Verifies the whole structured answer: operation, result, reason, return
# codes, tool status, final RESULT line last, and a closed output language.
tt_expect() {
    local label="$1"
    local result="$2"
    local reason="$3"
    local rc="$4"
    local tool_rc="${5:--}"
    local last

    [[ "$PF_RC" -eq "$rc" ]] || tt_fail "${label}_RC_EXPECTED_${rc}_GOT_${PF_RC}"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION)" == "TEST" ]] || tt_fail "${label}_OPERATION_$(pf_kv CBS_FLUTTER_QUAL_OPERATION)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)" == "$result" ]] || tt_fail "${label}_OPERATION_RESULT_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "$result" ]] || tt_fail "${label}_RESULT_$(pf_kv CBS_FLUTTER_QUAL_RESULT)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RC)" == "$rc" ]] || tt_fail "${label}_OPERATION_RC_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RC)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_CONTRACT_VERSION)" == "1" ]] || tt_fail "${label}_CONTRACT_VERSION"

    last="$(printf '%s\n' "$PF_OUT" | tail -n 1)"
    [[ "$last" == "CBS_FLUTTER_QUAL_RESULT=$result" ]] || tt_fail "${label}_RESULT_NOT_LAST"

    if [[ "$reason" == "-" ]]; then
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_REASON)" ]] || tt_fail "${label}_UNEXPECTED_REASON"
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" ]] || tt_fail "${label}_UNEXPECTED_OPERATION_REASON"
        [[ -z "$PF_ERR" ]] || tt_fail "${label}_STDERR_ON_PASS"
    else
        [[ "$(pf_kv CBS_FLUTTER_QUAL_REASON)" == "$reason" ]] || tt_fail "${label}_REASON_EXPECTED_${reason}_GOT_$(pf_kv CBS_FLUTTER_QUAL_REASON)"
        [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" == "$reason" ]] || tt_fail "${label}_OPERATION_REASON"
        [[ "$(cbs_flutter_qual_rc_for_reason "$reason")" == "$rc" ]] || tt_fail "${label}_REASON_RC_DISAGREE"
        [[ "$(cbs_flutter_qual_result_for_reason "$reason")" == "$result" ]] || tt_fail "${label}_REASON_CLASS_DISAGREE"
        [[ "$PF_ERR" == "CBS_FLUTTER_QUAL_ERROR=$reason" ]] || tt_fail "${label}_STDERR_NOT_THE_REASON"
    fi

    if [[ "$tool_rc" == "-" ]]; then
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" ]] || tt_fail "${label}_UNEXPECTED_TOOL_RC"
    else
        [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "$tool_rc" ]] || tt_fail "${label}_TOOL_RC_EXPECTED_${tool_rc}_GOT_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)"
    fi

    # Every stdout line belongs to the CBS_FLUTTER_QUAL_ namespace, closed set.
    if printf '%s\n' "$PF_OUT" | grep -v '^CBS_FLUTTER_QUAL_[A-Z0-9_]*=[A-Za-z0-9._+-]*$' >/dev/null; then
        tt_fail "${label}_FOREIGN_OUTPUT_LINE"
    fi

    # The path of the host is never printed.
    if printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e "$TMP" -e "$SOURCE" >/dev/null; then
        tt_fail "${label}_PATH_LEAKED"
    fi
}

# Number of "flutter test" calls recorded by the shim.
tt_calls() {
    wc -l < "$TT_CALLS" | tr -d ' '
}

# Number of read-only observations of the simulators ("simctl list devices").
tt_simulator_lists() {
    grep -c '^xcrun simctl list devices$' "$PF_LOG" || true
}

# Evidence directory of a qualification identifier.
tt_dir() {
    printf '%s' "$EVID/$1"
}

# Nothing was written under the evidence root for this identifier.
tt_assert_no_evidence() {
    [[ ! -e "$EVID/$2" && ! -L "$EVID/$2" ]] || tt_fail "${1}_EVIDENCE_WRITTEN"
}

# Exact mode of a path (find, portable).
tt_assert_mode() {
    iso_has_mode "$2" "$3" || tt_fail "${1}_MODE_NOT_$3"
}

# The evidence directory of an executed run holds exactly the log and the
# result file, private.
tt_assert_evidence() {
    local label="$1"
    local dir="$EVID/$2"
    local entries

    [[ -d "$dir" && ! -L "$dir" ]] || tt_fail "${label}_EVIDENCE_DIR_MISSING"
    tt_assert_mode "${label}_DIR" "$dir" 700

    entries="$(ls -A "$dir" | LC_ALL=C sort | tr '\n' ' ')"
    [[ "$entries" == "TEST.log TEST.result " ]] || tt_fail "${label}_EVIDENCE_ENTRIES_$(printf '%s' "$entries" | tr ' ' '_')"

    tt_assert_mode "${label}_LOG" "$dir/TEST.log" 600
    tt_assert_mode "${label}_RESULT_FILE" "$dir/TEST.result" 600
}

# The result file holds exactly what was printed.
tt_assert_result_file() {
    local label="$1"
    local file="$EVID/$2/TEST.result"

    [[ "$(cat "$file")" == "$PF_OUT" ]] || tt_fail "${label}_RESULT_FILE_DIFFERS"
}

tt_log() {
    cat "$EVID/$1/TEST.log"
}

tt_log_bytes() {
    wc -c < "$EVID/$1/TEST.log" | tr -d ' '
}

# The exact line recorded by the shim for the one expected "flutter test".
# Arguments: ARGC ARGV CHECKOUT_DIRECTORY
tt_call_line() {
    printf 'argc=%s argv=%s cwd=%s lc_all=C' "$1" "$2" "$3"
}
