#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$ROOT_DIR"

HISTORICAL_REAL_STATE_TESTS=(
    "tests/test_instance_cli.sh"
    "tests/test_instance_manager.sh"
    "tests/test_instance_mutation_gate.sh"
    "tests/test_isolation_checker.sh"
    "tests/test_worktree_observer.sh"
)

is_historical_real_state_test() {
    local candidate="$1"
    local historical_test

    for historical_test in "${HISTORICAL_REAL_STATE_TESTS[@]}"; do
        if [[ "$candidate" == "$historical_test" ]]; then
            return 0
        fi
    done

    return 1
}

PASS=0
FAIL=0
SKIP=0

echo "CBS_PORTABLE_NON_REGRESSION_VERSION=1"

for test_file in tests/test_*.sh; do
    if is_historical_real_state_test "$test_file"; then
        echo "CBS_PORTABLE_TEST_SKIPPED=$test_file"
        SKIP=$((SKIP + 1))
        continue
    fi

    echo "CBS_PORTABLE_TEST_RUNNING=$test_file"

    if bash "$test_file"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "CBS_PORTABLE_TEST_FAILED=$test_file"
    fi
done

echo "CBS_PORTABLE_TEST_PASS_COUNT=$PASS"
echo "CBS_PORTABLE_TEST_FAIL_COUNT=$FAIL"
echo "CBS_HISTORICAL_REAL_STATE_TEST_COUNT=$SKIP"

if [[ "$FAIL" -eq 0 ]]; then
    echo "CBS_PORTABLE_NON_REGRESSION_RESULT=PASS"
    exit 0
fi

echo "CBS_PORTABLE_NON_REGRESSION_RESULT=FAIL"
exit 1
