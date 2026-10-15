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
