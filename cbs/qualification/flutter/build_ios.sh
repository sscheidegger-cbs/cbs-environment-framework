#!/usr/bin/env bash

# D04b-C.2g - Flutter/iOS qualification: BUILD_IOS.
#
#   build_ios.sh KEY=VALUE...
#
# The arguments are the request defined by contract.sh (data only). BUILD_IOS
# runs one fixed command in the isolated checkout, and nothing else:
#
#   flutter build ios --simulator --no-codesign
#
# That command is the whole of what the contract says about this operation:
# the only target is "ios-simulator" and the operation is "unsigned simulator
# build, no archive" (README, "Operations and actions"). The four words after
# "flutter" are constants of this file. No value of the request, of the
# checkout or of the environment is ever part of the command:
#
#   build ios       the iOS application bundle, not an archive, not an IPA
#                   (no "ipa", no "--export-*", no "--obfuscate")
#   --simulator     the only target of the contract
#   --no-codesign   explicit: nothing is signed, whatever the project says
#
# No build mode (--debug, --profile, --release) is added: the contract carries
# no such parameter, and the mode is left to the default of flutter for a
# simulator build. No Xcode, simctl or CocoaPods command is run by this file;
# nothing is published or distributed; no simulator is created, booted, erased
# or deleted (a simulator_udid of the request is only checked by PREFLIGHT).
#
# What is common to the operations (request validation, evidence location,
# PREFLIGHT gate, checkout check, bounded supervised execution, timeout,
# redaction, log bound, classification, structured answer, evidence files) is
# the common execution engine, execution.sh (D04b-C.2e), which this file
# sources and does not duplicate. This file keeps what belongs to BUILD_IOS:
# the selected action, the fixed command, the lookup of flutter, the guards
# below and the order of the steps.
#
# Guards of this operation, all before anything is written:
#
#   - Environment. Flutter turns every FLUTTER_XCODE_<SETTING> variable of its
#     environment into an Xcode build setting (for instance a development team
#     or a signing identity). That would be a signing configuration that the
#     request never declared: the run is refused (BLOCKED, ARGUMENT_REFUSED)
#     when such a variable is exported, and nothing is unset or rewritten. The
#     name of the variable is never printed.
#   - Checkout. The build writes in "build/", ".dart_tool/" and "ios/" (and
#     "ios/Flutter/") of the checkout. When one of them is a symbolic link, the
#     build would write through it, possibly outside the isolation: the run is
#     refused (BLOCKED, PATH_NOT_ALLOWED, key isolation_id). A missing
#     directory is left to flutter, which reports it (FAIL).
#
# What this operation writes, and only this, under evidence_root (which must
# already exist: it is never created here):
#   <evidence_root>/<qualification_id>/BUILD_IOS.log      redacted, bounded output
#   <evidence_root>/<qualification_id>/BUILD_IOS.result   the structured answer
# Files are created with an exclusive create (never overwritten), mode 600, in
# a directory of mode 700 (engine). An evidence file that already exists
# refuses the run (PATH_NOT_ALLOWED): a new qualification_id is needed.
#
# What flutter itself may write is out of this file's control: the checkout
# (build/, .dart_tool/, ios/Flutter/, ios/Pods/, pubspec.lock, ...) and the
# caches of the user. The source repository is never a working directory,
# never written, never read. Nothing is cleaned afterwards: a checkout dirtied
# by the build is refused by the next PREFLIGHT, a new isolation is needed.
#
# Results (contract.sh):
#   PASS     flutter exited with 0 (tool status 0)
#   FAIL     COMMAND_FAILED (flutter exited non-zero, its exact status is
#            OPERATION_TOOL_RC), TIMEOUT, LOG_LIMIT_EXCEEDED, EVIDENCE_FAILURE
#   BLOCKED  request refused (including an action list without build_ios),
#            ARGUMENT_REFUSED (FLUTTER_XCODE_* exported), PATH_NOT_ALLOWED
#            (evidence location, link in the checkout), ISOLATION_REJECTED
#            (checkout path), TOOL_UNAVAILABLE (flutter vanished after
#            PREFLIGHT)
#   NOT_RUN  PREFLIGHT_NOT_PASSED
# NETWORK_FAILURE is never emitted (the real messages of the tool are not
# frozen).
#
# Compatible with Bash 3.2 (macOS) and later: no associative array, no empty
# array expansion, no case conversion expansion, no here-string, no GNU-only
# option. BSD tools only.

unset CDPATH

CBS_FLUTTER_QUAL_BUILD_IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [[ -z "$CBS_FLUTTER_QUAL_BUILD_IOS_DIR" || ! -f "$CBS_FLUTTER_QUAL_BUILD_IOS_DIR/execution.sh" ]]; then
    echo "CBS_FLUTTER_QUAL_ERROR=EXECUTION_UNAVAILABLE" >&2
    return 1 2>/dev/null || exit 1
fi

# The common execution engine: it sources PREFLIGHT (which loads the contract,
# scrubs the environment of Git and BASH_ENV, and exposes the helpers reused
# below). Nothing runs when sourced.
# shellcheck source=/dev/null
source "$CBS_FLUTTER_QUAL_BUILD_IOS_DIR/execution.sh"

# The words of the command that follow the path of flutter. Never built from
# anything.
readonly CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_BUILD="build"
readonly CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_PLATFORM="ios"
readonly CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_SIMULATOR="--simulator"
readonly CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_UNSIGNED="--no-codesign"

# Directories of the checkout that the build writes in (relative, fixed).
readonly CBS_FLUTTER_QUAL_BUILD_IOS_WRITTEN_DIRECTORIES="build .dart_tool ios ios/Flutter"

# Prefix of the environment variables that flutter turns into Xcode build
# settings.
readonly CBS_FLUTTER_QUAL_BUILD_IOS_XCODE_ENV_PREFIX="FLUTTER_XCODE_"

# --- Guards ----------------------------------------------------------------------

# No Xcode build setting may come from the environment: it could carry a
# signing configuration that the request never declared. Nothing is read from
# the values, nothing is unset. Records the refusal and returns 1 otherwise.
_cbs_flutter_qual_bld_check_environment() {
    local found

    found="$(compgen -e "$CBS_FLUTTER_QUAL_BUILD_IOS_XCODE_ENV_PREFIX" 2>/dev/null || true)"

    if [[ -n "$found" ]]; then
        EX_REJECTED_KEY=""
        _cbs_flutter_qual_ex_set "ARGUMENT_REFUSED"
        return 1
    fi

    return 0
}

# The directories the build writes in must not be symbolic links: the build
# would write through them. Reads the checkout only. Records the refusal and
# returns 1 otherwise.
_cbs_flutter_qual_bld_check_tree() {
    local name

    for name in $CBS_FLUTTER_QUAL_BUILD_IOS_WRITTEN_DIRECTORIES; do
        if [[ -L "$EX_CHECKOUT/$name" ]]; then
            EX_REJECTED_KEY="isolation_id"
            _cbs_flutter_qual_ex_set "PATH_NOT_ALLOWED"
            return 1
        fi
    done

    return 0
}

# --- Entry -----------------------------------------------------------------------

# Arguments: KEY=VALUE... (the request).
cbs_flutter_qual_build_ios() {
    local flutter

    _cbs_flutter_qual_ex_reset "$CBS_FLUTTER_QUAL_OP_BUILD_IOS" "flutter_build_ios"

    # ---- 1. request (this operation is the BUILD_IOS: it must have been selected)

    if ! _cbs_flutter_qual_ex_request "$@"; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 1b. nothing in the environment may configure the signing

    if ! _cbs_flutter_qual_bld_check_environment; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 2. evidence location (nothing is created yet)

    if ! _cbs_flutter_qual_ex_evidence_location; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 3. PREFLIGHT must be PASS (it verifies the checkout and the toolchain)

    if ! _cbs_flutter_qual_ex_preflight_gate "$@"; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 4. the checkout and the tool

    if ! _cbs_flutter_qual_ex_checkout; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    if ! flutter="$(_cbs_flutter_qual_pf_find_tool flutter)"; then
        _cbs_flutter_qual_ex_set "TOOL_UNAVAILABLE"
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 5. where the build will write, in the isolated checkout

    if ! _cbs_flutter_qual_bld_check_tree; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    # ---- 6. evidence, then the command

    if ! _cbs_flutter_qual_ex_evidence_open; then
        _cbs_flutter_qual_ex_conclude
        return $?
    fi

    _cbs_flutter_qual_ex_execute "$flutter" \
        "$CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_BUILD" \
        "$CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_PLATFORM" \
        "$CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_SIMULATOR" \
        "$CBS_FLUTTER_QUAL_BUILD_IOS_ARGUMENT_UNSIGNED"

    _cbs_flutter_qual_ex_conclude
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -u
    CBS_FLUTTER_QUAL_BUILD_IOS_RC=0
    cbs_flutter_qual_build_ios "$@" || CBS_FLUTTER_QUAL_BUILD_IOS_RC=$?
    exit "$CBS_FLUTTER_QUAL_BUILD_IOS_RC"
fi
