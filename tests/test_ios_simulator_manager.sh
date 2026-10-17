#!/usr/bin/env bash

# Portable test suite for cbs/runtime/ios_simulator_manager.sh (D05).
#
# Runs on any host (Linux included): "xcrun", "open" and "uname" are mocks
# placed on an isolated PATH, so no real iOS, Xcode or DeviceHub command can
# ever be reached. Nothing is created or deleted outside a temporary directory.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/cbs/runtime/ios_simulator_manager.sh"
CBS="$ROOT/bin/cbs"

fail() {
    echo "TEST_IOS_SIMULATOR_MANAGER_RESULT=FAIL" >&2
    echo "TEST_IOS_SIMULATOR_MANAGER_FAILURE=$1" >&2
    exit 1
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cbs-ios-sim-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

SHIMS="$TMP/shims"
SHIMS_NO_OPEN="$TMP/shims-no-open"
SHIMS_NO_XCRUN="$TMP/shims-no-xcrun"
TOOLS="$TMP/tools"
mkdir -p "$SHIMS" "$SHIMS_NO_OPEN" "$SHIMS_NO_XCRUN" "$TOOLS"

# Real PATH, restored only inside the mocks (they need sed, grep, mv, ...).
MOCK_REAL_PATH="$PATH"
export MOCK_REAL_PATH

# Only the system tools the code under test legitimately needs. "bash" is the
# interpreter used by the "#!/usr/bin/env bash" shebang of the CBS scripts.
for tool in tr dirname cat bash; do
    real="$(command -v "$tool" 2>/dev/null || true)"
    case "$real" in
        /*) ln -s "$real" "$TOOLS/$tool" ;;
        *) fail "SYSTEM_TOOL_MISSING_$tool" ;;
    esac
done

U_SHUT="11111111-1111-1111-1111-111111111111"
U_BOOT="22222222-2222-2222-2222-222222222222"
U_BOOTING="33333333-3333-3333-3333-333333333333"
U_SHUTTING="44444444-4444-4444-4444-444444444444"
U_UNAV="55555555-5555-5555-5555-555555555555"
U_MISSING="AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"

# --- mocks ------------------------------------------------------------------

cat > "$SHIMS/uname" <<'SCRIPT'
#!/bin/bash
PATH="$MOCK_REAL_PATH"
echo "uname $*" >> "$MOCK_DIR/calls.log"
[[ "${1:-}" == "-s" ]] || { echo "uname $*" >> "$MOCK_DIR/bad.log"; exit 99; }
echo "${MOCK_UNAME:-Darwin}"
SCRIPT

cat > "$SHIMS/xcrun" <<'SCRIPT'
#!/bin/bash
PATH="$MOCK_REAL_PATH"
echo "xcrun $*" >> "$MOCK_DIR/calls.log"

bad() {
    echo "xcrun $*" >> "$MOCK_DIR/bad.log"
    exit 99
}

[[ "${1:-}" == "simctl" ]] || bad "$@"
shift
cmd="${1:-}"
devices="$MOCK_DIR/devices.txt"

# Rewrites the state of one device in the mocked simctl database.
set_state() {
    local udid="$1" from="$2" to="$3" tmp="$MOCK_DIR/devices.tmp"
    sed -e "s/[(]${udid}[)] [(]${from}[)]/(${udid}) (${to})/" "$devices" > "$tmp"
    mv "$tmp" "$devices"
}

has_state() {
    grep -Fq "($1) ($2)" "$devices"
}

case "$cmd" in
    list)
        [[ $# -eq 2 && "${2:-}" == "devices" ]] || bad "simctl $*"
        if [[ "${MOCK_LIST_FAIL:-0}" == "1" ]]; then
            echo "simctl: simulated list failure" >&2
            exit 2
        fi
        # MOCK_LIST_FAIL_AFTER=N: the first N list calls succeed, the next fail.
        if [[ -n "${MOCK_LIST_FAIL_AFTER:-}" ]]; then
            list_n=0
            [[ ! -f "$MOCK_DIR/list.count" ]] || list_n="$(cat "$MOCK_DIR/list.count")"
            if [[ "$list_n" -ge "$MOCK_LIST_FAIL_AFTER" ]]; then
                echo "simctl: simulated list failure" >&2
                exit 2
            fi
            echo $((list_n + 1)) > "$MOCK_DIR/list.count"
        fi
        # Deferred transition: the transient state stays visible for N
        # "simctl list" calls, then the final state is applied.
        pending="$MOCK_DIR/pending"
        if [[ -f "$pending" ]]; then
            IFS='|' read -r p_udid p_transient p_final p_left < "$pending"
            if [[ "$p_left" -le 0 ]]; then
                set_state "$p_udid" "$p_transient" "$p_final"
                rm -f "$pending"
            else
                echo "$p_udid|$p_transient|$p_final|$((p_left - 1))" > "$pending"
            fi
        fi
        cat "$devices"
        ;;
    boot)
        [[ $# -eq 2 ]] || bad "simctl $*"
        if [[ "${MOCK_BOOT_FAIL:-0}" == "1" ]]; then
            echo "simctl: simulated boot failure" >&2
            exit 3
        fi
        # Real simctl refuses to boot a device that is not shut down.
        has_state "$2" "Shutdown" || { echo "simctl boot on non-shutdown" >> "$MOCK_DIR/bad.log"; exit 149; }
        if [[ "${MOCK_BOOT_NOEFFECT:-0}" == "1" ]]; then
            :
        elif [[ -n "${MOCK_BOOT_DEFER:-}" ]]; then
            set_state "$2" "Shutdown" "Booting"
            echo "$2|Booting|Booted|$MOCK_BOOT_DEFER" > "$MOCK_DIR/pending"
        else
            set_state "$2" "Shutdown" "Booted"
        fi
        ;;
    bootstatus)
        [[ $# -eq 3 && "${3:-}" == "-b" ]] || bad "simctl $*"
        if [[ "${MOCK_BOOTSTATUS_FAIL:-0}" == "1" ]]; then
            echo "simctl: simulated bootstatus failure" >&2
            exit 3
        fi
        # MOCK_BOOT_NOEFFECT: bootstatus succeeds although "simctl list" never
        # reports the device as Booted (boot not confirmed scenario).
        [[ "${MOCK_BOOT_NOEFFECT:-0}" != "1" ]] || exit 0
        # Real bootstatus is only meaningful for a booting or booted device.
        has_state "$2" "Booting" || has_state "$2" "Booted" ||
            { echo "simctl bootstatus on shutdown device" >> "$MOCK_DIR/bad.log"; exit 149; }
        ;;
    shutdown)
        [[ $# -eq 2 ]] || bad "simctl $*"
        if [[ "${MOCK_SHUTDOWN_FAIL:-0}" == "1" ]]; then
            echo "simctl: simulated shutdown failure" >&2
            exit 3
        fi
        has_state "$2" "Booted" || { echo "simctl shutdown on non-booted" >> "$MOCK_DIR/bad.log"; exit 149; }
        if [[ "${MOCK_SHUTDOWN_NOEFFECT:-0}" == "1" ]]; then
            :
        elif [[ -n "${MOCK_SHUTDOWN_DEFER:-}" ]]; then
            set_state "$2" "Booted" "Shutting Down"
            echo "$2|Shutting Down|Shutdown|$MOCK_SHUTDOWN_DEFER" > "$MOCK_DIR/pending"
        else
            set_state "$2" "Booted" "Shutdown"
        fi
        ;;
    *)
        # create, delete, erase, clone, ... must never be reached.
        bad "simctl $*"
        ;;
esac
SCRIPT

cat > "$SHIMS/open" <<'SCRIPT'
#!/bin/bash
PATH="$MOCK_REAL_PATH"
echo "open $*" >> "$MOCK_DIR/calls.log"
[[ $# -eq 2 && "${1:-}" == "-a" && "${2:-}" == "DeviceHub" ]] || {
    echo "open $*" >> "$MOCK_DIR/bad.log"
    exit 99
}
if [[ "${MOCK_OPEN_FAIL:-0}" == "1" ]]; then
    echo "Unable to find application named 'DeviceHub'" >&2
    exit 1
fi
SCRIPT

# "sleep" never really sleeps: it only records the call, so the bounded waits
# of the manager are exercised instantly and counted exactly.
cat > "$SHIMS/sleep" <<'SCRIPT'
#!/bin/bash
PATH="$MOCK_REAL_PATH"
echo "sleep $*" >> "$MOCK_DIR/calls.log"
[[ $# -eq 1 && "${1:-}" =~ ^[0-9]+$ ]] || {
    echo "sleep $*" >> "$MOCK_DIR/bad.log"
    exit 99
}
SCRIPT

chmod 755 "$SHIMS/uname" "$SHIMS/xcrun" "$SHIMS/open" "$SHIMS/sleep"

ln -s "$SHIMS/uname" "$SHIMS_NO_OPEN/uname"
ln -s "$SHIMS/xcrun" "$SHIMS_NO_OPEN/xcrun"
ln -s "$SHIMS/sleep" "$SHIMS_NO_OPEN/sleep"
ln -s "$SHIMS/uname" "$SHIMS_NO_XCRUN/uname"
ln -s "$SHIMS/open" "$SHIMS_NO_XCRUN/open"
ln -s "$SHIMS/sleep" "$SHIMS_NO_XCRUN/sleep"

# --- harness ----------------------------------------------------------------

CASE_N=0
OUT=""
ERR=""
RC=0

new_case() {
    CASE_N=$((CASE_N + 1))
    MOCK_DIR="$TMP/case$CASE_N"
    mkdir -p "$MOCK_DIR"
    export MOCK_DIR
    unset MOCK_UNAME MOCK_LIST_FAIL MOCK_BOOT_FAIL MOCK_BOOT_NOEFFECT \
        MOCK_BOOT_DEFER MOCK_BOOTSTATUS_FAIL MOCK_LIST_FAIL_AFTER \
        MOCK_SHUTDOWN_FAIL MOCK_SHUTDOWN_NOEFFECT MOCK_SHUTDOWN_DEFER \
        MOCK_OPEN_FAIL || true
    : > "$MOCK_DIR/calls.log"
    : > "$MOCK_DIR/bad.log"

    cat > "$MOCK_DIR/devices.txt" <<EOF
== Devices ==
-- iOS 17.5 --
    iPhone 15 ($U_SHUT) (Shutdown)
    iPhone 15 Pro (Max) ($U_BOOT) (Booted)
    iPhone 15 Plus ($U_BOOTING) (Booting)
    iPhone SE ($U_SHUTTING) (Shutting Down)
-- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-16-4 --
    iPhone 14 ($U_UNAV) (Shutdown) (unavailable, runtime profile not found)
EOF
    cp "$MOCK_DIR/devices.txt" "$MOCK_DIR/devices.initial"
}

# run_with_path <PATH> <command...>: captures OUT, ERR and RC.
run_with_path() {
    local test_path="$1"
    shift
    set +e
    OUT="$(env PATH="$test_path" "$@" 2>"$MOCK_DIR/stderr")"
    RC=$?
    set -e
    ERR="$(cat "$MOCK_DIR/stderr")"
}

mgr() {
    run_with_path "$SHIMS:$TOOLS" "$BASH" "$MANAGER" "$@"
}

cbs_run() {
    run_with_path "$SHIMS:$TOOLS" "$BASH" "$CBS" "$@"
}

count_calls() {
    local pattern="$1" n
    n="$(grep -c -- "$pattern" "$MOCK_DIR/calls.log" || true)"
    echo "$n"
}

assert_rc() {
    [[ "$RC" -eq "$1" ]] || fail "$2 (rc=$RC expected=$1 err=$ERR)"
}

assert_out() {
    grep -Fq -- "$1" <<<"$OUT" || fail "$2 (stdout missing: $1)"
}

assert_no_out() {
    if grep -Fq -- "$1" <<<"$OUT"; then
        fail "$2 (stdout unexpectedly has: $1)"
    fi
}

assert_err() {
    grep -Fq -- "$1" <<<"$ERR" || fail "$2 (stderr missing: $1)"
}

assert_calls() {
    [[ "$(count_calls "$1")" -eq "$2" ]] ||
        fail "$3 (calls matching '$1': $(count_calls "$1"), expected $2)"
}

assert_no_unexpected() {
    [[ ! -s "$MOCK_DIR/bad.log" ]] ||
        fail "$1 (unexpected mock call: $(cat "$MOCK_DIR/bad.log"))"
}

assert_db_unchanged() {
    cmp -s "$MOCK_DIR/devices.txt" "$MOCK_DIR/devices.initial" ||
        fail "$1 (simulator database mutated)"
}

assert_no_mutation() {
    assert_calls "simctl boot" 0 "$1"
    assert_calls "simctl bootstatus" 0 "$1"
    assert_calls "simctl shutdown" 0 "$1"
    assert_calls "^sleep" 0 "$1"
    assert_calls "^open " 0 "$1"
    assert_db_unchanged "$1"
    assert_no_unexpected "$1"
}

assert_no_host_call() {
    # Nothing but the host check: no xcrun, no open.
    assert_calls "^xcrun" 0 "$1"
    assert_calls "^open" 0 "$1"
    assert_no_unexpected "$1"
}

# --- static contract of the source ------------------------------------------

bash -n "$MANAGER" || fail "MANAGER_SYNTAX"
bash -n "$CBS" || fail "ENTRYPOINT_SYNTAX"
[[ -x "$MANAGER" ]] || fail "MANAGER_NOT_EXECUTABLE"

# Comment lines are ignored: only executable code is checked.
MANAGER_CODE="$(grep -v '^[[:space:]]*#' "$MANAGER")"

if grep -Eq 'simctl[[:space:]]+(create|delete|erase|clone|rename|upgrade)' <<<"$MANAGER_CODE"; then
    fail "MANAGER_MUTATES_SIMULATOR_INVENTORY"
fi
if grep -Eq '(^|[^[:alnum:]_])(ssh|scp)([^[:alnum:]_]|$)' <<<"$MANAGER_CODE"; then
    fail "MANAGER_USES_SSH"
fi
if grep -Eq 'declare[[:space:]]+-A|mapfile|readarray|\$\{[A-Za-z_]+(\^\^|,,)\}|\|&' <<<"$MANAGER_CODE"; then
    fail "MANAGER_NOT_BASH_3_2_COMPATIBLE"
fi
# Waits must stay bounded: no "while true", "while :" or "until" loop, and the
# bound used by the transition tests below must be the one the manager defines.
if grep -Eq '(^|[[:space:]])(while[[:space:]]+(true|:)([[:space:]]|;|$)|until[[:space:]])' <<<"$MANAGER_CODE"; then
    fail "MANAGER_HAS_UNBOUNDED_LOOP"
fi
POLL_MAX=30
grep -Fxq "POLL_MAX_ATTEMPTS=$POLL_MAX" <<<"$MANAGER_CODE" || fail "MANAGER_POLL_BOUND_MISMATCH"
grep -Eq 'simctl[[:space:]]+bootstatus[[:space:]]+"\$UDID"[[:space:]]+-b' <<<"$MANAGER_CODE" ||
    fail "MANAGER_NO_BOOTSTATUS"
echo "TEST_IOS_SIMULATOR_MANAGER_STATIC=PASS"

# --- platform not macOS -----------------------------------------------------

for action in list "ensure $U_SHUT" "start $U_SHUT" "status $U_SHUT" "stop $U_SHUT"; do
    new_case
    export MOCK_UNAME="Linux"
    # shellcheck disable=SC2086
    mgr $action
    assert_rc 82 "NOT_MACOS_RC_$action"
    assert_err "CBS_IOS_RUNTIME_ERROR=HOST_NOT_MACOS" "NOT_MACOS_ERROR_$action"
    assert_no_host_call "NOT_MACOS_NO_IOS_COMMAND_$action"
    assert_db_unchanged "NOT_MACOS_DB_$action"
done
echo "TEST_IOS_SIMULATOR_MANAGER_NOT_MACOS=PASS"

# --- xcrun / open missing ---------------------------------------------------

new_case
run_with_path "$SHIMS_NO_XCRUN:$TOOLS" "$BASH" "$MANAGER" list
assert_rc 82 "XCRUN_MISSING_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=XCRUN_MISSING" "XCRUN_MISSING_ERROR"
assert_calls "^open" 0 "XCRUN_MISSING_NO_OPEN"

new_case
run_with_path "$SHIMS_NO_OPEN:$TOOLS" "$BASH" "$MANAGER" start "$U_SHUT"
assert_rc 82 "OPEN_MISSING_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=OPEN_MISSING" "OPEN_MISSING_ERROR"
assert_calls "simctl boot" 0 "OPEN_MISSING_NO_BOOT_BEFORE_FAILURE"
assert_db_unchanged "OPEN_MISSING_DB"
echo "TEST_IOS_SIMULATOR_MANAGER_TOOLS_MISSING=PASS"

# --- unknown commands and invalid arguments ---------------------------------

for bad_action in "" create delete erase boot shutdown restart LIST; do
    new_case
    mgr "$bad_action"
    assert_rc 64 "UNKNOWN_ACTION_RC_'$bad_action'"
    assert_err "CBS_IOS_RUNTIME_ERROR=USAGE" "UNKNOWN_ACTION_ERROR_'$bad_action'"
    assert_err "Usage: ios_simulator_manager.sh" "UNKNOWN_ACTION_USAGE_'$bad_action'"
    assert_calls "^xcrun" 0 "UNKNOWN_ACTION_NO_XCRUN_'$bad_action'"
done

new_case
mgr
assert_rc 64 "NO_ACTION_RC"

new_case
mgr list "$U_SHUT"
assert_rc 64 "LIST_EXTRA_ARGUMENT_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=USAGE" "LIST_EXTRA_ARGUMENT_ERROR"
assert_calls "^xcrun" 0 "LIST_EXTRA_ARGUMENT_NO_XCRUN"

for action in ensure start status stop; do
    new_case
    mgr "$action"
    assert_rc 64 "UDID_REQUIRED_RC_$action"
    assert_err "CBS_IOS_RUNTIME_ERROR=UDID_REQUIRED" "UDID_REQUIRED_ERROR_$action"
    assert_calls "^xcrun" 0 "UDID_REQUIRED_NO_XCRUN_$action"

    new_case
    mgr "$action" "$U_SHUT" extra
    assert_rc 64 "EXTRA_ARGUMENT_RC_$action"
    assert_err "CBS_IOS_RUNTIME_ERROR=USAGE" "EXTRA_ARGUMENT_ERROR_$action"
    assert_calls "^xcrun" 0 "EXTRA_ARGUMENT_NO_XCRUN_$action"

    for bad_udid in "" "iPhone 15" "not-a-udid" "medium_phone" \
        "1111111-1111-1111-1111-111111111111" \
        "11111111-1111-1111-1111-1111111111111" \
        "11111111111111111111111111111111" \
        "GGGGGGGG-1111-1111-1111-111111111111" \
        "11111111-1111-1111-1111-111111111111;ls" \
        "-1111111-1111-1111-1111-111111111111"; do
        new_case
        mgr "$action" "$bad_udid"
        assert_rc 64 "UDID_INVALID_RC_${action}_'$bad_udid'"
        assert_err "CBS_IOS_RUNTIME_ERROR=UDID_INVALID" "UDID_INVALID_ERROR_${action}_'$bad_udid'"
        assert_calls "^xcrun" 0 "UDID_INVALID_NO_XCRUN_${action}_'$bad_udid'"
        assert_calls "^open" 0 "UDID_INVALID_NO_OPEN_${action}_'$bad_udid'"
        assert_db_unchanged "UDID_INVALID_DB_${action}_'$bad_udid'"
    done
done
echo "TEST_IOS_SIMULATOR_MANAGER_UNKNOWN_COMMAND=PASS"
echo "TEST_IOS_SIMULATOR_MANAGER_UDID_VALIDATION=PASS"

# --- list -------------------------------------------------------------------

new_case
mgr list
assert_rc 0 "LIST_RC"
assert_out "iPhone 15 ($U_SHUT) (Shutdown)" "LIST_SHUTDOWN_DEVICE"
assert_out "iPhone 15 Pro (Max) ($U_BOOT) (Booted)" "LIST_BOOTED_DEVICE"
assert_out "CBS_IOS_RUNTIME_LIST_RESULT=PASS" "LIST_RESULT"
assert_calls "simctl list devices" 1 "LIST_SINGLE_SIMCTL_CALL"
assert_no_mutation "LIST_NO_MUTATION"

new_case
export MOCK_LIST_FAIL=1
mgr list
assert_rc 82 "LIST_SIMCTL_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_LIST_FAILED" "LIST_SIMCTL_ERROR"
assert_no_out "CBS_IOS_RUNTIME_LIST_RESULT=PASS" "LIST_SIMCTL_ERROR_NO_PASS"
assert_no_mutation "LIST_SIMCTL_ERROR_NO_MUTATION"
echo "TEST_IOS_SIMULATOR_MANAGER_LIST=PASS"

# --- ensure (no mutation) ---------------------------------------------------

new_case
mgr ensure "$U_SHUT"
assert_rc 0 "ENSURE_SHUTDOWN_RC"
assert_out "CBS_IOS_RUNTIME_DEVICE=$U_SHUT" "ENSURE_DEVICE"
assert_out "CBS_IOS_RUNTIME_STATE=SHUTDOWN" "ENSURE_STATE"
assert_out "CBS_IOS_RUNTIME_ACTION=REUSE" "ENSURE_ACTION"
assert_out "CBS_IOS_RUNTIME_ENSURE_RESULT=PASS" "ENSURE_RESULT"
assert_no_mutation "ENSURE_SHUTDOWN_NO_MUTATION"

new_case
mgr ensure "$U_BOOT"
assert_rc 0 "ENSURE_BOOTED_RC"
assert_out "CBS_IOS_RUNTIME_STATE=BOOTED" "ENSURE_BOOTED_STATE"
assert_no_mutation "ENSURE_BOOTED_NO_MUTATION"

new_case
mgr ensure "11111111-1111-1111-1111-111111111111"
lower="$(printf '%s' "$U_SHUT" | tr '[:upper:]' '[:lower:]')"
mgr ensure "$lower"
assert_rc 0 "ENSURE_LOWERCASE_RC"
assert_out "CBS_IOS_RUNTIME_DEVICE=$U_SHUT" "ENSURE_LOWERCASE_NORMALIZED"

new_case
mgr ensure "$U_MISSING"
assert_rc 82 "ENSURE_MISSING_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_MISSING" "ENSURE_MISSING_ERROR"
assert_no_out "CBS_IOS_RUNTIME_ENSURE_RESULT=PASS" "ENSURE_MISSING_NO_PASS"
assert_no_mutation "ENSURE_MISSING_NO_CREATION"

new_case
mgr ensure "$U_UNAV"
assert_rc 82 "ENSURE_UNAVAILABLE_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_UNAVAILABLE" "ENSURE_UNAVAILABLE_ERROR"
assert_no_mutation "ENSURE_UNAVAILABLE_NO_MUTATION"

new_case
export MOCK_LIST_FAIL=1
mgr ensure "$U_SHUT"
assert_rc 82 "ENSURE_SIMCTL_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_LIST_FAILED" "ENSURE_SIMCTL_ERROR"
assert_no_mutation "ENSURE_SIMCTL_ERROR_NO_MUTATION"
echo "TEST_IOS_SIMULATOR_MANAGER_ENSURE=PASS"

# --- status (no mutation) ---------------------------------------------------

new_case
mgr status "$U_SHUT"
assert_rc 0 "STATUS_SHUTDOWN_RC"
assert_out "CBS_IOS_RUNTIME_DEVICE=$U_SHUT" "STATUS_DEVICE"
assert_out "CBS_IOS_RUNTIME_STATE=SHUTDOWN" "STATUS_SHUTDOWN_STATE"
assert_out "CBS_IOS_RUNTIME_STATUS_RESULT=PASS" "STATUS_RESULT"
assert_no_mutation "STATUS_SHUTDOWN_NO_MUTATION"

new_case
mgr status "$U_BOOT"
assert_rc 0 "STATUS_BOOTED_RC"
assert_out "CBS_IOS_RUNTIME_STATE=BOOTED" "STATUS_BOOTED_STATE"
assert_no_mutation "STATUS_BOOTED_NO_MUTATION"

new_case
mgr status "$U_BOOTING"
assert_rc 0 "STATUS_BOOTING_RC"
assert_out "CBS_IOS_RUNTIME_STATE=BOOTING" "STATUS_BOOTING_STATE"
assert_no_mutation "STATUS_BOOTING_NO_MUTATION"

new_case
mgr status "$U_SHUTTING"
assert_rc 0 "STATUS_SHUTTING_DOWN_RC"
assert_out "CBS_IOS_RUNTIME_STATE=SHUTTING_DOWN" "STATUS_SHUTTING_DOWN_STATE"
assert_no_mutation "STATUS_SHUTTING_DOWN_NO_MUTATION"

new_case
mgr status "$U_UNAV"
assert_rc 0 "STATUS_UNAVAILABLE_RC"
assert_out "CBS_IOS_RUNTIME_STATE=UNAVAILABLE" "STATUS_UNAVAILABLE_STATE"
assert_no_mutation "STATUS_UNAVAILABLE_NO_MUTATION"

new_case
mgr status "$U_MISSING"
assert_rc 82 "STATUS_MISSING_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_MISSING" "STATUS_MISSING_ERROR"
assert_no_out "CBS_IOS_RUNTIME_STATUS_RESULT=PASS" "STATUS_MISSING_NO_PASS"
assert_no_mutation "STATUS_MISSING_NO_MUTATION"

new_case
export MOCK_LIST_FAIL=1
mgr status "$U_SHUT"
assert_rc 82 "STATUS_SIMCTL_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_LIST_FAILED" "STATUS_SIMCTL_ERROR"
assert_no_mutation "STATUS_SIMCTL_ERROR_NO_MUTATION"
echo "TEST_IOS_SIMULATOR_MANAGER_STATUS=PASS"

# --- start ------------------------------------------------------------------

# Stopped simulator: boot, then DeviceHub.
new_case
mgr start "$U_SHUT"
assert_rc 0 "START_SHUTDOWN_RC"
assert_out "CBS_IOS_RUNTIME_DEVICE=$U_SHUT" "START_DEVICE"
assert_out "CBS_IOS_RUNTIME_STATE=BOOTED" "START_STATE"
assert_out "CBS_IOS_RUNTIME_ACTION=BOOT" "START_ACTION"
assert_out "CBS_IOS_RUNTIME_DEVICEHUB=OPENED" "START_DEVICEHUB"
assert_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_RESULT"
assert_calls "simctl boot $U_SHUT" 1 "START_SHUTDOWN_BOOT_ONCE"
assert_calls "^open -a DeviceHub$" 1 "START_SHUTDOWN_DEVICEHUB_ONCE"
grep -Fq "($U_SHUT) (Booted)" "$MOCK_DIR/devices.txt" || fail "START_SHUTDOWN_DB_BOOTED"
assert_no_unexpected "START_SHUTDOWN_NO_UNEXPECTED"

# boot happens before DeviceHub.
boot_line="$(grep -n "^xcrun simctl boot [^ ]*$" "$MOCK_DIR/calls.log" | head -n 1 | cut -d: -f1)"
bootstatus_line="$(grep -n "^xcrun simctl bootstatus [^ ]* -b$" "$MOCK_DIR/calls.log" | head -n 1 | cut -d: -f1)"
open_line="$(grep -n "^open" "$MOCK_DIR/calls.log" | head -n 1 | cut -d: -f1)"
[[ -n "$boot_line" && -n "$open_line" && "$boot_line" -lt "$open_line" ]] ||
    fail "START_ORDER_BOOT_THEN_DEVICEHUB"
[[ -n "$bootstatus_line" && "$boot_line" -lt "$bootstatus_line" && "$bootstatus_line" -lt "$open_line" ]] ||
    fail "START_ORDER_BOOT_BOOTSTATUS_DEVICEHUB"
assert_calls "^xcrun simctl bootstatus $U_SHUT -b$" 1 "START_SHUTDOWN_BOOTSTATUS_ONCE"
assert_calls "^sleep" 0 "START_SHUTDOWN_IMMEDIATE_NO_WAIT"

# Already started simulator: no boot, DeviceHub still opened.
new_case
mgr start "$U_BOOT"
assert_rc 0 "START_BOOTED_RC"
assert_out "CBS_IOS_RUNTIME_ACTION=NOOP" "START_BOOTED_ACTION"
assert_out "CBS_IOS_RUNTIME_DEVICEHUB=OPENED" "START_BOOTED_DEVICEHUB"
assert_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_BOOTED_RESULT"
assert_calls "simctl boot" 0 "START_BOOTED_NO_BOOT"
assert_calls "^open -a DeviceHub$" 1 "START_BOOTED_DEVICEHUB_ONCE"
assert_no_unexpected "START_BOOTED_NO_UNEXPECTED"

# Idempotence: start twice.
new_case
mgr start "$U_SHUT"
assert_rc 0 "START_IDEMPOTENT_FIRST_RC"
mgr start "$U_SHUT"
assert_rc 0 "START_IDEMPOTENT_SECOND_RC"
assert_out "CBS_IOS_RUNTIME_ACTION=NOOP" "START_IDEMPOTENT_SECOND_ACTION"
assert_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_IDEMPOTENT_SECOND_RESULT"
assert_calls "^xcrun simctl boot [^ ]*$" 1 "START_IDEMPOTENT_BOOT_ONCE"
assert_no_unexpected "START_IDEMPOTENT_NO_UNEXPECTED"

# Missing / unavailable / transitioning simulators.
new_case
mgr start "$U_MISSING"
assert_rc 82 "START_MISSING_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_MISSING" "START_MISSING_ERROR"
assert_no_mutation "START_MISSING_NO_MUTATION"

new_case
mgr start "$U_UNAV"
assert_rc 82 "START_UNAVAILABLE_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_UNAVAILABLE" "START_UNAVAILABLE_ERROR"
assert_no_mutation "START_UNAVAILABLE_NO_MUTATION"

for transitional in "$U_BOOTING" "$U_SHUTTING"; do
    new_case
    mgr start "$transitional"
    assert_rc 82 "START_TRANSITIONING_RC_$transitional"
    assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_STATE_TRANSITIONING" "START_TRANSITIONING_ERROR_$transitional"
    assert_no_mutation "START_TRANSITIONING_NO_MUTATION_$transitional"
done

# simctl errors.
new_case
export MOCK_LIST_FAIL=1
mgr start "$U_SHUT"
assert_rc 82 "START_LIST_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_LIST_FAILED" "START_LIST_ERROR"
assert_no_mutation "START_LIST_ERROR_NO_MUTATION"

new_case
export MOCK_BOOT_FAIL=1
mgr start "$U_SHUT"
assert_rc 82 "START_BOOT_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_BOOT_FAILED" "START_BOOT_ERROR"
assert_err "simulated boot failure" "START_BOOT_ERROR_SIMCTL_MESSAGE_PRESERVED"
assert_no_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_BOOT_ERROR_NO_PASS"
assert_calls "^open" 0 "START_BOOT_ERROR_NO_DEVICEHUB"
assert_db_unchanged "START_BOOT_ERROR_DB"

new_case
export MOCK_BOOT_NOEFFECT=1
mgr start "$U_SHUT"
assert_rc 82 "START_BOOT_NOT_CONFIRMED_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=BOOT_NOT_CONFIRMED" "START_BOOT_NOT_CONFIRMED_ERROR"
assert_no_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_BOOT_NOT_CONFIRMED_NO_PASS"
assert_calls "^open" 0 "START_BOOT_NOT_CONFIRMED_NO_DEVICEHUB"
assert_calls "^sleep 1$" "$POLL_MAX" "START_BOOT_NOT_CONFIRMED_WAIT_BOUNDED"

# bootstatus failure: structured error, simctl message preserved, no wait, no
# DeviceHub, no PASS.
new_case
export MOCK_BOOTSTATUS_FAIL=1
mgr start "$U_SHUT"
assert_rc 82 "START_BOOTSTATUS_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_BOOTSTATUS_FAILED" "START_BOOTSTATUS_ERROR"
assert_err "simulated bootstatus failure" "START_BOOTSTATUS_ERROR_SIMCTL_MESSAGE_PRESERVED"
assert_no_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_BOOTSTATUS_ERROR_NO_PASS"
assert_calls "^xcrun simctl boot [^ ]*$" 1 "START_BOOTSTATUS_ERROR_BOOT_ONCE"
assert_calls "^xcrun simctl bootstatus $U_SHUT -b$" 1 "START_BOOTSTATUS_ERROR_BOOTSTATUS_ONCE"
assert_calls "^sleep" 0 "START_BOOTSTATUS_ERROR_NO_WAIT"
assert_calls "^open" 0 "START_BOOTSTATUS_ERROR_NO_DEVICEHUB"
assert_no_unexpected "START_BOOTSTATUS_ERROR_NO_UNEXPECTED"

# bootstatus must not run when boot itself failed.
new_case
export MOCK_BOOT_FAIL=1
mgr start "$U_SHUT"
assert_rc 82 "START_BOOT_ERROR_NO_BOOTSTATUS_RC"
assert_calls "simctl bootstatus" 0 "START_BOOT_ERROR_NO_BOOTSTATUS"

# Deferred boot: simctl list still reports Booting after bootstatus returned.
# The transition is waited for (bounded) instead of failing immediately.
new_case
export MOCK_BOOT_DEFER=3
mgr start "$U_SHUT"
assert_rc 0 "START_DEFERRED_RC"
assert_out "CBS_IOS_RUNTIME_STATE=BOOTED" "START_DEFERRED_STATE"
assert_out "CBS_IOS_RUNTIME_ACTION=BOOT" "START_DEFERRED_ACTION"
assert_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_DEFERRED_RESULT"
assert_calls "^xcrun simctl boot [^ ]*$" 1 "START_DEFERRED_BOOT_ONCE"
assert_calls "^xcrun simctl bootstatus $U_SHUT -b$" 1 "START_DEFERRED_BOOTSTATUS_ONCE"
assert_calls "^sleep 1$" 3 "START_DEFERRED_WAITED_THREE_TIMES"
assert_calls "^open -a DeviceHub$" 1 "START_DEFERRED_DEVICEHUB_ONCE"
grep -Fq "($U_SHUT) (Booted)" "$MOCK_DIR/devices.txt" || fail "START_DEFERRED_DB_BOOTED"
assert_no_unexpected "START_DEFERRED_NO_UNEXPECTED"

# Deferred boot completing exactly on the last allowed observation.
new_case
export MOCK_BOOT_DEFER="$POLL_MAX"
mgr start "$U_SHUT"
assert_rc 0 "START_DEFERRED_AT_BOUND_RC"
assert_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_DEFERRED_AT_BOUND_RESULT"
assert_calls "^sleep 1$" "$POLL_MAX" "START_DEFERRED_AT_BOUND_WAITS"

# Deferred boot that never completes: bounded, structured error, no DeviceHub.
new_case
export MOCK_BOOT_DEFER=1000
mgr start "$U_SHUT"
assert_rc 82 "START_DEFERRED_TIMEOUT_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=BOOT_NOT_CONFIRMED" "START_DEFERRED_TIMEOUT_ERROR"
assert_no_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_DEFERRED_TIMEOUT_NO_PASS"
assert_calls "^sleep 1$" "$POLL_MAX" "START_DEFERRED_TIMEOUT_BOUNDED"
assert_calls "^xcrun simctl boot [^ ]*$" 1 "START_DEFERRED_TIMEOUT_NO_REBOOT"
assert_calls "^open" 0 "START_DEFERRED_TIMEOUT_NO_DEVICEHUB"
# 1 (require_device) + 1 (first observation) + POLL_MAX (one per wait).
assert_calls "simctl list devices" "$((POLL_MAX + 2))" "START_DEFERRED_TIMEOUT_LIST_BOUNDED"

# DeviceHub absent.
new_case
export MOCK_OPEN_FAIL=1
mgr start "$U_BOOT"
assert_rc 82 "START_DEVICEHUB_ABSENT_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICEHUB_UNAVAILABLE" "START_DEVICEHUB_ABSENT_ERROR"
assert_err "DeviceHub" "START_DEVICEHUB_ABSENT_OPEN_MESSAGE_PRESERVED"
assert_no_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_DEVICEHUB_ABSENT_NO_PASS"
assert_no_out "CBS_IOS_RUNTIME_DEVICEHUB=OPENED" "START_DEVICEHUB_ABSENT_NOT_OPENED"
assert_calls "simctl boot" 0 "START_DEVICEHUB_ABSENT_NO_BOOT"

new_case
export MOCK_OPEN_FAIL=1
mgr start "$U_SHUT"
assert_rc 82 "START_SHUTDOWN_DEVICEHUB_ABSENT_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICEHUB_UNAVAILABLE" "START_SHUTDOWN_DEVICEHUB_ABSENT_ERROR"
assert_no_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_SHUTDOWN_DEVICEHUB_ABSENT_NO_PASS"
echo "TEST_IOS_SIMULATOR_MANAGER_START=PASS"

# --- stop -------------------------------------------------------------------

new_case
mgr stop "$U_BOOT"
assert_rc 0 "STOP_BOOTED_RC"
assert_out "CBS_IOS_RUNTIME_DEVICE=$U_BOOT" "STOP_DEVICE"
assert_out "CBS_IOS_RUNTIME_STATE=SHUTDOWN" "STOP_STATE"
assert_out "CBS_IOS_RUNTIME_ACTION=SHUTDOWN" "STOP_ACTION"
assert_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "STOP_RESULT"
assert_calls "simctl shutdown $U_BOOT" 1 "STOP_SHUTDOWN_ONCE"
assert_calls "^open" 0 "STOP_NO_DEVICEHUB"
grep -Fq "($U_BOOT) (Shutdown)" "$MOCK_DIR/devices.txt" || fail "STOP_DB_SHUTDOWN"
assert_no_unexpected "STOP_NO_UNEXPECTED"

new_case
mgr stop "$U_SHUT"
assert_rc 0 "STOP_ALREADY_STOPPED_RC"
assert_out "CBS_IOS_RUNTIME_ACTION=NOOP" "STOP_ALREADY_STOPPED_ACTION"
assert_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "STOP_ALREADY_STOPPED_RESULT"
assert_calls "simctl shutdown" 0 "STOP_ALREADY_STOPPED_NO_SHUTDOWN"
assert_no_mutation "STOP_ALREADY_STOPPED_NO_MUTATION"

# Idempotence: stop twice.
new_case
mgr stop "$U_BOOT"
assert_rc 0 "STOP_IDEMPOTENT_FIRST_RC"
mgr stop "$U_BOOT"
assert_rc 0 "STOP_IDEMPOTENT_SECOND_RC"
assert_out "CBS_IOS_RUNTIME_ACTION=NOOP" "STOP_IDEMPOTENT_SECOND_ACTION"
assert_calls "simctl shutdown" 1 "STOP_IDEMPOTENT_SHUTDOWN_ONCE"
assert_no_unexpected "STOP_IDEMPOTENT_NO_UNEXPECTED"

# start / stop / start round trip.
new_case
mgr start "$U_SHUT"
assert_rc 0 "ROUNDTRIP_START_RC"
mgr stop "$U_SHUT"
assert_rc 0 "ROUNDTRIP_STOP_RC"
mgr start "$U_SHUT"
assert_rc 0 "ROUNDTRIP_RESTART_RC"
assert_calls "^xcrun simctl boot [^ ]*$" 2 "ROUNDTRIP_BOOT_TWICE"
assert_calls "^xcrun simctl bootstatus [^ ]* -b$" 2 "ROUNDTRIP_BOOTSTATUS_TWICE"
assert_calls "simctl shutdown" 1 "ROUNDTRIP_SHUTDOWN_ONCE"
assert_no_unexpected "ROUNDTRIP_NO_UNEXPECTED"

new_case
mgr stop "$U_MISSING"
assert_rc 82 "STOP_MISSING_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_MISSING" "STOP_MISSING_ERROR"
assert_no_mutation "STOP_MISSING_NO_MUTATION"

new_case
mgr stop "$U_UNAV"
assert_rc 82 "STOP_UNAVAILABLE_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_UNAVAILABLE" "STOP_UNAVAILABLE_ERROR"
assert_no_mutation "STOP_UNAVAILABLE_NO_MUTATION"

for transitional in "$U_BOOTING" "$U_SHUTTING"; do
    new_case
    mgr stop "$transitional"
    assert_rc 82 "STOP_TRANSITIONING_RC_$transitional"
    assert_err "CBS_IOS_RUNTIME_ERROR=DEVICE_STATE_TRANSITIONING" "STOP_TRANSITIONING_ERROR_$transitional"
    assert_no_mutation "STOP_TRANSITIONING_NO_MUTATION_$transitional"
done

new_case
export MOCK_LIST_FAIL=1
mgr stop "$U_BOOT"
assert_rc 82 "STOP_LIST_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_LIST_FAILED" "STOP_LIST_ERROR"
assert_no_mutation "STOP_LIST_ERROR_NO_MUTATION"

new_case
export MOCK_SHUTDOWN_FAIL=1
mgr stop "$U_BOOT"
assert_rc 82 "STOP_SHUTDOWN_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_SHUTDOWN_FAILED" "STOP_SHUTDOWN_ERROR"
assert_err "simulated shutdown failure" "STOP_SHUTDOWN_ERROR_SIMCTL_MESSAGE_PRESERVED"
assert_no_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "STOP_SHUTDOWN_ERROR_NO_PASS"
assert_db_unchanged "STOP_SHUTDOWN_ERROR_DB"

new_case
export MOCK_SHUTDOWN_NOEFFECT=1
mgr stop "$U_BOOT"
assert_rc 82 "STOP_NOT_CONFIRMED_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SHUTDOWN_NOT_CONFIRMED" "STOP_NOT_CONFIRMED_ERROR"
assert_no_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "STOP_NOT_CONFIRMED_NO_PASS"
assert_calls "^sleep 1$" "$POLL_MAX" "STOP_NOT_CONFIRMED_WAIT_BOUNDED"

# Immediate shutdown: no wait needed.
new_case
mgr stop "$U_BOOT"
assert_rc 0 "STOP_IMMEDIATE_RC"
assert_calls "^sleep" 0 "STOP_IMMEDIATE_NO_WAIT"

# Deferred shutdown: simctl list reports Shutting Down for a few observations,
# then Shutdown. The transition is waited for (bounded).
new_case
export MOCK_SHUTDOWN_DEFER=3
mgr stop "$U_BOOT"
assert_rc 0 "STOP_DEFERRED_RC"
assert_out "CBS_IOS_RUNTIME_DEVICE=$U_BOOT" "STOP_DEFERRED_DEVICE"
assert_out "CBS_IOS_RUNTIME_STATE=SHUTDOWN" "STOP_DEFERRED_STATE"
assert_out "CBS_IOS_RUNTIME_ACTION=SHUTDOWN" "STOP_DEFERRED_ACTION"
assert_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "STOP_DEFERRED_RESULT"
assert_calls "simctl shutdown $U_BOOT" 1 "STOP_DEFERRED_SHUTDOWN_ONCE"
assert_calls "^sleep 1$" 3 "STOP_DEFERRED_WAITED_THREE_TIMES"
assert_calls "^open" 0 "STOP_DEFERRED_NO_DEVICEHUB"
grep -Fq "($U_BOOT) (Shutdown)" "$MOCK_DIR/devices.txt" || fail "STOP_DEFERRED_DB_SHUTDOWN"
assert_no_unexpected "STOP_DEFERRED_NO_UNEXPECTED"

# Deferred shutdown completing exactly on the last allowed observation.
new_case
export MOCK_SHUTDOWN_DEFER="$POLL_MAX"
mgr stop "$U_BOOT"
assert_rc 0 "STOP_DEFERRED_AT_BOUND_RC"
assert_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "STOP_DEFERRED_AT_BOUND_RESULT"
assert_calls "^sleep 1$" "$POLL_MAX" "STOP_DEFERRED_AT_BOUND_WAITS"

# Deferred shutdown one observation too late: timeout.
new_case
export MOCK_SHUTDOWN_DEFER="$((POLL_MAX + 1))"
mgr stop "$U_BOOT"
assert_rc 82 "STOP_DEFERRED_JUST_TOO_LATE_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SHUTDOWN_NOT_CONFIRMED" "STOP_DEFERRED_JUST_TOO_LATE_ERROR"
assert_calls "^sleep 1$" "$POLL_MAX" "STOP_DEFERRED_JUST_TOO_LATE_BOUNDED"

# Shutdown timeout: the device stays in Shutting Down forever. The wait is
# bounded, the error is structured, there is no PASS and no second shutdown.
new_case
export MOCK_SHUTDOWN_DEFER=1000
mgr stop "$U_BOOT"
assert_rc 82 "STOP_TIMEOUT_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SHUTDOWN_NOT_CONFIRMED" "STOP_TIMEOUT_ERROR"
assert_no_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "STOP_TIMEOUT_NO_PASS"
assert_no_out "CBS_IOS_RUNTIME_STATE=SHUTDOWN" "STOP_TIMEOUT_NO_STATE_CLAIM"
assert_calls "^sleep 1$" "$POLL_MAX" "STOP_TIMEOUT_BOUNDED"
assert_calls "simctl shutdown" 1 "STOP_TIMEOUT_NO_RETRY"
# 1 (require_device) + 1 (first observation) + POLL_MAX (one per wait).
assert_calls "simctl list devices" "$((POLL_MAX + 2))" "STOP_TIMEOUT_LIST_BOUNDED"
assert_no_unexpected "STOP_TIMEOUT_NO_UNEXPECTED"

# simctl list failing in the middle of the wait (list calls: 1 require_device,
# 2 first observation, 3 fails after one sleep) stays a structured error and
# the wait stops immediately.
new_case
export MOCK_SHUTDOWN_DEFER=5
export MOCK_LIST_FAIL_AFTER=2
mgr stop "$U_BOOT"
assert_rc 82 "STOP_WAIT_LIST_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_LIST_FAILED" "STOP_WAIT_LIST_ERROR"
assert_no_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "STOP_WAIT_LIST_ERROR_NO_PASS"
assert_calls "^sleep 1$" 1 "STOP_WAIT_LIST_ERROR_STOPPED_WAITING"

new_case
export MOCK_BOOT_DEFER=5
export MOCK_LIST_FAIL_AFTER=2
mgr start "$U_SHUT"
assert_rc 82 "START_WAIT_LIST_ERROR_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=SIMCTL_LIST_FAILED" "START_WAIT_LIST_ERROR"
assert_no_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "START_WAIT_LIST_ERROR_NO_PASS"
assert_calls "^sleep 1$" 1 "START_WAIT_LIST_ERROR_STOPPED_WAITING"
assert_calls "^open" 0 "START_WAIT_LIST_ERROR_NO_DEVICEHUB"
echo "TEST_IOS_SIMULATOR_MANAGER_TRANSITIONS=PASS"
echo "TEST_IOS_SIMULATOR_MANAGER_STOP=PASS"
echo "TEST_IOS_SIMULATOR_MANAGER_IDEMPOTENCE=PASS"
echo "TEST_IOS_SIMULATOR_MANAGER_NO_MUTATION=PASS"

# --- entrypoint wiring (bin/cbs) --------------------------------------------

new_case
cbs_run help
assert_rc 0 "CBS_HELP_RC"
for line in \
    "cbs runtime ios list" \
    "cbs runtime ios ensure <UDID>" \
    "cbs runtime ios start <UDID>" \
    "cbs runtime ios status <UDID>" \
    "cbs runtime ios stop <UDID>"; do
    assert_out "$line" "CBS_HELP_LISTS_${line}"
done

new_case
cbs_run runtime ios list
assert_rc 0 "CBS_LIST_RC"
assert_out "CBS_IOS_RUNTIME_LIST_RESULT=PASS" "CBS_LIST_RESULT"

new_case
cbs_run runtime ios status "$U_BOOT"
assert_rc 0 "CBS_STATUS_RC"
assert_out "CBS_IOS_RUNTIME_STATE=BOOTED" "CBS_STATUS_STATE"
assert_no_mutation "CBS_STATUS_NO_MUTATION"

new_case
cbs_run runtime ios ensure "$U_SHUT"
assert_rc 0 "CBS_ENSURE_RC"
assert_out "CBS_IOS_RUNTIME_ENSURE_RESULT=PASS" "CBS_ENSURE_RESULT"

new_case
cbs_run runtime ios start "$U_SHUT"
assert_rc 0 "CBS_START_RC"
assert_out "CBS_IOS_RUNTIME_START_RESULT=PASS" "CBS_START_RESULT"

new_case
cbs_run runtime ios stop "$U_BOOT"
assert_rc 0 "CBS_STOP_RC"
assert_out "CBS_IOS_RUNTIME_STOP_RESULT=PASS" "CBS_STOP_RESULT"

new_case
cbs_run runtime ios bogus
assert_rc 64 "CBS_UNKNOWN_IOS_ACTION_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=USAGE" "CBS_UNKNOWN_IOS_ACTION_ERROR"

new_case
cbs_run runtime ios
assert_rc 64 "CBS_IOS_NO_ACTION_RC"

new_case
cbs_run runtime ios start "bad-udid"
assert_rc 64 "CBS_INVALID_UDID_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=UDID_INVALID" "CBS_INVALID_UDID_ERROR"
assert_calls "^xcrun" 0 "CBS_INVALID_UDID_NO_XCRUN"

new_case
export MOCK_UNAME="Linux"
cbs_run runtime ios list
assert_rc 82 "CBS_NOT_MACOS_RC"
assert_err "CBS_IOS_RUNTIME_ERROR=HOST_NOT_MACOS" "CBS_NOT_MACOS_ERROR"
assert_no_host_call "CBS_NOT_MACOS_NO_IOS_COMMAND"

new_case
cbs_run runtime windows list
assert_rc 2 "CBS_UNKNOWN_RUNTIME_TYPE_RC"
assert_err "CBS_ERROR=UNKNOWN_RUNTIME_TYPE" "CBS_UNKNOWN_RUNTIME_TYPE_ERROR"
echo "TEST_IOS_SIMULATOR_MANAGER_ENTRYPOINT=PASS"

echo "TEST_IOS_SIMULATOR_MANAGER_CASES=$CASE_N"
echo "TEST_IOS_SIMULATOR_MANAGER_RESULT=PASS"
