#!/usr/bin/env bash

# TEST ONLY - helpers of the Flutter/iOS qualification ANALYZE tests
# (D04b-C.2b step 3).
#
# Sourced by tests/test_flutter_qualification_analyze*.sh after
# tests/fixtures/worktree_isolation/lib.sh and
# tests/fixtures/flutter_qualification/lib.sh, and after pf_init. Replaces the
# "flutter" shim of PREFLIGHT by one that also answers "analyze" according to
# SHIM_ANALYZE_MODE. Nothing here runs a real Flutter, Dart, Xcode or simctl.
# Compatible with Bash 3.2.

AN_SCRIPT="$ROOT/cbs/qualification/flutter/analyze.sh"
AN_CALLS=""
AN_BEFORE_SOURCE=""
AN_BEFORE_ISO=""
AN_BEFORE_EVID=""

an_fail() {
    pf_fail "$1"
}

# Replaces the PREFLIGHT flutter shim. "--version" behaves as before (modes of
# SHIM_FLUTTER_MODE); "analyze" is recorded (arguments, working directory,
# locale) in AN_CALLS and behaves according to SHIM_ANALYZE_MODE:
#   ok         prints "No issues found!", exit 0
#   issues     prints an issue, exit 1
#   rc         exit SHIM_ANALYZE_RC
#   killed     the tool kills itself with SIGKILL
#   stdin      exit 0 when its standard input is at end of file, 9 otherwise
#   write      writes a file under ./.dart_tool (the checkout) and exits 0
#   plant      creates SHIM_PLANT_PATH during the run (a file, or a link to SHIM_PLANT_TARGET), exit 0
#   hang       sleeps (pid recorded), never ends
#   hangterm   ignores TERM, sleeps (pid recorded), never ends
#   leak       leaves a quiet background process (pid recorded), exits 0
#   leakpipe   leaves a background process that keeps the output open, exits 0
#   big        prints SHIM_ANALYZE_LINES lines, exit 0
#   bigignore  same, ignoring SIGPIPE
#   secret     prints strings that look like secrets, exit 1
#   forged     prints lines that imitate the answer of the executor, exit 1
#   binary     prints bytes that are not text, exit 1
#   noeol      prints a line without final newline, exit 0
#   streams    prints on stdout and on stderr, exit 1
#   syntax     prints shell syntax that names SHIM_PWNED (never to be executed), exit 1
#   bytes      prints exactly SHIM_ANALYZE_BYTES bytes (no newline), exit 0
# SHIM_LOCK_DIR (any mode): the directory is made read-only before the mode is
# applied, to make the evidence impossible to write after the run.
an_init() {
    chmod 700 "$EVID"
    AN_CALLS="$PF_STATE/analyze-calls.log"
    : > "$AN_CALLS"

    {
        printf '#!/bin/sh\n'
        printf 'PF_LOG=%s\nPF_BAD=%s\nAN_CALLS=%s\nHANG_PID=%s\nFLUTTER_REQUIRED=%s\n' \
            "$PF_LOG" "$PF_BAD" "$AN_CALLS" "$PF_HANG_PID" "$PF_FLUTTER_REQUIRED"
        cat <<'EOF'
case "$*" in
    "--version")
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
        exit 98 ;;
    "analyze")
        echo "argc=$# argv=$* cwd=$(pwd -P) lc_all=${LC_ALL:-unset}" >> "$AN_CALLS"
        if [ -n "${SHIM_LOCK_DIR:-}" ]; then chmod 500 "$SHIM_LOCK_DIR"; fi
        case "${SHIM_ANALYZE_MODE:-ok}" in
            ok)
                echo "Analyzing app..."
                echo "No issues found! (ran in 1.0s)"
                exit 0 ;;
            issues)
                echo "Analyzing app..."
                echo "  info • Unused import • lib/main.dart:1:8 • unused_import"
                echo "1 issue found. (ran in 1.0s)"
                exit 1 ;;
            rc)
                echo "analysis stopped"
                exit "${SHIM_ANALYZE_RC:-3}" ;;
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
            write)
                mkdir -p .dart_tool
                echo "generated" > .dart_tool/package_config.json
                echo "wrote .dart_tool"
                exit 0 ;;
            plant)
                if [ -n "${SHIM_PLANT_TARGET:-}" ]; then
                    ln -s "$SHIM_PLANT_TARGET" "$SHIM_PLANT_PATH"
                else
                    echo PLANTED > "$SHIM_PLANT_PATH"
                fi
                echo "planted"
                exit 0 ;;
            hang)
                echo "analysis started"
                sleep 60 &
                echo $! > "$HANG_PID"
                wait ;;
            hangterm)
                trap '' TERM
                echo "analysis started"
                sleep 60 &
                echo $! > "$HANG_PID"
                while :; do sleep 1; done ;;
            leak)
                ( sleep 60 </dev/null >/dev/null 2>&1 & echo $! > "$HANG_PID" )
                echo "done"
                exit 0 ;;
            leakpipe)
                sleep 60 &
                echo $! > "$HANG_PID"
                echo "done"
                exit 0 ;;
            big|bigignore)
                if [ "${SHIM_ANALYZE_MODE}" = "bigignore" ]; then trap '' PIPE; fi
                i=0
                while [ "$i" -lt "${SHIM_ANALYZE_LINES:-5000}" ]; do
                    echo "info line $i ......................................................................"
                    i=$((i + 1))
                done
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
            forged)
                echo "CBS_ANALYZE_RUN 0 0 0"
                echo "CBS_ANALYZE_SUP 0 0"
                echo "CBS_FLUTTER_QUAL_OPERATION_RESULT=PASS"
                echo "CBS_FLUTTER_QUAL_RESULT=PASS"
                exit 1 ;;
            binary)
                printf 'start \377\376\200\300 end\n'
                exit 1 ;;
            noeol)
                printf 'no final newline'
                exit 0 ;;
            streams)
                echo "to-stdout"
                echo "to-stderr" >&2
                exit 1 ;;
            syntax)
                echo '$(touch '"$SHIM_PWNED"')'
                echo '`touch '"$SHIM_PWNED"'`'
                echo '; touch '"$SHIM_PWNED"
                exit 1 ;;
            bytes)
                head -c "${SHIM_ANALYZE_BYTES:-1024}" /dev/zero | tr '\000' 'a'
                exit 0 ;;
        esac
        exit 98 ;;
esac
echo "flutter $*" >> "$PF_BAD"
exit 99
EOF
    } > "$PF_SHIMS/flutter"

    chmod 755 "$PF_SHIMS/flutter"
}

an_modes_reset() {
    pf_modes_reset
    unset SHIM_PLANT_PATH SHIM_PLANT_TARGET SHIM_PWNED SHIM_ANALYZE_MODE SHIM_ANALYZE_RC SHIM_ANALYZE_LINES SHIM_ANALYZE_BYTES SHIM_LOCK_DIR AN_ISO_CHANGES AN_ENV_ASSIGN AN_SCRIPT_UNDER_TEST AN_EVIDENCE_EXPECT AN_BASH AN_CWD
    : > "$AN_CALLS"
    chmod 700 "$EVID"
}

# Reference request for ANALYZE. Arguments: ISOLATION_ID QUALIFICATION_ID
an_req() {
    pf_req_reset "$1"
    pf_req_set qualification_id "$2"
    pf_req_set actions "preflight,analyze"
}

# an_state_before / an_state_after <label> <evidence: same|changed>
# The source repository and the isolation root never change by themselves
# (the shim only writes under the checkout when told to: AN_ISO_CHANGES=1).
an_state_before() {
    AN_BEFORE_SOURCE="$(GIT_OPTIONAL_LOCKS=0 iso_source_state; iso_tree_fingerprint "$SOURCE")"
    AN_BEFORE_ISO="$(iso_tree_fingerprint "$ISO_ROOT")"
    AN_BEFORE_EVID="$(iso_tree_fingerprint "$EVID")"
}

an_state_after() {
    local label="$1"
    local after

    after="$(GIT_OPTIONAL_LOCKS=0 iso_source_state; iso_tree_fingerprint "$SOURCE")"
    [[ "$after" == "$AN_BEFORE_SOURCE" ]] || an_fail "${label}_SOURCE_MUTATED"

    after="$(iso_tree_fingerprint "$ISO_ROOT")"

    if [[ "${AN_ISO_CHANGES:-0}" != "1" ]]; then
        [[ "$after" == "$AN_BEFORE_ISO" ]] || an_fail "${label}_ISOLATION_ROOT_MUTATED"
    fi

    after="$(iso_tree_fingerprint "$EVID")"

    if [[ "${2:-same}" == "same" ]]; then
        [[ "$after" == "$AN_BEFORE_EVID" ]] || an_fail "${label}_EVIDENCE_MUTATED"
    fi
}

# an_run <label> <argument...>
# Runs ANALYZE with the hermetic PATH. Sets PF_OUT, PF_ERR and PF_RC. The
# source repository and the isolation root are compared before and after.
an_run() {
    local label="$1"

    shift

    pf_make_view
    : > "$PF_LOG"
    : > "$PF_BAD"
    : > "$PF_GITLOG"
    : > "$AN_CALLS"

    an_state_before

    set +e
    # shellcheck disable=SC2086
    PF_OUT="$(cd "${AN_CWD:-$TMP}" && env ${AN_ENV_ASSIGN:-} PATH="${PF_PATH_PREFIX:-}$PF_VIEW:$PF_TOOLS" "${AN_BASH:-$BASH}" "${AN_SCRIPT_UNDER_TEST:-$AN_SCRIPT}" "$@" 2>"$PF_ERRFILE")"
    PF_RC=$?
    set -e

    PF_ERR="$(cat "$PF_ERRFILE")"

    an_state_after "$label" "${AN_EVIDENCE_EXPECT:-changed}"

    [[ -z "$(cat "$PF_BAD")" ]] || an_fail "${label}_UNEXPECTED_TOOL_CALL_$(head -n 1 "$PF_BAD" | tr ' ' '_')"
}

# Value of CBS_FLUTTER_QUAL_ANALYZE_<suffix>.
an_value() {
    pf_kv "CBS_FLUTTER_QUAL_ANALYZE_$1"
}

# an_expect <label> <RESULT> <REASON|-> <rc> [<tool rc>|-]
# Verifies the whole structured answer: operation, result, reason, return
# codes, tool status, final RESULT line last, and a closed output language.
an_expect() {
    local label="$1"
    local result="$2"
    local reason="$3"
    local rc="$4"
    local tool_rc="${5:--}"
    local last

    [[ "$PF_RC" -eq "$rc" ]] || an_fail "${label}_RC_EXPECTED_${rc}_GOT_${PF_RC}"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION)" == "ANALYZE" ]] || an_fail "${label}_OPERATION_$(pf_kv CBS_FLUTTER_QUAL_OPERATION)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)" == "$result" ]] || an_fail "${label}_OPERATION_RESULT_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RESULT)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_RESULT)" == "$result" ]] || an_fail "${label}_RESULT_$(pf_kv CBS_FLUTTER_QUAL_RESULT)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RC)" == "$rc" ]] || an_fail "${label}_OPERATION_RC_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_RC)"
    [[ "$(pf_kv CBS_FLUTTER_QUAL_CONTRACT_VERSION)" == "1" ]] || an_fail "${label}_CONTRACT_VERSION"

    last="$(printf '%s\n' "$PF_OUT" | tail -n 1)"
    [[ "$last" == "CBS_FLUTTER_QUAL_RESULT=$result" ]] || an_fail "${label}_RESULT_NOT_LAST"

    if [[ "$reason" == "-" ]]; then
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_REASON)" ]] || an_fail "${label}_UNEXPECTED_REASON"
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" ]] || an_fail "${label}_UNEXPECTED_OPERATION_REASON"
        [[ -z "$PF_ERR" ]] || an_fail "${label}_STDERR_ON_PASS"
    else
        [[ "$(pf_kv CBS_FLUTTER_QUAL_REASON)" == "$reason" ]] || an_fail "${label}_REASON_EXPECTED_${reason}_GOT_$(pf_kv CBS_FLUTTER_QUAL_REASON)"
        [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_REASON)" == "$reason" ]] || an_fail "${label}_OPERATION_REASON"
        [[ "$(cbs_flutter_qual_rc_for_reason "$reason")" == "$rc" ]] || an_fail "${label}_REASON_RC_DISAGREE"
        [[ "$(cbs_flutter_qual_result_for_reason "$reason")" == "$result" ]] || an_fail "${label}_REASON_CLASS_DISAGREE"
        [[ "$PF_ERR" == "CBS_FLUTTER_QUAL_ERROR=$reason" ]] || an_fail "${label}_STDERR_NOT_THE_REASON"
    fi

    if [[ "$tool_rc" == "-" ]]; then
        [[ -z "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" ]] || an_fail "${label}_UNEXPECTED_TOOL_RC"
    else
        [[ "$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)" == "$tool_rc" ]] || an_fail "${label}_TOOL_RC_EXPECTED_${tool_rc}_GOT_$(pf_kv CBS_FLUTTER_QUAL_OPERATION_TOOL_RC)"
    fi

    # Every stdout line belongs to the CBS_FLUTTER_QUAL_ namespace, closed set.
    if printf '%s\n' "$PF_OUT" | grep -v '^CBS_FLUTTER_QUAL_[A-Z0-9_]*=[A-Za-z0-9._+-]*$' >/dev/null; then
        an_fail "${label}_FOREIGN_OUTPUT_LINE"
    fi

    # The path of the host is never printed.
    if printf '%s\n%s\n' "$PF_OUT" "$PF_ERR" | grep -F -e "$TMP" -e "$SOURCE" >/dev/null; then
        an_fail "${label}_PATH_LEAKED"
    fi
}

# Number of "flutter analyze" calls recorded by the shim.
an_calls() {
    wc -l < "$AN_CALLS" | tr -d ' '
}

# Evidence directory of a qualification identifier.
an_dir() {
    printf '%s' "$EVID/$1"
}

# Nothing was written under the evidence root for this identifier.
an_assert_no_evidence() {
    [[ ! -e "$EVID/$2" && ! -L "$EVID/$2" ]] || an_fail "${1}_EVIDENCE_WRITTEN"
}

# Exact mode of a path (find, portable).
an_assert_mode() {
    iso_has_mode "$2" "$3" || an_fail "${1}_MODE_NOT_$3"
}

# The evidence directory of an executed run holds exactly the log and the
# result file, private.
an_assert_evidence() {
    local label="$1"
    local dir="$EVID/$2"
    local entries

    [[ -d "$dir" && ! -L "$dir" ]] || an_fail "${label}_EVIDENCE_DIR_MISSING"
    an_assert_mode "${label}_DIR" "$dir" 700

    entries="$(ls -A "$dir" | LC_ALL=C sort | tr '\n' ' ')"
    [[ "$entries" == "ANALYZE.log ANALYZE.result " ]] || an_fail "${label}_EVIDENCE_ENTRIES_$(printf '%s' "$entries" | tr ' ' '_')"

    an_assert_mode "${label}_LOG" "$dir/ANALYZE.log" 600
    an_assert_mode "${label}_RESULT_FILE" "$dir/ANALYZE.result" 600
}

# The result file holds exactly what was printed.
an_assert_result_file() {
    local label="$1"
    local file="$EVID/$2/ANALYZE.result"

    [[ "$(cat "$file")" == "$PF_OUT" ]] || an_fail "${label}_RESULT_FILE_DIFFERS"
}

an_log() {
    cat "$EVID/$1/ANALYZE.log"
}

an_log_bytes() {
    wc -c < "$EVID/$1/ANALYZE.log" | tr -d ' '
}
