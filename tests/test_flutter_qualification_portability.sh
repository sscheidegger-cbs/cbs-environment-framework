#!/usr/bin/env bash

# D04b-C.2b step 1: portability of the Flutter/iOS qualification contract
# (Linux, and macOS with /bin/bash 3.2 and BSD utilities).
#
# What this test proves, and what it does not:
#   1. a static scan forbids Bash 4+ constructs and GNU-only options in the
#      contract, the fixture and the tests;
#   2. the contract runs with a restricted tool set (only sed and dirname are
#      reachable), behind a strict sed wrapper that rejects every GNU-only
#      usage, with "set -u", and under several locales;
#   3. when a genuine Bash 3.2 is available, the contract and security tests
#      are executed with it. Otherwise this step is reported NOT_RUN.
#
# On Linux, none of this replaces a run on a native Mac: the macOS marker stays
# NOT_RUN unless this very test runs on Darwin and every step passes.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_PORTABILITY"

source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"

fq_init

# ---------------------------------------------------------------- 0. files and syntax

CODE_FILES="$CONTRACT $ROOT/tests/fixtures/flutter_qualification/lib.sh"
TEST_FILES="$ROOT/tests/test_flutter_qualification_contract.sh $ROOT/tests/test_flutter_qualification_security.sh"

for file in $CODE_FILES $TEST_FILES "$ROOT/tests/test_flutter_qualification_portability.sh"; do
    [[ -f "$file" ]] || fq_fail "FILE_MISSING_$file"
    bash -n "$file" || fq_fail "SYNTAX_$file"
done

echo "${TEST_PREFIX}_SYNTAX=PASS"

# ---------------------------------------------------------------- 1. static scan

# Bash 4+ constructs (not available in Bash 3.2). The two patterns that mention
# characters used by the regular expressions of the security test are limited
# to the code files.
BASH4='mapfile|readarray|declare[[:space:]]+-[a-zA-Z]*[Ag]|local[[:space:]]+-[a-zA-Z]*[nA]|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}|;;&|;&[[:space:]]*$|\|&([[:space:]]|$)|&>>|coproc|\[\[[[:space:]]+-[vR][[:space:]]|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}|\$(BASHPID|EPOCHSECONDS|EPOCHREALTIME|SRANDOM)|wait[[:space:]]+-n|shopt[[:space:]]+-s[[:space:]]+(globstar|lastpipe|nocasematch|assoc_expand_once)|read[[:space:]]+-[a-zA-Z]*[iNt]|\$\{[A-Za-z_][A-Za-z0-9_]*@[UuLlQEPAaKk]\}|=~[[:space:]]+["'"'"']'

# GNU-only tools and options (absent or different on macOS).
GNU_ONLY='find[^|]*[[:space:]](-printf|-regextype|-xtype|-readable|-writable|-executable|-newer[a-zA-Z]+|-delete|-fprint[a-z0-9]*|-quit|-samefile)|find[^|]*-perm[[:space:]]+[/+]|sed[[:space:]]+(-[a-zA-Z]*[irzsu][a-zA-Z]*|--[a-z])|sed[^|]*\\[+?|]|grep[[:space:]]+(-[a-zA-Z]*P|--[a-z])|xargs[[:space:]]+-r|sort[[:space:]]+-[a-zA-Z]*[VR]|head[[:space:]]+-n[[:space:]]+-|cp[[:space:]]+-[a-zA-Z]*a|ls[[:space:]]+--|du[[:space:]]+-b|readlink[[:space:]]+-f|realpath|stat[[:space:]]+-[cf]|date[[:space:]]+-d|mktemp[[:space:]]+--|(^|[;&|({[:space:]])(seq|tac|shuf|md5sum|sha1sum|sha256sum|truncate|flock|gtimeout)[[:space:]]|base64[[:space:]]+-w|tr[[:space:]]+--|printf[[:space:]]+.*%\(|\$EPOCH|sed[^|]*\\n|echo[[:space:]]+-e[[:space:]]'

# find always receives its path first (BSD requirement).
FIND_WITHOUT_PATH='(^|[^a-zA-Z_./-])find[[:space:]]+-'

for file in $CODE_FILES; do
    if fq_code_matches "$file" "$BASH4"; then
        fq_fail "STATIC_BASH4_$file"
    fi
done

for file in $TEST_FILES; do
    # Same scan: the regular expressions of the security test are inert
    # strings and do not contain any of these constructs.
    if fq_code_matches "$file" "$BASH4"; then
        fq_fail "STATIC_BASH4_$file"
    fi
done

for file in $CODE_FILES $TEST_FILES; do
    if fq_code_matches "$file" "$GNU_ONLY"; then
        fq_fail "STATIC_GNU_ONLY_$file"
    fi

    if fq_code_matches "$file" "$FIND_WITHOUT_PATH"; then
        fq_fail "STATIC_FIND_WITHOUT_PATH_$file"
    fi
done

# The contract runs sed and dirname only: nothing else is reachable.
for tool in tr grep awk cat head tail cut sort uniq wc date stat readlink realpath basename; do
    if fq_code_matches "$CONTRACT" "(^|[;&|({]|\\\$\\()[[:space:]]*${tool}[[:space:]]"; then
        fq_fail "STATIC_UNEXPECTED_TOOL_$tool"
    fi
done

# Regular expressions: stored in variables (a quoted right-hand side is literal
# in Bash 3.2) and every repetition bound stays below the 255 limit of the BSD
# regular expression library.
BOUNDS="$(grep -Ev '^[[:space:]]*#' "$CONTRACT" |
    grep -Eo '\{[0-9]+(,[0-9]+)?\}' | tr -d '{}' | tr ',' ' ' || true)"
BOUND_COUNT=0

for bound in $BOUNDS; do
    BOUND_COUNT=$((BOUND_COUNT + 1))
    [[ "$bound" -le 255 ]] || fq_fail "STATIC_REGEX_REPETITION_OVER_255_$bound"
done

[[ "$BOUND_COUNT" -gt 0 ]] || fq_fail "STATIC_REGEX_BOUNDS_NOT_FOUND"

if fq_code_matches "$CONTRACT" '=~[[:space:]]+[^$[:space:]]'; then
    fq_fail "STATIC_REGEX_NOT_IN_VARIABLE"
fi

echo "${TEST_PREFIX}_STATIC_SCAN=PASS"

# ---------------------------------------------------------------- 2. restricted tool set, strict sed, set -u, locales

RESTRICTED="$FQ_TMP/restricted-bin"
mkdir -p "$RESTRICTED"

REAL_SED="$(command -v sed)"
REAL_DIRNAME="$(command -v dirname)"
REAL_BASH="$(command -v bash)"

[[ -x "$REAL_SED" && -x "$REAL_DIRNAME" && -x "$REAL_BASH" ]] || fq_fail "TOOLS_NOT_FOUND"

cp "$ROOT/tests/fixtures/worktree_isolation/strict_sed.sh" "$RESTRICTED/sed"
chmod 755 "$RESTRICTED/sed"
ln -s "$REAL_DIRNAME" "$RESTRICTED/dirname"
ln -s "$REAL_BASH" "$RESTRICTED/bash"

export CBS_SHIM_REAL_SED="$REAL_SED"
export CBS_SHIM_TOOLLOG="$FQ_TMP/strict-sed.log"

RUN_SCRIPT="$FQ_TMP/restricted_run.sh"
cat > "$RUN_SCRIPT" <<'EOF'
set -u
contract="$1"
shift

source "$contract" || exit 90

cbs_flutter_qual_validate_request "$@" || exit 91

[ "$(cbs_flutter_qual_redact 'token=abc')" = "token=[REDACTED]" ] || exit 92

key_block="$(cbs_flutter_qual_redact_stream <<'KEY'
before
-----BEGIN PRIVATE KEY-----
body-line
-----END PRIVATE KEY-----
after
KEY
)"
case "$key_block" in
    *body-line*) exit 93 ;;
esac

cbs_flutter_qual_text_contains_secret "https://u:p@h/x" || exit 94
cbs_flutter_qual_text_contains_secret "https://example.invalid/x" && exit 95

cbs_flutter_qual_validate_param expected_origin "https://u:p@h/x"
[ "$?" -eq 125 ] || exit 96

cbs_flutter_qual_validate_param actions "preflight,rm"
[ "$?" -eq 122 ] || exit 97

cbs_flutter_qual_validate_param timeout_seconds "09"
[ "$?" -eq 121 ] || exit 98

cbs_flutter_qual_emit_result PASS > /dev/null || exit 99
[ "$(cbs_flutter_qual_aggregate PASS SKIPPED)" = "PASS" ] || exit 100
[ "$(cbs_flutter_qual_aggregate SKIPPED)" = "NOT_RUN" ] || exit 101

echo "RESTRICTED_RUN_OK"
EOF

fq_request_reset

for locale in C POSIX; do
    : > "$CBS_SHIM_TOOLLOG"

    set +e
    OUT="$(env -i PATH="$RESTRICTED" LC_ALL="$locale" HOME="$FQ_TMP" TMPDIR="$FQ_TMP" \
        CBS_SHIM_REAL_SED="$REAL_SED" CBS_SHIM_TOOLLOG="$CBS_SHIM_TOOLLOG" \
        "$RESTRICTED/bash" -u "$RUN_SCRIPT" "$CONTRACT" "${FQ_REQUEST[@]}" 2>&1)"
    RC=$?
    set -e

    [[ "$RC" -eq 0 ]] || fq_fail "RESTRICTED_RUN_${locale}_RC_${RC}_$(printf '%s' "$OUT" | head -n 1 | tr -c 'A-Za-z0-9._-' '_')"
    [[ "$OUT" == "RESTRICTED_RUN_OK" ]] || fq_fail "RESTRICTED_RUN_${locale}_OUTPUT"

    if grep -q '^REJECTED ' "$CBS_SHIM_TOOLLOG"; then
        fq_fail "STRICT_SED_REJECTED_$(grep '^REJECTED ' "$CBS_SHIM_TOOLLOG" | head -n 1 | tr -c 'A-Za-z0-9._-' '_')"
    fi

    # Not vacuous: sed was really exercised through the strict wrapper.
    grep -q '^sed ' "$CBS_SHIM_TOOLLOG" || fq_fail "STRICT_SED_NOT_EXERCISED_$locale"
done

echo "${TEST_PREFIX}_RESTRICTED_TOOLS_STRICT_SED=PASS"

# The strict wrapper means what it says: it rejects GNU-only sed usage.
for script in 's/a\+/b/' 's/a\|b/c/' 's/a/b/I' 's/\w/b/'; do
    set +e
    PATH="$RESTRICTED" "$RESTRICTED/sed" -e "$script" /dev/null >/dev/null 2>&1
    RC=$?
    set -e
    [[ "$RC" -eq 97 ]] || fq_fail "STRICT_SED_ACCEPTED_GNU_ONLY_$script"
done

set +e
PATH="$RESTRICTED" "$RESTRICTED/sed" -r -e 's/a+/b/' /dev/null >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 97 ]] || fq_fail "STRICT_SED_ACCEPTED_DASH_R"

echo "${TEST_PREFIX}_STRICT_SED_SELF_CHECK=PASS"

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

    for suite in contract security; do
        LOG="$FQ_TMP/native-bash32-$suite.log"

        set +e
        "$BASH32" "$ROOT/tests/test_flutter_qualification_$suite.sh" > "$LOG" 2>&1
        RC=$?
        set -e

        if [[ "$RC" -ne 0 ]] ||
            ! grep -Fxq "TEST_FLUTTER_QUALIFICATION_$(printf '%s' "$suite" | tr 'a-z' 'A-Z')_RESULT=PASS" "$LOG"; then
            fq_fail "NATIVE_BASH_3_2_${suite}_RC_${RC}"
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
