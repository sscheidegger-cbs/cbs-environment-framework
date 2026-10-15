#!/usr/bin/env bash

# D04b-C.2c: portability of the Flutter dependency preparation
# (cbs/qualification/flutter/dependencies.sh) - Linux, and macOS with
# /bin/bash 3.2 and BSD utilities.
#
# What this test proves, and what it does not:
#   1. a static scan forbids Bash 4+ constructs and GNU-only options in the
#      script and in its behaviour test;
#   2. the manifest reader (awk) gives the same records under every awk
#      available here (no interval expression, no gawk-only function);
#   3. when a genuine Bash 3.2 is available, the behaviour test is executed
#      with it. Otherwise this step is NOT_RUN.
#
# On Linux none of this replaces a run on a native Mac: the macOS marker stays
# NOT_RUN unless this very test runs on Darwin with a genuine Bash 3.2 and
# every step passes.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="$ROOT/cbs/qualification/flutter/dependencies.sh"
BEHAVIOUR="$ROOT/tests/test_flutter_qualification_dependencies.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_DEPENDENCIES_PORTABILITY"

fail() {
    echo "${TEST_PREFIX}_RESULT=FAIL" >&2
    echo "${TEST_PREFIX}_FAILURE=$1" >&2
    exit 1
}

# Code scan without SIGPIPE (see tests/fixtures/flutter_qualification/lib.sh).
code_matches() {
    local hits
    hits="$(grep -En -e "$2" "$1" | grep -Ev '^[0-9]+:[[:space:]]*#' || true)"
    [[ -n "$hits" ]]
}

for file in "$DEPS" "$BEHAVIOUR" "$ROOT/tests/test_flutter_qualification_dependencies_portability.sh"; do
    [[ -f "$file" ]] || fail "FILE_MISSING_$(basename "$file")"
    bash -n "$file" || fail "SYNTAX_$(basename "$file")"
done

echo "${TEST_PREFIX}_SYNTAX=PASS"

# ---------------------------------------------------------------- 1. static scan

BASH4='mapfile|readarray|declare[[:space:]]+-[a-zA-Z]*[Ag]|local[[:space:]]+-[a-zA-Z]*[nA]|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}|;;&|;&[[:space:]]*$|\|&([[:space:]]|$)|&>>|coproc|\[\[[[:space:]]+-[vR][[:space:]]|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}|\$(BASHPID|EPOCHSECONDS|EPOCHREALTIME|SRANDOM)|wait[[:space:]]+-n|shopt[[:space:]]+-s[[:space:]]+(globstar|lastpipe|nocasematch|assoc_expand_once)|read[[:space:]]+-[a-zA-Z]*[iNt]|\$\{[A-Za-z_][A-Za-z0-9_]*@[UuLlQEPAaKk]\}|=~[[:space:]]+["'"'"']|\|\|=|printf[[:space:]]+-v[[:space:]]+[A-Za-z_]+\['

GNU_ONLY='find[^|]*[[:space:]](-printf|-regextype|-xtype|-readable|-writable|-executable|-newer[a-zA-Z]+|-delete|-fprint[a-z0-9]*|-quit|-samefile)|find[^|]*-perm[[:space:]]+[/+]|sed[[:space:]]+(-[a-zA-Z]*[irzsu][a-zA-Z]*|--[a-z])|sed[^|]*\\[+?|]|grep[[:space:]]+(-[a-zA-Z]*P|--[a-z])|xargs[[:space:]]+-r|sort[[:space:]]+-[a-zA-Z]*[VR]|head[[:space:]]+-n[[:space:]]+-|cp[[:space:]]+-[a-zA-Z]*a|ls[[:space:]]+--|du[[:space:]]+-b|readlink[[:space:]]+-f|realpath|stat[[:space:]]+-[cf]|date[[:space:]]+-d|mktemp[[:space:]]+--|(^|[;&|({[:space:]])(seq|tac|shuf|md5sum|sha1sum|sha256sum|truncate|flock|timeout|gtimeout)[[:space:]]|base64[[:space:]]+-w|tr[[:space:]]+--|printf[[:space:]]+.*%\(|\$EPOCH|sed[^|]*\\n|echo[[:space:]]+-e[[:space:]]|head[[:space:]]+-c[[:space:]]+-|cut[[:space:]]+--|sleep[[:space:]]+[0-9.]*[smhd]([[:space:]]|$)'

FIND_WITHOUT_PATH='(^|[^a-zA-Z_./-])find[[:space:]]+-'

for file in "$DEPS" "$BEHAVIOUR"; do
    if code_matches "$file" "$BASH4"; then
        fail "STATIC_BASH4_$(basename "$file")"
    fi

    if code_matches "$file" "$GNU_ONLY"; then
        fail "STATIC_GNU_ONLY_$(basename "$file")"
    fi

    if code_matches "$file" "$FIND_WITHOUT_PATH"; then
        fail "STATIC_FIND_WITHOUT_PATH_$(basename "$file")"
    fi

    if code_matches "$file" '<<<'; then
        fail "STATIC_HERE_STRING_$(basename "$file")"
    fi
done

# The script reaches only these tools directly (the isolation manager, Git and
# the contract do the rest).
for tool in sed grep cut sort uniq cksum date stat readlink realpath basename ls od find; do
    if code_matches "$DEPS" "(^|[;&|({]|\\\$\\()[[:space:]]*${tool}[[:space:]]"; then
        fail "STATIC_UNEXPECTED_TOOL_$tool"
    fi
done

# Regular expressions are held in variables (a quoted right-hand side is
# literal in Bash 3.2) and stay under the 255 repetition limit of the BSD
# library. awk programs use no interval expression (old BSD awk).
if code_matches "$DEPS" '=~[[:space:]]+[^$[:space:]]'; then
    fail "STATIC_REGEX_NOT_IN_VARIABLE"
fi

BOUNDS="$(grep -Ev '^[[:space:]]*#' "$DEPS" | grep -Eo '\{[0-9]+(,[0-9]+)?\}' | tr -d '{}' | tr ',' ' ' || true)"

for bound in $BOUNDS; do
    [[ "$bound" -le 255 ]] || fail "STATIC_REGEX_REPETITION_OVER_255_$bound"
done

# No empty-array expansion under "set -u" is possible: the script never sets it
# and expands only indexed arrays with an explicit subscript.
if grep -Ev '^[[:space:]]*#' "$DEPS" | grep -E '\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}' >/dev/null; then
    fail "STATIC_ARRAY_EXPANSION"
fi

if grep -Ev '^[[:space:]]*#' "$DEPS" | grep -E '(^|[[:space:]])set[[:space:]]+-[a-zA-Z]*u' >/dev/null; then
    fail "STATIC_SET_U"
fi

echo "${TEST_PREFIX}_STATIC_SCAN=PASS"

# ---------------------------------------------------------------- 2. the manifest reader under every awk

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cbs-deps-portability.XXXXXX")"
TMP="$(cd -P "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/pubspec.yaml" <<'EOF'
name: app
dependencies:
  flutter:
    sdk: flutter
  # comment
  pkg_a:
    path: ../fw/packages/pkg_a   # trailing
  pkg_q:
    path: "../fw/packages/pkg_q"
  pkg_s:
    path: '../fw/packages/pkg_s'
  local_pkg:
    path: packages/local_pkg
  hosted_pkg: ^1.0.0
  git_pkg:
    git:
      url: https://example.invalid/x.git
      path: packages/not_local
  inline_pkg: {path: ../fw/packages/inline}
  inline_git: {git: {url: https://example.invalid/y.git, path: sub}}
dev_dependencies:
  flutter_test:
    sdk: flutter
  dev_pkg:
    path: ../other/dev
dependency_overrides:
  over_pkg:
    path: ../other/over/
flutter:
  assets:
    - path: not_a_dependency
EOF

EXPECTED="dependencies	pkg_a	../fw/packages/pkg_a
dependencies	pkg_q	../fw/packages/pkg_q
dependencies	pkg_s	../fw/packages/pkg_s
dependencies	local_pkg	packages/local_pkg
dependencies	inline_pkg	../fw/packages/inline
dev_dependencies	dev_pkg	../other/dev
dependency_overrides	over_pkg	../other/over/"

AWK_PROGRAM="$(bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "$CBS_FLUTTER_DEPS_AWK"' _ "$DEPS")"
[[ -n "$AWK_PROGRAM" ]] || fail "AWK_PROGRAM_NOT_FOUND"

AWKS=0
for candidate in awk mawk gawk nawk original-awk; do
    tool="$(command -v "$candidate" 2>/dev/null || true)"
    [[ -n "$tool" ]] || continue

    got="$(LC_ALL=C "$tool" "$AWK_PROGRAM" "$TMP/pubspec.yaml")" || fail "AWK_FAILED_$candidate"
    [[ "$got" == "$EXPECTED" ]] || fail "AWK_RECORDS_DIFFER_$candidate"
    AWKS=$((AWKS + 1))
done

[[ "$AWKS" -ge 1 ]] || fail "NO_AWK"

# gawk in POSIX mode (no GNU extension) when it is the one available.
GAWK="$(command -v gawk 2>/dev/null || true)"
if [[ -n "$GAWK" ]]; then
    got="$(LC_ALL=C "$GAWK" --posix "$AWK_PROGRAM" "$TMP/pubspec.yaml")" || fail "AWK_POSIX_FAILED"
    [[ "$got" == "$EXPECTED" ]] || fail "AWK_POSIX_RECORDS_DIFFER"
fi

# Forms that cannot be read safely are reported, never guessed.
printf 'dependencies: {a: {path: ../x}}\n' > "$TMP/flow.yaml"
got="$(LC_ALL=C awk "$AWK_PROGRAM" "$TMP/flow.yaml")"
case "$got" in
    *UNSUPPORTED*) ;;
    *) fail "AWK_FLOW_NOT_REPORTED" ;;
esac

printf 'dependencies:\n\tx:\n\t\tpath: ../x\n' > "$TMP/tab.yaml"
got="$(LC_ALL=C awk "$AWK_PROGRAM" "$TMP/tab.yaml")"
case "$got" in
    *UNSUPPORTED*) ;;
    *) fail "AWK_TAB_NOT_REPORTED" ;;
esac

echo "${TEST_PREFIX}_AWK_VARIANTS=$AWKS"
echo "${TEST_PREFIX}_AWK_READER=PASS"

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
    LOG="$TMP/native-bash32.log"

    set +e
    "$BASH32" "$BEHAVIOUR" > "$LOG" 2>&1
    RC=$?
    set -e

    if [[ "$RC" -ne 0 ]] || ! grep -Fxq "TEST_FLUTTER_QUALIFICATION_DEPENDENCIES_RESULT=PASS" "$LOG"; then
        fail "NATIVE_BASH_3_2_RC_${RC}"
    fi
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
