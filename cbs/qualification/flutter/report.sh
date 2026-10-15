#!/usr/bin/env bash

# D04b-C.2h - Flutter/iOS qualification: REPORT.
#
#   report.sh KEY=VALUE...
#
# The arguments are the request defined by contract.sh (data only, same
# validation, no new request format). REPORT consolidates the evidence that the
# other operations already left under
#
#   <evidence_root>/<qualification_id>/<OPERATION>.result
#
# and nothing else. It is a read-only observer:
#
#   - it never runs PREFLIGHT, ANALYZE, TEST or BUILD_IOS, never calls Flutter,
#     Dart, Xcode, simctl, Git, SSH or the network, and never starts any other
#     external program than the basic tools of the system (dirname, find, wc,
#     tr);
#   - it never creates, modifies, moves, cleans or deletes anything: not the
#     evidence, not the checkouts, not the isolations, not the source
#     repository. It writes no REPORT.result: the structured answer is printed
#     on stdout only (the contract defines no evidence file for REPORT, and
#     the evidence of a qualification is never changed afterwards);
#   - it never sources, evaluates, expands or executes a ".result" file or
#     anything it contains. A file is read line by line as data, every line
#     must be "KEY=VALUE" with a closed character set and a key of the closed
#     list of the answer of its operation; anything else is refused;
#   - it never follows a symbolic link: a link in place of the evidence
#     directory, of the evidence root or of a ".result" file is refused;
#   - it never prints what a file contains, only closed values of the contract
#     (operations, results, reasons, numeric codes) and the identifiers of the
#     request.
#
# Selection. The selected operations are exactly the actions of the request
# ("actions", contract order) that name a reportable operation. The request must
# select "report" (otherwise ACTION_NOT_ALLOWED). An operation that is not
# selected is SKIPPED (NOT_SELECTED): its file is never read, even when one
# exists. REPORT itself is not part of the consolidation.
#
# Evidence of each selected operation.
#   ANALYZE, TEST, BUILD_IOS   <OPERATION>.result, written by the executor only
#       once PREFLIGHT passed and the evidence directory was opened. A file that
#       is read must be coherent, otherwise the operation is BLOCKED with
#       INPUT_INVALID (a link, an unsafe owner or mode: PATH_NOT_ALLOWED):
#         - the operation, the answer of the operation and the final result
#           agree; the result is PASS or FAIL (the only results an executor
#           writes); result, reason and return code agree with the contract;
#           a PASS carries a tool status of 0;
#         - the qualification identifier and the observed commit are exactly
#           those of the request; the PREFLIGHT recorded in the file is PASS;
#         - the evidence is WRITTEN (FAILED is accepted for a FAIL only).
#       No file, and no trace of a started run (".log" or ".log.partial"): the
#       operation is NOT_RUN / NOT_EXECUTED. A trace of a run without answer is
#       an incomplete evidence: BLOCKED / INPUT_INVALID, never a result.
#       The refusal of an operation before its evidence was opened writes
#       nothing, so it cannot be told from an operation never launched: both
#       are NOT_RUN. The ".log" content is not read.
#   PREFLIGHT   the contract gives PREFLIGHT no evidence file: it writes nothing.
#       Its only recorded trace is the "PREFLIGHT_RESULT" fact that every
#       executor writes in its own ".result" (always PASS: an executor starts
#       only after a PASS). PREFLIGHT is therefore PASS (evidence DERIVED) when
#       at least one selected operation's file was read and found coherent,
#       and NOT_RUN / NOT_EXECUTED otherwise. A qualification that selected
#       PREFLIGHT alone can thus never be consolidated as PASS: that is a limit
#       of the contract, not something REPORT papers over.
#
# Consolidated result: cbs_flutter_qual_aggregate (contract) over PREFLIGHT,
# ANALYZE, TEST and BUILD_IOS: FAIL, then BLOCKED, then NOT_RUN win over PASS;
# SKIPPED alone is never a PASS. The reason is the one of the first operation, in
# contract order, that carries the consolidated result (NOT_EXECUTED when
# nothing but SKIPPED). The exit status is the contract code of that reason (0
# for PASS). REPORT never reports a PASS for an operation it did not observe.
#
# Refusals of the whole report (nothing is consolidated, only the answer of
# REPORT is printed): request refused (contract reasons), "report" not selected
# (ACTION_NOT_ALLOWED), evidence root or evidence directory not usable, absent
# or a link (PATH_NOT_ALLOWED on evidence_root; an absent evidence directory is
# not a refusal: no operation left evidence).
#
# Limits: files are checked, then read: nothing makes the pair atomic, a file
# swapped in between by a process of the same user would be read. Evidence
# written after the read is not seen.
#
# Compatible with Bash 3.2 (macOS) and later: no associative array, no empty
# array expansion, no case conversion expansion, no here-string, no GNU-only
# option. BSD tools only.

unset CDPATH

# A "loaded" guard coming from the environment would skip the contracts: they
# are always loaded from this repository.
unset CBS_FLUTTER_QUAL_CONTRACT_LOADED CBS_ISOLATION_CONTRACT_LOADED CBS_WORKTREE_CONTRACT_LOADED 2>/dev/null || true

unset BASH_ENV
export LC_ALL=C

CBS_FLUTTER_QUAL_REPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [[ -z "$CBS_FLUTTER_QUAL_REPORT_DIR" || ! -f "$CBS_FLUTTER_QUAL_REPORT_DIR/contract.sh" ]]; then
    echo "CBS_FLUTTER_QUAL_ERROR=CONTRACT_UNAVAILABLE" >&2
    return 1 2>/dev/null || exit 1
fi

# shellcheck source=/dev/null
source "$CBS_FLUTTER_QUAL_REPORT_DIR/contract.sh"

# Operations consolidated, in contract order (REPORT is not one of them), and
# those that leave a ".result" file.
CBS_FLUTTER_QUAL_REPORT_OPERATIONS="PREFLIGHT ANALYZE TEST BUILD_IOS"
CBS_FLUTTER_QUAL_REPORT_EVIDENCE_OPERATIONS="ANALYZE TEST BUILD_IOS"

# Bounds of a ".result" file (an answer holds about 20 short lines).
CBS_FLUTTER_QUAL_REPORT_RESULT_MAX_BYTES=8192
CBS_FLUTTER_QUAL_REPORT_RESULT_MAX_LINES=40

# Closed list of the keys of an answer. "FACT_" names stand for
# CBS_FLUTTER_QUAL_<OPERATION>_<NAME>; the others are the generic lines of the
# contract (CBS_FLUTTER_QUAL_<NAME>).
CBS_FLUTTER_QUAL_REPORT_NAMES="OPERATION OPERATION_RESULT OPERATION_REASON OPERATION_RC OPERATION_TOOL_RC REASON CONTRACT_VERSION RESULT FACT_QUALIFICATION_ID FACT_PREFLIGHT_RESULT FACT_PREFLIGHT_REASON FACT_COMMIT_OBSERVED FACT_FLUTTER_VERSION FACT_COMMAND FACT_DURATION_SECONDS FACT_LOG_BYTES FACT_LOG_CRC FACT_LOG_TRUNCATED FACT_EVIDENCE"

# --- State ---------------------------------------------------------------------

# RP_R_<OP> result, RP_X_<OP> reason, RP_T_<OP> tool status, RP_E_<OP> evidence
# state (NOT_SELECTED, ABSENT, READ, DERIVED, REJECTED).
_cbs_flutter_qual_rp_reset() {
    local operation

    for operation in $CBS_FLUTTER_QUAL_REPORT_OPERATIONS; do
        _cbs_flutter_qual_rp_set "$operation" "SKIPPED" "NOT_SELECTED" "" "NOT_SELECTED"
    done

    RP_QUALIFICATION_ID=""
    RP_COMMIT_EXPECTED=""
    RP_COMMIT_OBSERVED=""
    RP_REASON=""
    RP_KEY=""
}

# Arguments: OPERATION RESULT REASON TOOL_RC EVIDENCE
_cbs_flutter_qual_rp_set() {
    printf -v "RP_R_$1" '%s' "$2"
    printf -v "RP_X_$1" '%s' "$3"
    printf -v "RP_T_$1" '%s' "$4"
    printf -v "RP_E_$1" '%s' "$5"
}

# Arguments: OPERATION REASON EVIDENCE. The result is the class of the reason:
# they never diverge.
_cbs_flutter_qual_rp_set_reason() {
    local result

    result="$(cbs_flutter_qual_result_for_reason "$2")" || result="BLOCKED"

    _cbs_flutter_qual_rp_set "$1" "$result" "$2" "" "$3"
}

# Arguments: LETTER OPERATION (R, X, T or E). Prints the value.
_cbs_flutter_qual_rp_get() {
    local variable="RP_$1_$2"

    printf '%s' "${!variable}"
}

# --- Read-only checks ----------------------------------------------------------

# Argument: PATH. Succeeds when something exists there (a dangling symbolic link
# counts as existing).
_cbs_flutter_qual_rp_present() {
    [[ -e "$1" || -L "$1" ]]
}

# Argument: PATH. Succeeds when it is not writable by group or others.
_cbs_flutter_qual_rp_not_shared() {
    local found

    found="$(find "$1" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" || return 1
    [[ -z "$found" ]]
}

# Argument: DIRECTORY. Succeeds when it is an existing directory of this user,
# canonical (no symbolic link in any component), readable, not writable by
# group or others.
_cbs_flutter_qual_rp_dir_is_private() {
    local path="$1"

    [[ -d "$path" && ! -L "$path" && -O "$path" && -r "$path" && -x "$path" ]] || return 1
    cbs_flutter_qual_dir_is_canonical "$path" || return 1
    _cbs_flutter_qual_rp_not_shared "$path"
}

# Argument: FILE. Succeeds when it is a regular file (never a link) of this user,
# readable, not writable by group or others.
_cbs_flutter_qual_rp_file_is_private() {
    local path="$1"

    [[ -f "$path" && ! -L "$path" && -O "$path" && -r "$path" ]] || return 1
    _cbs_flutter_qual_rp_not_shared "$path"
}

# --- Reading an answer (data only) ---------------------------------------------

_cbs_flutter_qual_rp_clear() {
    local name

    for name in $CBS_FLUTTER_QUAL_REPORT_NAMES; do
        printf -v "RP_P_$name" '%s' ""
    done
}

# Arguments: NAME VALUE. Keeps the value of a key of the closed list; fails on
# an unknown name or on a key that was already given.
_cbs_flutter_qual_rp_store() {
    local name="$1"
    local value="$2"
    local variable

    case " $CBS_FLUTTER_QUAL_REPORT_NAMES " in
        *" $name "*) ;;
        *) return 1 ;;
    esac

    variable="RP_P_$name"
    [[ -z "${!variable}" ]] || return 1

    printf -v "$variable" '%s' "$value"
}

# Arguments: OPERATION FILE. Reads one ".result" file as data and checks it
# against the request (RP_QUALIFICATION_ID, RP_COMMIT_EXPECTED). Succeeds only
# for a coherent answer, and then records the operation. Nothing is printed.
_cbs_flutter_qual_rp_read_result() {
    local operation="$1"
    local file="$2"
    local prefix="CBS_FLUTTER_QUAL_${operation}_"
    local line_pattern='^[A-Z][A-Z0-9_]{0,95}=[A-Za-z0-9._+-]{1,128}$'
    local size_pattern='^[0-9]{1,9}$'
    local line
    local key
    local value
    local name
    local size
    local bytes=0
    local count=0
    local last_key=""
    local result
    local reason
    local tool_rc

    _cbs_flutter_qual_rp_clear

    size="$(wc -c < "$file" 2>/dev/null | tr -d ' ')"
    [[ "$size" =~ $size_pattern ]] || return 1
    size="$((10#$size))"
    [[ "$size" -ge 1 && "$size" -le "$CBS_FLUTTER_QUAL_REPORT_RESULT_MAX_BYTES" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        count=$((count + 1))
        [[ "$count" -le "$CBS_FLUTTER_QUAL_REPORT_RESULT_MAX_LINES" ]] || return 1

        # The byte count of what was read must end up equal to the size of the
        # file: a NUL byte or a missing final newline makes it differ.
        bytes=$((bytes + ${#line} + 1))

        [[ "$line" =~ $line_pattern ]] || return 1

        key="${line%%=*}"
        value="${line#*=}"

        case "$key" in
            CBS_FLUTTER_QUAL_OPERATION) name="OPERATION" ;;
            CBS_FLUTTER_QUAL_OPERATION_RESULT) name="OPERATION_RESULT" ;;
            CBS_FLUTTER_QUAL_OPERATION_REASON) name="OPERATION_REASON" ;;
            CBS_FLUTTER_QUAL_OPERATION_RC) name="OPERATION_RC" ;;
            CBS_FLUTTER_QUAL_OPERATION_TOOL_RC) name="OPERATION_TOOL_RC" ;;
            CBS_FLUTTER_QUAL_REASON) name="REASON" ;;
            CBS_FLUTTER_QUAL_CONTRACT_VERSION) name="CONTRACT_VERSION" ;;
            CBS_FLUTTER_QUAL_RESULT) name="RESULT" ;;
            "$prefix"*) name="FACT_${key#"$prefix"}" ;;
            *) return 1 ;;
        esac

        _cbs_flutter_qual_rp_store "$name" "$value" || return 1
        last_key="$key"
    done < "$file"

    [[ "$bytes" -eq "$size" ]] || return 1

    # The final result is the last line of an answer.
    [[ "$last_key" == "CBS_FLUTTER_QUAL_RESULT" ]] || return 1

    # The answer is the one of this operation, under this contract.
    [[ "$RP_P_OPERATION" == "$operation" ]] || return 1
    [[ "$RP_P_CONTRACT_VERSION" == "$CBS_FLUTTER_QUAL_CONTRACT_VERSION" ]] || return 1

    # Operation result, final result and reasons agree with one another and
    # with the contract. An executor writes only PASS or FAIL.
    result="$RP_P_OPERATION_RESULT"
    reason="$RP_P_OPERATION_REASON"

    [[ -n "$result" && "$result" == "$RP_P_RESULT" && "$reason" == "$RP_P_REASON" ]] || return 1

    case "$result" in
        PASS|FAIL) ;;
        *) return 1 ;;
    esac

    cbs_flutter_qual_result_reason_consistent "$result" "$reason" || return 1
    [[ "$RP_P_OPERATION_RC" == "$(cbs_flutter_qual_rc_for_reason "$reason")" ]] || return 1

    tool_rc="$RP_P_OPERATION_TOOL_RC"

    if [[ -n "$tool_rc" ]]; then
        [[ "$tool_rc" =~ $CBS_FLUTTER_QUAL_PATTERN_TOOL_RC ]] || return 1
        [[ "$((10#$tool_rc))" -le 255 ]] || return 1
        tool_rc="$((10#$tool_rc))"
    fi

    if [[ "$result" == "PASS" ]]; then
        [[ "$tool_rc" == "0" ]] || return 1
    fi

    # The identifiers of the request: same qualification, same commit.
    [[ "$RP_P_FACT_QUALIFICATION_ID" == "$RP_QUALIFICATION_ID" ]] || return 1
    [[ "$RP_P_FACT_COMMIT_OBSERVED" == "$RP_COMMIT_EXPECTED" ]] || return 1

    # An executor writes its answer only after a PASS of PREFLIGHT.
    [[ "$RP_P_FACT_PREFLIGHT_RESULT" == "PASS" && -z "$RP_P_FACT_PREFLIGHT_REASON" ]] || return 1

    case "$RP_P_FACT_EVIDENCE" in
        WRITTEN) ;;
        FAILED) [[ "$result" == "FAIL" ]] || return 1 ;;
        *) return 1 ;;
    esac

    _cbs_flutter_qual_rp_set "$operation" "$result" "$reason" "$tool_rc" "READ"
}

# Arguments: OPERATION EVIDENCE_DIRECTORY PRESENT (1 when the directory exists).
# Records the operation: its coherent answer, NOT_RUN when nothing was left, or a
# refusal. Never writes.
_cbs_flutter_qual_rp_collect() {
    local operation="$1"
    local directory="$2"
    local present="$3"
    local file="$directory/$operation.result"

    if [[ "$present" != "1" ]]; then
        _cbs_flutter_qual_rp_set_reason "$operation" "NOT_EXECUTED" "ABSENT"
        return 0
    fi

    if [[ -L "$file" ]]; then
        _cbs_flutter_qual_rp_set_reason "$operation" "PATH_NOT_ALLOWED" "REJECTED"
        return 0
    fi

    if ! _cbs_flutter_qual_rp_present "$file"; then
        # A trace of a started run without its answer is not "never run".
        if _cbs_flutter_qual_rp_present "$directory/$operation.log" ||
            _cbs_flutter_qual_rp_present "$directory/$operation.log.partial"; then
            _cbs_flutter_qual_rp_set_reason "$operation" "INPUT_INVALID" "REJECTED"
        else
            _cbs_flutter_qual_rp_set_reason "$operation" "NOT_EXECUTED" "ABSENT"
        fi

        return 0
    fi

    if ! _cbs_flutter_qual_rp_file_is_private "$file"; then
        _cbs_flutter_qual_rp_set_reason "$operation" "PATH_NOT_ALLOWED" "REJECTED"
        return 0
    fi

    if ! _cbs_flutter_qual_rp_read_result "$operation" "$file"; then
        _cbs_flutter_qual_rp_set_reason "$operation" "INPUT_INVALID" "REJECTED"
    fi

    return 0
}

# --- Structured output ---------------------------------------------------------

# Arguments: REASON [KEY]. The answer of a refusal of the whole report: only the
# answer of REPORT, no operation is consolidated. Returns the contract code.
_cbs_flutter_qual_rp_refuse() {
    local reason="$1"
    local key="${2:-}"
    local result
    local operation_lines
    local result_lines

    result="$(cbs_flutter_qual_result_for_reason "$reason")" || result=""

    if [[ "$result" != "BLOCKED" ]] ||
        ! operation_lines="$(cbs_flutter_qual_emit_operation "REPORT" "$result" "$reason" 2>/dev/null)" ||
        ! result_lines="$(cbs_flutter_qual_emit_result "$result" "$reason" 2>/dev/null)"; then
        echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
        return "$CBS_RC_FLUTTER_QUAL_USAGE"
    fi

    if [[ -n "$key" ]] && cbs_flutter_qual_key_valid "$key"; then
        printf 'CBS_FLUTTER_QUAL_REPORT_REJECTED_KEY=%s\n' "$key"
    fi

    if [[ -n "$RP_QUALIFICATION_ID" ]] && cbs_flutter_qual_id_valid "$RP_QUALIFICATION_ID"; then
        printf 'CBS_FLUTTER_QUAL_REPORT_QUALIFICATION_ID=%s\n' "$RP_QUALIFICATION_ID"
    fi

    printf '%s\n' "$operation_lines"
    printf '%s\n' "$result_lines"
    printf 'CBS_FLUTTER_QUAL_ERROR=%s\n' "$reason" >&2

    return "$(cbs_flutter_qual_rc_for_reason "$reason")"
}

# Consolidates, prints the summary and the structured answer. Returns the
# contract code of the consolidated reason (0 for PASS).
_cbs_flutter_qual_rp_conclude() {
    local operation
    local results=""
    local overall
    local overall_reason=""
    local operation_lines
    local result_lines
    local body
    local value

    for operation in $CBS_FLUTTER_QUAL_REPORT_OPERATIONS; do
        results="$results $(_cbs_flutter_qual_rp_get R "$operation")"
    done

    # No result of the list is ever converted: FAIL, then BLOCKED, then NOT_RUN
    # win over PASS; SKIPPED alone is not a PASS.
    # shellcheck disable=SC2086
    if ! overall="$(cbs_flutter_qual_aggregate $results)"; then
        _cbs_flutter_qual_rp_refuse "INPUT_INVALID" ""
        return $?
    fi

    if [[ "$overall" != "PASS" ]]; then
        for operation in $CBS_FLUTTER_QUAL_REPORT_OPERATIONS; do
            [[ "$(_cbs_flutter_qual_rp_get R "$operation")" == "$overall" ]] || continue

            overall_reason="$(_cbs_flutter_qual_rp_get X "$operation")"
            break
        done

        # Nothing but SKIPPED: nothing was observed.
        if [[ -z "$overall_reason" ]] ||
            ! cbs_flutter_qual_result_reason_consistent "$overall" "$overall_reason"; then
            overall="NOT_RUN"
            overall_reason="NOT_EXECUTED"
        fi
    fi

    if ! operation_lines="$(cbs_flutter_qual_emit_operation "REPORT" "$overall" "$overall_reason" 2>/dev/null)" ||
        ! result_lines="$(cbs_flutter_qual_emit_result "$overall" "$overall_reason" 2>/dev/null)"; then
        echo "CBS_FLUTTER_QUAL_ERROR=INVALID_EMISSION" >&2
        return "$CBS_RC_FLUTTER_QUAL_USAGE"
    fi

    body="$(
        printf 'CBS_FLUTTER_QUAL_REPORT_QUALIFICATION_ID=%s\n' "$RP_QUALIFICATION_ID"
        printf 'CBS_FLUTTER_QUAL_REPORT_COMMIT_EXPECTED=%s\n' "$RP_COMMIT_EXPECTED"

        if [[ -n "$RP_COMMIT_OBSERVED" ]]; then
            printf 'CBS_FLUTTER_QUAL_REPORT_COMMIT_OBSERVED=%s\n' "$RP_COMMIT_OBSERVED"
        fi

        for operation in $CBS_FLUTTER_QUAL_REPORT_OPERATIONS; do
            printf 'CBS_FLUTTER_QUAL_REPORT_%s_RESULT=%s\n' "$operation" "$(_cbs_flutter_qual_rp_get R "$operation")"

            value="$(_cbs_flutter_qual_rp_get X "$operation")"
            if [[ -n "$value" ]]; then
                printf 'CBS_FLUTTER_QUAL_REPORT_%s_REASON=%s\n' "$operation" "$value"
            fi

            printf 'CBS_FLUTTER_QUAL_REPORT_%s_RC=%s\n' "$operation" "$(cbs_flutter_qual_rc_for_reason "$value")"

            value="$(_cbs_flutter_qual_rp_get T "$operation")"
            if [[ -n "$value" ]]; then
                printf 'CBS_FLUTTER_QUAL_REPORT_%s_TOOL_RC=%s\n' "$operation" "$value"
            fi

            printf 'CBS_FLUTTER_QUAL_REPORT_%s_EVIDENCE=%s\n' "$operation" "$(_cbs_flutter_qual_rp_get E "$operation")"
        done

        printf '%s\n' "$operation_lines"
        printf '%s\n' "$result_lines"
    )"

    printf '%s\n' "$body"

    if [[ -n "$overall_reason" ]]; then
        printf 'CBS_FLUTTER_QUAL_ERROR=%s\n' "$overall_reason" >&2
    fi

    return "$(cbs_flutter_qual_rc_for_reason "$overall_reason")"
}

# --- Entry ---------------------------------------------------------------------

# Arguments: KEY=VALUE... (the request).
cbs_flutter_qual_report() {
    local reason
    local actions
    local action
    local operation
    local evidence_root
    local directory
    local present="0"
    local derived="0"

    _cbs_flutter_qual_rp_reset

    # ---- 1. request

    if [[ "$#" -eq 0 ]]; then
        _cbs_flutter_qual_rp_refuse "USAGE" ""
        return $?
    fi

    if ! cbs_flutter_qual_validate_request "$@"; then
        reason="$CBS_FLUTTER_QUAL_VALIDATION_REASON"
        cbs_flutter_qual_reason_is_valid "$reason" || reason="INPUT_INVALID"

        _cbs_flutter_qual_rp_refuse "$reason" "$CBS_FLUTTER_QUAL_VALIDATION_KEY"
        return $?
    fi

    actions="$(cbs_flutter_qual_entries_get actions "$@")"

    # This operation is the REPORT: it must have been selected.
    case ",$actions," in
        *,report,*) ;;
        *)
            _cbs_flutter_qual_rp_refuse "ACTION_NOT_ALLOWED" "actions"
            return $?
            ;;
    esac

    RP_QUALIFICATION_ID="$(cbs_flutter_qual_entries_get qualification_id "$@")"
    RP_COMMIT_EXPECTED="$(cbs_flutter_qual_entries_get commit "$@")"
    evidence_root="$(cbs_flutter_qual_entries_get evidence_root "$@")"

    # ---- 2. evidence location (read-only, never a link)

    if ! _cbs_flutter_qual_rp_dir_is_private "$evidence_root"; then
        _cbs_flutter_qual_rp_refuse "PATH_NOT_ALLOWED" "evidence_root"
        return $?
    fi

    directory="$evidence_root/$RP_QUALIFICATION_ID"

    if _cbs_flutter_qual_rp_present "$directory"; then
        if ! _cbs_flutter_qual_rp_dir_is_private "$directory"; then
            _cbs_flutter_qual_rp_refuse "PATH_NOT_ALLOWED" "qualification_id"
            return $?
        fi

        present="1"
    fi

    # ---- 3. the selected operations, in contract order

    for operation in $CBS_FLUTTER_QUAL_REPORT_OPERATIONS; do
        action="$(cbs_flutter_qual_action_for_operation "$operation")" || continue

        case ",$actions," in
            *",$action,"*) ;;
            *) continue ;;
        esac

        # PREFLIGHT leaves no file of its own: derived below.
        [[ "$operation" != "PREFLIGHT" ]] || continue

        _cbs_flutter_qual_rp_collect "$operation" "$directory" "$present"
    done

    # ---- 4. PREFLIGHT, from what the other operations recorded of it

    case ",$actions," in
        *,preflight,*)
            for operation in $CBS_FLUTTER_QUAL_REPORT_EVIDENCE_OPERATIONS; do
                if [[ "$(_cbs_flutter_qual_rp_get E "$operation")" == "READ" ]]; then
                    derived="1"
                fi
            done

            if [[ "$derived" == "1" ]]; then
                _cbs_flutter_qual_rp_set "PREFLIGHT" "PASS" "" "" "DERIVED"
                RP_COMMIT_OBSERVED="$RP_COMMIT_EXPECTED"
            else
                _cbs_flutter_qual_rp_set_reason "PREFLIGHT" "NOT_EXECUTED" "ABSENT"
            fi
            ;;
    esac

    # ---- 5. consolidation

    _cbs_flutter_qual_rp_conclude
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -u
    CBS_FLUTTER_QUAL_REPORT_RC=0
    cbs_flutter_qual_report "$@" || CBS_FLUTTER_QUAL_REPORT_RC=$?
    exit "$CBS_FLUTTER_QUAL_REPORT_RC"
fi
