#!/usr/bin/env bash

# D04b-C.2b step 3: portability of the Flutter/iOS qualification ANALYZE
# (Linux, and macOS with /bin/bash 3.2 and BSD utilities).
#
# What this test proves, and what it does not:
#   1. a static scan forbids Bash 4+ constructs and GNU-only options in the
#      executor, the fixture and the ANALYZE tests;
#   2. the executor runs (PASS, tool failure, timeout, gate refusal) behind a
#      strict sed wrapper that rejects every GNU-only usage, under the C and
#      POSIX locales;
#   3. when a genuine Bash 3.2 is available, the ANALYZE behaviour and
#      security tests are executed with it. Otherwise this step is NOT_RUN.
#
# On Linux, none of this replaces a run on a native Mac: the macOS marker stays
# NOT_RUN unless this very test runs on Darwin with a genuine Bash 3.2 and every
# step passes.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANALYZE="$ROOT/cbs/qualification/flutter/analyze.sh"
EXECUTION="$ROOT/cbs/qualification/flutter/execution.sh"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_ANALYZE_PORTABILITY"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"
source "$ROOT/tests/fixtures/flutter_qualification/analyze_lib.sh"
source "$CONTRACT"

# ---------------------------------------------------------------- 0. files and syntax

CODE_FILES="$ANALYZE $EXECUTION $ROOT/tests/fixtures/flutter_qualification/analyze_lib.sh"
TEST_FILES="$ROOT/tests/test_flutter_qualification_analyze.sh $ROOT/tests/test_flutter_qualification_analyze_security.sh"

for file in $CODE_FILES $TEST_FILES "$ROOT/tests/test_flutter_qualification_analyze_portability.sh"; do
    [[ -f "$file" ]] || pf_fail "FILE_MISSING_$file"
    bash -n "$file" || pf_fail "SYNTAX_$file"
done

echo "${TEST_PREFIX}_SYNTAX=PASS"

# ---------------------------------------------------------------- 1. static scan

# Bash 4+ constructs (not available in Bash 3.2).
BASH4='mapfile|readarray|declare[[:space:]]+-[a-zA-Z]*[Ag]|local[[:space:]]+-[a-zA-Z]*[nA]|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}|;;&|;&[[:space:]]*$|\|&([[:space:]]|$)|&>>|coproc|\[\[[[:space:]]+-[vR][[:space:]]|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}|\$(BASHPID|EPOCHSECONDS|EPOCHREALTIME|SRANDOM)|wait[[:space:]]+-n|shopt[[:space:]]+-s[[:space:]]+(globstar|lastpipe|nocasematch|assoc_expand_once)|read[[:space:]]+-[a-zA-Z]*[iNt]|\$\{[A-Za-z_][A-Za-z0-9_]*@[UuLlQEPAaKk]\}|=~[[:space:]]+["'"'"']|\|\|=|printf[[:space:]]+-v[[:space:]]+[A-Za-z_]+\['

# GNU-only tools and options (absent or different on macOS).
GNU_ONLY='find[^|]*[[:space:]](-printf|-regextype|-xtype|-readable|-writable|-executable|-newer[a-zA-Z]+|-delete|-fprint[a-z0-9]*|-quit|-samefile)|find[^|]*-perm[[:space:]]+[/+]|sed[[:space:]]+(-[a-zA-Z]*[irzsu][a-zA-Z]*|--[a-z])|sed[^|]*\\[+?|]|grep[[:space:]]+(-[a-zA-Z]*P|--[a-z])|xargs[[:space:]]+-r|sort[[:space:]]+-[a-zA-Z]*[VR]|head[[:space:]]+-n[[:space:]]+-|cp[[:space:]]+-[a-zA-Z]*a|ls[[:space:]]+--|du[[:space:]]+-b|readlink[[:space:]]+-f|realpath|stat[[:space:]]+-[cf]|date[[:space:]]+-d|mktemp[[:space:]]+--|(^|[;&|({[:space:]])(seq|tac|shuf|md5sum|sha1sum|sha256sum|truncate|flock|timeout|gtimeout)[[:space:]]|base64[[:space:]]+-w|tr[[:space:]]+--|printf[[:space:]]+.*%\(|\$EPOCH|sed[^|]*\\n|echo[[:space:]]+-e[[:space:]]|head[[:space:]]+-c[[:space:]]+-|cut[[:space:]]+--|sleep[[:space:]]+[0-9.]*[smhd]([[:space:]]|$)'

# find always receives its path first (BSD requirement).
FIND_WITHOUT_PATH='(^|[^a-zA-Z_./-])find[[:space:]]+-'

for file in $CODE_FILES $TEST_FILES; do
    if pf_code_matches "$file" "$BASH4"; then
        pf_fail "STATIC_BASH4_$(basename "$file")"
    fi

    if pf_code_matches "$file" "$GNU_ONLY"; then
        pf_fail "STATIC_GNU_ONLY_$(basename "$file")"
    fi

    if pf_code_matches "$file" "$FIND_WITHOUT_PATH"; then
        pf_fail "STATIC_FIND_WITHOUT_PATH_$(basename "$file")"
    fi
done

# The executor itself (the operation file and the common engine it sources)
# reaches only these tools directly (everything else comes through PREFLIGHT,
# the contract and the isolation manager).
for tool in tr grep awk cat tail cut sort uniq wc date stat readlink realpath basename ls od; do
    for executor_file in "$ANALYZE" "$EXECUTION"; do
        if pf_code_matches "$executor_file" "(^|[;&|({]|\\\$\\()[[:space:]]*${tool}[[:space:]]"; then
            pf_fail "STATIC_UNEXPECTED_TOOL_$tool"
        fi
    done
done

# No empty-array expansion under "set -u" (fatal in Bash 3.2): the only array
# the executor expands is PIPESTATUS, which is never empty. "$@" is not an array
# in this sense.
ARRAYS="$(cat "$ANALYZE" "$EXECUTION" | grep -Ev '^[[:space:]]*#' | grep -Eo '\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}' | sort -u || true)"
[[ "$ARRAYS" == '${PIPESTATUS[@]}' ]] || pf_fail "STATIC_ARRAY_EXPANSIONS_$ARRAYS"

# Bounded repetitions of the regular expressions stay under the 255 limit of
# the BSD regular expression library, and no regular expression is written
# inline (a quoted right-hand side is literal in Bash 3.2).
BOUNDS="$(cat "$ANALYZE" "$EXECUTION" | grep -Ev '^[[:space:]]*#' |
    grep -Eo '\{[0-9]+(,[0-9]+)?\}' | tr -d '{}' | tr ',' ' ' || true)"

for bound in $BOUNDS; do
    [[ "$bound" -le 255 ]] || pf_fail "STATIC_REGEX_REPETITION_OVER_255_$bound"
done

for executor_file in "$ANALYZE" "$EXECUTION"; do
    if pf_code_matches "$executor_file" '=~[[:space:]]+[^$[:space:]]'; then
        pf_fail "STATIC_REGEX_NOT_IN_VARIABLE"
    fi
done

# The texts run by a fresh bash do not use "case" inside "$( )" (Bash 3.2
# parsing), nor here-strings.
for executor_file in "$ANALYZE" "$EXECUTION"; do
    if pf_code_matches "$executor_file" '<<<'; then
        pf_fail "STATIC_HERE_STRING"
    fi
done

echo "${TEST_PREFIX}_STATIC_SCAN=PASS"

# ---------------------------------------------------------------- 2. strict sed, locales

iso_fixture_init
pf_init
an_init

REAL_SED="$(command -v sed)"
[[ -x "$REAL_SED" ]] || pf_fail "SED_NOT_FOUND"

# The strict wrapper takes the place of sed in the tools the executor can reach.
rm -f "$PF_TOOLS/sed"
cp "$ROOT/tests/fixtures/worktree_isolation/strict_sed.sh" "$PF_TOOLS/sed"
chmod 755 "$PF_TOOLS/sed"

STRICT_LOG="$TMP/strict-sed.log"

strict_env() {
    # $1: locale
    printf 'LC_ALL=%s CBS_SHIM_REAL_SED=%s CBS_SHIM_TOOLLOG=%s' "$1" "$REAL_SED" "$STRICT_LOG"
}

strict_check() {
    local label="$1"

    if grep -q '^REJECTED ' "$STRICT_LOG"; then
        pf_fail "${label}_STRICT_SED_REJECTED_$(grep '^REJECTED ' "$STRICT_LOG" | head -n 1 | tr -c 'A-Za-z0-9._-' '_')"
    fi
}

pf_new_isolation iso-pt
iso_snapshot_source

SEQ=0
for locale in C POSIX; do
    SEQ=$((SEQ + 1))
    : > "$STRICT_LOG"
    an_modes_reset

    # PASS
    AN_ENV_ASSIGN="$(strict_env "$locale")"
    an_req iso-pt "qual-pt-pass-$SEQ"
    an_run "PASS_$locale" "${PF_REQ[@]}"
    an_expect "PASS_$locale" PASS - 0 0
    strict_check "PASS_$locale"

    # Not vacuous: sed was really exercised through the strict wrapper.
    grep -q '^sed ' "$STRICT_LOG" || pf_fail "STRICT_SED_NOT_EXERCISED_$locale"

    # Tool failure, with its output kept.
    export SHIM_ANALYZE_MODE=issues
    AN_ENV_ASSIGN="$(strict_env "$locale")"
    an_req iso-pt "qual-pt-issues-$SEQ"
    an_run "ISSUES_$locale" "${PF_REQ[@]}"
    an_expect "ISSUES_$locale" FAIL COMMAND_FAILED 130 1
    strict_check "ISSUES_$locale"

    # Timeout.
    export SHIM_ANALYZE_MODE=hang
    AN_ENV_ASSIGN="$(strict_env "$locale")"
    an_req iso-pt "qual-pt-hang-$SEQ"
    pf_req_set timeout_seconds 3
    an_run "TIMEOUT_$locale" "${PF_REQ[@]}"
    an_expect "TIMEOUT_$locale" FAIL TIMEOUT 131
    strict_check "TIMEOUT_$locale"
    pf_pid_gone "$(cat "$PF_HANG_PID")" 5 || pf_fail "TIMEOUT_${locale}_PROCESS_SURVIVED"

    # Gate refusal: no flutter on the PATH.
    export SHIM_ANALYZE_MODE=ok
    PF_MISSING="flutter"
    AN_ENV_ASSIGN="$(strict_env "$locale")"
    an_req iso-pt "qual-pt-gate-$SEQ"
    AN_EVIDENCE_EXPECT=same an_run "GATE_$locale" "${PF_REQ[@]}"
    an_expect "GATE_$locale" NOT_RUN PREFLIGHT_NOT_PASSED 136
    strict_check "GATE_$locale"
    unset PF_MISSING
done

unset AN_ENV_ASSIGN
an_modes_reset

echo "${TEST_PREFIX}_STRICT_SED_LOCALES=PASS"

# ---------------------------------------------------------------- 3. native Bash 3.2 (only if a genuine one exists)

bash_version() {
    "$1" -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null || true
}

BASH32=""
for candidate in "$BASH" /bin/bash /usr/bin/bash /usr/local/bin/bash; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue

    if [[ "$(bash_version "$candidate")" == "3.2" ]]; then
        BASH32="$candidate"
        break
    fi
done

echo "${TEST_PREFIX}_INTERPRETER_UNDER_TEST=${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
echo "${TEST_PREFIX}_PLATFORM=$(uname -s)"

NATIVE_32="NOT_RUN"

if [[ -n "$BASH32" ]]; then
    NATIVE_32="PASS"

    for suite in analyze analyze_security; do
        LOG="$TMP/native-bash32-$suite.log"
        MARKER="TEST_FLUTTER_QUALIFICATION_$(printf '%s' "$suite" | tr 'a-z' 'A-Z')_RESULT=PASS"

        set +e
        "$BASH32" "$ROOT/tests/test_flutter_qualification_$suite.sh" > "$LOG" 2>&1
        RC=$?
        set -e

        if [[ "$RC" -ne 0 ]] || ! grep -Fxq "$MARKER" "$LOG"; then
            pf_fail "NATIVE_BASH_3_2_${suite}_RC_${RC}"
        fi
    done
else
    echo "${TEST_PREFIX}_NATIVE_BASH_3_2_REASON=NO_BASH_3_2_AVAILABLE"
fi

echo "${TEST_PREFIX}_NATIVE_BASH_3_2=$NATIVE_32"

# The macOS marker is PASS only on Darwin, with a genuine Bash 3.2, and when
# every step above passed (a failure exits before this point).
if [[ "$(uname -s)" == "Darwin" && "$NATIVE_32" == "PASS" ]]; then
    echo "${TEST_PREFIX}_NATIVE_MACOS=PASS"
else
    echo "${TEST_PREFIX}_NATIVE_MACOS=NOT_RUN"
fi

echo "${TEST_PREFIX}_RESULT=PASS"
