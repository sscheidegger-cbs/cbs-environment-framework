#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS="$ROOT/bin/cbs"

fail() {
    echo "TEST_RESULT=FAIL" >&2
    echo "TEST_FAILURE=$1" >&2
    exit 1
}

EXPECTED_VERSION="$(tr -d "\r\n" < "$ROOT/VERSION")"

HELP="$("$CBS" help)"
HELP_LONG="$("$CBS" --help)"
HELP_SHORT="$("$CBS" -h)"
HELP_DEFAULT="$("$CBS")"

[[ "$HELP" == "$HELP_LONG" ]] || fail "HELP_LONG_ALIAS_MISMATCH"
[[ "$HELP" == "$HELP_SHORT" ]] || fail "HELP_SHORT_ALIAS_MISMATCH"
[[ "$HELP" == "$HELP_DEFAULT" ]] || fail "HELP_DEFAULT_MISMATCH"

grep -Fq "CBS Environment Framework" <<<"$HELP" || fail "HELP_HEADER_MISSING"
grep -Fq "cbs help" <<<"$HELP" || fail "HELP_COMMAND_MISSING"
grep -Fq "cbs version" <<<"$HELP" || fail "VERSION_COMMAND_MISSING"

VERSION_OUTPUT="$("$CBS" version)"
VERSION_ALIAS_OUTPUT="$("$CBS" --version)"
EXPECTED_OUTPUT="CBS_FRAMEWORK_VERSION=${EXPECTED_VERSION}"

[[ "$VERSION_OUTPUT" == "$EXPECTED_OUTPUT" ]] || fail "VERSION_OUTPUT_INVALID"
[[ "$VERSION_ALIAS_OUTPUT" == "$EXPECTED_OUTPUT" ]] || fail "VERSION_ALIAS_OUTPUT_INVALID"

set +e
UNKNOWN_OUTPUT="$("$CBS" does-not-exist 2>&1)"
UNKNOWN_RC=$?
set -e

[[ "$UNKNOWN_RC" -eq 2 ]] || fail "UNKNOWN_COMMAND_RC_INVALID"
grep -Fq "CBS_ERROR=UNKNOWN_COMMAND" <<<"$UNKNOWN_OUTPUT" || fail "UNKNOWN_COMMAND_ERROR_MISSING"
grep -Fq "CBS_COMMAND=does-not-exist" <<<"$UNKNOWN_OUTPUT" || fail "UNKNOWN_COMMAND_VALUE_MISSING"

for forbidden in setup start stop deploy release rollback; do
    if grep -Eq "(^|[[:space:]])${forbidden}([[:space:]]|$)" <<<"$HELP"; then
        fail "UNIMPLEMENTED_COMMAND_ADVERTISED_${forbidden}"
    fi
done

echo "TEST_ENTRYPOINT_HELP=PASS"
echo "TEST_ENTRYPOINT_VERSION=PASS"
echo "TEST_ENTRYPOINT_UNKNOWN_COMMAND=PASS"
echo "TEST_ENTRYPOINT_RESULT=PASS"
