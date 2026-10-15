#!/usr/bin/env bash

# D04b-C.2c - Flutter qualification: preparation of the local "path:"
# dependencies of an isolated consumer.
#
#   dependencies.sh prepare <consumer-id> <consumer-source> <isolation-root> \
#                           <name> <source> <expected-origin> <commit> [<name> <source> <expected-origin> <commit>]...
#   dependencies.sh verify  (same arguments, read-only)
#   dependencies.sh cleanup <isolation-root> <name> <source> [<name> <source>]...
#
# Problem. A Flutter consumer may declare
#
#     cbs_flutter_ux:
#       path: ../cbs-environment-framework/packages/cbs_flutter_ux
#
# In the isolated checkout <isolation-root>/<consumer-id> that relative path
# resolves to <isolation-root>/cbs-environment-framework/packages/cbs_flutter_ux,
# a sibling of the checkout, which does not exist: "flutter pub get" fails.
#
# What this file does, and only this:
#   - verifies the consumer isolation (isolation manager "verify", read-only):
#     the manifest read is the one of an owned, clean, detached checkout of the
#     exact commit;
#   - reads the tracked pubspec.yaml of that checkout and lists the "path:"
#     dependencies it declares (dependencies, dev_dependencies,
#     dependency_overrides). A path inside the checkout needs nothing. A path
#     that resolves under <isolation-root>/<name>/... needs the repository
#     <name> to be materialized there. Anything else is refused;
#   - requires one explicit mapping <name> -> (source repository, expected
#     origin, full commit) per needed repository, and refuses a mapping that
#     nothing needs: nothing is guessed, nothing unneeded is materialized;
#   - materializes each repository with the existing isolation manager
#     (D04b-C.1, unchanged): detached worktree at the explicit commit, directly
#     at <isolation-root>/<name>, with its CBS ownership proof. No symbolic
#     link, no copy, no second mechanism;
#   - verifies, through the manager again, the provenance (proof, origin,
#     commit), a detached and clean HEAD, and that every declared package is a
#     canonical directory holding a pubspec.yaml.
#
# Idempotence. A repository already present is accepted only when the manager
# verifies it as CBS-owned, at the same commit and origin, detached and clean
# (state REUSED). Anything else already present is a conflict (BLOCKED) and is
# left exactly as found. Every conflict is detected before the first creation.
#
# Cleanup. Only through the manager "cleanup" (non-forced "git worktree
# remove" of a worktree it created, proof and Git association checked). Every
# requested resource is verified first: nothing is removed unless all of them
# are owned and clean. A directory without CBS proof, a modified worktree, an
# unknown identifier are refused and never touched. The consumer isolation is
# cleaned by the operator beforehand, with the manager.
#
# What this file never does: modify a source repository (the manager only adds
# or removes the Git administrative entry of the worktree it manages, as for the
# consumer isolation), run Flutter, Dart or pub, use the network, create a
# symbolic link, delete recursively, reset or clean, source or evaluate any
# value. All arguments and the manifest are data. Output contains closed values
# only (no path of the host, no free text).
#
# Compatible with Bash 3.2 (macOS) and later: no associative array, no case
# conversion expansion, no here-string, no GNU-only option; BSD tools only
# (awk without interval expressions, wc, tr).

unset CDPATH

# Loaded fresh from this repository (a guard coming from the environment would
# skip the contracts). Readonly when a caller already loaded them: harmless.
unset CBS_FLUTTER_QUAL_CONTRACT_LOADED CBS_ISOLATION_CONTRACT_LOADED CBS_WORKTREE_CONTRACT_LOADED 2>/dev/null || true

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
unset GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_PREFIX
unset GIT_CONFIG_PARAMETERS
unset BASH_ENV
export GIT_TERMINAL_PROMPT=0
export GIT_NO_LAZY_FETCH=1
export GIT_OPTIONAL_LOCKS=0

# Same guard as PREFLIGHT: the manager runs raw Git commands; the settings that
# execute code are neutralised at the highest precedence (Git >= 2.31), and the
# sentinel proves that this Git applies them.
CBS_FLUTTER_DEPS_GIT_PROBE_KEY="cbs.depsconfigcount"
CBS_FLUTTER_DEPS_GIT_PROBE_VALUE="applied-$$-$RANDOM-$RANDOM"

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
export GIT_CONFIG_KEY_2=core.untrackedCache GIT_CONFIG_VALUE_2=false
export GIT_CONFIG_KEY_3="$CBS_FLUTTER_DEPS_GIT_PROBE_KEY"
export GIT_CONFIG_VALUE_3="$CBS_FLUTTER_DEPS_GIT_PROBE_VALUE"
export LC_ALL=C

CBS_FLUTTER_DEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CBS_FLUTTER_DEPS_ROOT="$(cd "$CBS_FLUTTER_DEPS_DIR/../../.." 2>/dev/null && pwd)"

if [[ -z "$CBS_FLUTTER_DEPS_DIR" || ! -f "$CBS_FLUTTER_DEPS_DIR/contract.sh" ]]; then
    echo "CBS_FLUTTER_DEPS_ERROR=CONTRACT_UNAVAILABLE" >&2
    return 1 2>/dev/null || exit 1
fi

# shellcheck source=/dev/null
source "$CBS_FLUTTER_DEPS_DIR/contract.sh"

# Fixed location, derived from this file only (never from an argument).
CBS_FLUTTER_DEPS_MANAGER="$CBS_FLUTTER_DEPS_ROOT/cbs/worktree/isolation_manager.sh"

readonly CBS_FLUTTER_DEPS_VERSION=1
readonly CBS_FLUTTER_DEPS_MANIFEST_MAX_BYTES=262144
readonly CBS_FLUTTER_DEPS_RECORDS_MAX=64
readonly CBS_FLUTTER_DEPS_REPOSITORIES_MAX=8
readonly CBS_FLUTTER_DEPS_RELATIVE_PATH_PATTERN='^[A-Za-z0-9._+@/-]+$'
readonly CBS_FLUTTER_DEPS_RELATIVE_PATH_MAX=512
readonly CBS_FLUTTER_DEPS_PACKAGE_NAME_PATTERN='^[A-Za-z_][A-Za-z0-9_]{0,63}$'
readonly CBS_FLUTTER_DEPS_CLOSED_ID_PATTERN='^[A-Z][A-Z0-9_]{0,63}$'
readonly CBS_FLUTTER_DEPS_UINT_PATTERN='^[0-9]{1,9}$'
readonly CBS_FLUTTER_DEPS_GIT_VERSION_PATTERN='^git[[:space:]]version[[:space:]]([0-9]{1,4})\.([0-9]{1,4})'

# Reasons. BLOCKED: refused before any change. FAIL: something ran and went
# wrong. 64 is the shared usage code; 140..152 are reserved for this step and
# collide with no code of another CBS component (50-53, 60-72, 80-82, 90-94,
# 100-110, 120-137, 255).
#
# reason                      rc   result
#   USAGE                     64   BLOCKED
#   INPUT_INVALID             140  BLOCKED
#   GIT_UNSUPPORTED           141  BLOCKED
#   CONSUMER_REJECTED         142  BLOCKED
#   MANIFEST_UNSUPPORTED      143  BLOCKED
#   DEPENDENCY_UNMAPPED       144  BLOCKED
#   MAPPING_UNUSED            145  BLOCKED
#   DEPENDENCY_CONFLICT       146  BLOCKED
#   DEPENDENCY_MISSING        147  BLOCKED
#   SOURCE_REJECTED           148  BLOCKED
#   CLEANUP_REFUSED           149  BLOCKED
#   PACKAGE_INVALID           150  FAIL
#   MATERIALIZATION_FAILED    151  FAIL
#   CLEANUP_FAILED            152  FAIL
_cbs_flutter_deps_row() {
    case "${1:-}" in
        USAGE) printf '%s\n' "64 BLOCKED" ;;
        INPUT_INVALID) printf '%s\n' "140 BLOCKED" ;;
        GIT_UNSUPPORTED) printf '%s\n' "141 BLOCKED" ;;
        CONSUMER_REJECTED) printf '%s\n' "142 BLOCKED" ;;
        MANIFEST_UNSUPPORTED) printf '%s\n' "143 BLOCKED" ;;
        DEPENDENCY_UNMAPPED) printf '%s\n' "144 BLOCKED" ;;
        MAPPING_UNUSED) printf '%s\n' "145 BLOCKED" ;;
        DEPENDENCY_CONFLICT) printf '%s\n' "146 BLOCKED" ;;
        DEPENDENCY_MISSING) printf '%s\n' "147 BLOCKED" ;;
        SOURCE_REJECTED) printf '%s\n' "148 BLOCKED" ;;
        CLEANUP_REFUSED) printf '%s\n' "149 BLOCKED" ;;
        PACKAGE_INVALID) printf '%s\n' "150 FAIL" ;;
        MATERIALIZATION_FAILED) printf '%s\n' "151 FAIL" ;;
        CLEANUP_FAILED) printf '%s\n' "152 FAIL" ;;
        *) return 1 ;;
    esac
}

CBS_FLUTTER_DEPS_NL="
"
CBS_FLUTTER_DEPS_TAB="	"

# The manifest reader (POSIX awk, no interval expression: BSD awk of macOS).
# It prints one "section<TAB>name<TAB>path" record per local path dependency of
# the three dependency sections, and "!<TAB><TAB>!UNSUPPORTED" for a form it
# cannot read safely (flow-style section, tab indentation). A "path:" nested
# deeper than the keys of the dependency (the "path" of a "git:" source) is not
# a local path and is ignored; so is an inline map that names git, sdk or
# hosted.
CBS_FLUTTER_DEPS_AWK='
function indent_of(s,   n) { n = match(s, /[^ ]/); return n ? n - 1 : -1 }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function strip_comment(s) {
    if (index(s, "\"") == 0 && index(s, q) == 0) { sub(/[ \t]+#.*$/, "", s); sub(/^#.*$/, "", s) }
    return s
}
function unquote(s) {
    if (length(s) >= 2) {
        if ((substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") || (substr(s, 1, 1) == q && substr(s, length(s), 1) == q)) {
            s = substr(s, 2, length(s) - 2)
        }
    }
    return s
}
BEGIN { q = "\047"; section = ""; dep = ""; depind = -1; child = -1 }
{
    line = $0
    sub(/\r$/, "", line)
    if (line ~ /^[ ]*(#.*)?$/) next
    if (line ~ /^\t/) { print "!\t\t!UNSUPPORTED"; next }
    ind = indent_of(line)
    if (ind == 0) {
        key = line; sub(/:.*$/, "", key); key = trim(key)
        if (key == "dependencies" || key == "dev_dependencies" || key == "dependency_overrides") {
            section = key
            rest = line; sub(/^[^:]*:/, "", rest); rest = trim(strip_comment(rest))
            if (rest != "") print "!\t\t!UNSUPPORTED"
        } else {
            section = ""
        }
        dep = ""; depind = -1; child = -1
        next
    }
    if (section == "") next
    if (depind < 0) depind = ind
    text = trim(line)
    if (ind == depind) {
        name = text; sub(/:.*$/, "", name); name = trim(name)
        rest = text; sub(/^[^:]*:/, "", rest); rest = trim(strip_comment(rest))
        dep = name; child = -1
        if (substr(rest, 1, 1) == "{") {
            if (rest ~ /(git|sdk|hosted)[ ]*:/) next
            if (rest ~ /path[ ]*:/) {
                val = rest; sub(/^.*path[ ]*:[ ]*/, "", val); sub(/[,}].*$/, "", val)
                print section "\t" dep "\t" unquote(trim(val))
            }
        }
        next
    }
    if (ind > depind && dep != "") {
        if (child < 0) child = ind
        if (ind == child && text ~ /^path[ ]*:/) {
            val = text; sub(/^path[ ]*:/, "", val)
            print section "\t" dep "\t" unquote(trim(strip_comment(trim(val))))
        }
    }
}
'

# --- State ---------------------------------------------------------------------

_cbs_flutter_deps_reset() {
    DEPS_OPERATION=""
    DEPS_RESULT="BLOCKED"
    DEPS_REASON="USAGE"
    DEPS_DETAIL=""
    DEPS_CONSUMER_ID=""
    DEPS_CONSUMER_COMMIT=""
    DEPS_EXTERNAL_COUNT=""
    DEPS_INTERNAL_COUNT=""
    DEPS_COUNT=0
    D_NAME=()
    D_SOURCE=()
    D_ORIGIN=()
    D_COMMIT=()
    D_SUBS=()
    D_STATE=()
    D_OBSERVED=()
    D_PACKAGE=()
    DEPS_RECORDS=""
    DEPS_NEEDED=""
    DEPS_LINE=""
    DEPS_TAIL=""
    DEPS_TARGET=""
    DEPS_ISO_RESULT=""
    DEPS_ISO_REASON=""
    DEPS_ISO_RC=""
    DEPS_ISO_VERSION=""
    DEPS_ISO_EXPECTED=""
    DEPS_ISO_OBSERVED=""
    DEPS_ISO_ORIGIN=""
    DEPS_ISO_PROC_RC=""
}

# Arguments: REASON [DETAIL]. The result is the class of the reason.
_cbs_flutter_deps_set() {
    local row

    row="$(_cbs_flutter_deps_row "$1")" || row="64 BLOCKED"

    DEPS_REASON="$1"
    DEPS_RESULT="${row#* }"
    DEPS_DETAIL=""

    # A detail is a closed identifier, never free text.
    if [[ "${2:-}" =~ $CBS_FLUTTER_DEPS_CLOSED_ID_PATTERN ]]; then
        DEPS_DETAIL="$2"
    fi
}

_cbs_flutter_deps_pass() {
    DEPS_RESULT="PASS"
    DEPS_REASON="NONE"
    DEPS_DETAIL=""
}

# Arguments: TEXT. Sets DEPS_LINE (first line) and DEPS_TAIL (the rest).
_cbs_flutter_deps_pop() {
    local text="$1"

    if [[ "$text" == *"$CBS_FLUTTER_DEPS_NL"* ]]; then
        DEPS_LINE="${text%%"$CBS_FLUTTER_DEPS_NL"*}"
        DEPS_TAIL="${text#*"$CBS_FLUTTER_DEPS_NL"}"
    else
        DEPS_LINE="$text"
        DEPS_TAIL=""
    fi
}

# Git, without repository hooks or file system monitor.
_cbs_flutter_deps_git() {
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"
}

# --- Structured output ---------------------------------------------------------

# Arguments: NAME VALUE PATTERN. A value that does not match is not printed.
_cbs_flutter_deps_fact() {
    [[ -n "$2" && "$2" =~ $3 ]] || return 0

    printf 'CBS_FLUTTER_DEPS_%s=%s\n' "$1" "$2"
}

_cbs_flutter_deps_conclude() {
    local index
    local row
    local rc
    local word='^[A-Za-z0-9._-]{1,64}$'
    local state='^(CREATED|REUSED|PRESENT|MISSING|CONFLICT|REMOVED|NOT_RUN)$'

    row="$(_cbs_flutter_deps_row "$DEPS_REASON")" || row=""

    if [[ "$DEPS_RESULT" == "PASS" ]]; then
        rc=0
    else
        rc="${row%% *}"
        [[ -n "$rc" ]] || rc=64
    fi

    printf 'CBS_FLUTTER_DEPS_VERSION=%s\n' "$CBS_FLUTTER_DEPS_VERSION"
    _cbs_flutter_deps_fact OPERATION "$DEPS_OPERATION" '^(PREPARE|VERIFY|CLEANUP)$'
    _cbs_flutter_deps_fact CONSUMER_ID "$DEPS_CONSUMER_ID" "$word"

    if [[ -n "$DEPS_CONSUMER_COMMIT" ]] && cbs_flutter_qual_commit_valid "$DEPS_CONSUMER_COMMIT"; then
        printf 'CBS_FLUTTER_DEPS_CONSUMER_COMMIT=%s\n' "$DEPS_CONSUMER_COMMIT"
    fi

    _cbs_flutter_deps_fact EXTERNAL_COUNT "$DEPS_EXTERNAL_COUNT" '^[0-9]{1,4}$'
    _cbs_flutter_deps_fact INTERNAL_COUNT "$DEPS_INTERNAL_COUNT" '^[0-9]{1,4}$'
    printf 'CBS_FLUTTER_DEPS_DEPENDENCY_COUNT=%s\n' "$DEPS_COUNT"

    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        _cbs_flutter_deps_fact "DEPENDENCY_$((index + 1))_NAME" "${D_NAME[$index]}" "$word"
        _cbs_flutter_deps_fact "DEPENDENCY_$((index + 1))_STATE" "${D_STATE[$index]}" "$state"

        if [[ -n "${D_COMMIT[$index]:-}" ]] && cbs_flutter_qual_commit_valid "${D_COMMIT[$index]}"; then
            printf 'CBS_FLUTTER_DEPS_DEPENDENCY_%s_COMMIT_EXPECTED=%s\n' "$((index + 1))" "${D_COMMIT[$index]}"
        fi

        if [[ -n "${D_OBSERVED[$index]:-}" ]] && cbs_flutter_qual_commit_valid "${D_OBSERVED[$index]}"; then
            printf 'CBS_FLUTTER_DEPS_DEPENDENCY_%s_COMMIT_OBSERVED=%s\n' "$((index + 1))" "${D_OBSERVED[$index]}"
        fi

        _cbs_flutter_deps_fact "DEPENDENCY_$((index + 1))_PACKAGE" "${D_PACKAGE[$index]:-}" '^(OK|INVALID|NOT_RUN)$'
        index=$((index + 1))
    done

    printf 'CBS_FLUTTER_DEPS_REASON=%s\n' "$DEPS_REASON"
    _cbs_flutter_deps_fact DETAIL "$DEPS_DETAIL" '^[A-Z][A-Z0-9_]{0,63}$'
    printf 'CBS_FLUTTER_DEPS_RC=%s\n' "$rc"
    printf 'CBS_FLUTTER_DEPS_RESULT=%s\n' "$DEPS_RESULT"

    if [[ "$DEPS_RESULT" != "PASS" ]]; then
        printf 'CBS_FLUTTER_DEPS_ERROR=%s\n' "$DEPS_REASON" >&2
    fi

    return "$rc"
}

# --- Isolation manager -----------------------------------------------------------

# Arguments: MANAGER_ARGUMENT... Runs the manager and keeps only the keys read
# below (first occurrence wins, nothing is evaluated).
_cbs_flutter_deps_manager() {
    local out
    local rc=0
    local rest
    local line
    local key
    local value

    DEPS_ISO_RESULT=""
    DEPS_ISO_REASON=""
    DEPS_ISO_RC=""
    DEPS_ISO_VERSION=""
    DEPS_ISO_EXPECTED=""
    DEPS_ISO_OBSERVED=""
    DEPS_ISO_ORIGIN=""

    if [[ ! -f "$CBS_FLUTTER_DEPS_MANAGER" ]]; then
        DEPS_ISO_PROC_RC=255
        DEPS_ISO_REASON="MANAGER_UNAVAILABLE"
        return 1
    fi

    out="$("${BASH:-bash}" "$CBS_FLUTTER_DEPS_MANAGER" "$@" </dev/null 2>/dev/null)" || rc=$?
    DEPS_ISO_PROC_RC="$rc"

    rest="$out"

    while [[ -n "$rest" ]]; do
        _cbs_flutter_deps_pop "$rest"
        line="$DEPS_LINE"
        rest="$DEPS_TAIL"

        case "$line" in
            CBS_FLUTTER_ISOLATION_*=*) ;;
            *) continue ;;
        esac

        key="${line%%=*}"
        value="${line#*=}"

        case "$key" in
            CBS_FLUTTER_ISOLATION_VERSION) [[ -n "$DEPS_ISO_VERSION" ]] || DEPS_ISO_VERSION="$value" ;;
            CBS_FLUTTER_ISOLATION_RESULT) [[ -n "$DEPS_ISO_RESULT" ]] || DEPS_ISO_RESULT="$value" ;;
            CBS_FLUTTER_ISOLATION_REASON) [[ -n "$DEPS_ISO_REASON" ]] || DEPS_ISO_REASON="$value" ;;
            CBS_FLUTTER_ISOLATION_RC) [[ -n "$DEPS_ISO_RC" ]] || DEPS_ISO_RC="$value" ;;
            CBS_FLUTTER_ISOLATION_COMMIT_EXPECTED) [[ -n "$DEPS_ISO_EXPECTED" ]] || DEPS_ISO_EXPECTED="$value" ;;
            CBS_FLUTTER_ISOLATION_COMMIT_OBSERVED) [[ -n "$DEPS_ISO_OBSERVED" ]] || DEPS_ISO_OBSERVED="$value" ;;
            CBS_FLUTTER_ISOLATION_ORIGIN) [[ -n "$DEPS_ISO_ORIGIN" ]] || DEPS_ISO_ORIGIN="$value" ;;
        esac
    done

    return 0
}

# Succeeds only when the whole answer of the manager is a coherent PASS.
_cbs_flutter_deps_manager_passed() {
    [[ "$DEPS_ISO_PROC_RC" == "0" && "$DEPS_ISO_RESULT" == "PASS" && "$DEPS_ISO_RC" == "0" &&
        "$DEPS_ISO_REASON" == "NONE" && "$DEPS_ISO_VERSION" == "$CBS_ISOLATION_CONTRACT_VERSION" ]]
}

# The reason of the manager, as a detail (closed identifier or nothing).
_cbs_flutter_deps_manager_detail() {
    if [[ "$DEPS_ISO_REASON" =~ $CBS_FLUTTER_DEPS_CLOSED_ID_PATTERN && "$DEPS_ISO_REASON" != "NONE" ]]; then
        printf '%s' "$DEPS_ISO_REASON"
    fi
}

# --- Git guard -------------------------------------------------------------------

# Accepts the Git only when it really applies GIT_CONFIG_COUNT (>= 2.31).
_cbs_flutter_deps_check_git() {
    local version
    local major
    local minor
    local value

    version="$(git --version 2>/dev/null)" || return 1

    [[ "$version" =~ $CBS_FLUTTER_DEPS_GIT_VERSION_PATTERN ]] || return 1
    major="$((10#${BASH_REMATCH[1]}))"
    minor="$((10#${BASH_REMATCH[2]}))"

    if [[ "$major" -lt 2 || ( "$major" -eq 2 && "$minor" -lt 31 ) ]]; then
        return 1
    fi

    value="$(git config --get "$CBS_FLUTTER_DEPS_GIT_PROBE_KEY" 2>/dev/null)" || return 1
    [[ "$value" == "$CBS_FLUTTER_DEPS_GIT_PROBE_VALUE" ]]
}

# --- Paths ---------------------------------------------------------------------

# Arguments: BASE RELATIVE. BASE is an absolute canonical directory, RELATIVE
# the text of a "path:". Sets DEPS_TARGET to the lexically normalized absolute
# path. Fails (nothing set) on an absolute path, an unexpected character, an
# empty component or a path that climbs above the filesystem root. One trailing
# slash is accepted.
_cbs_flutter_deps_target() {
    local base="$1"
    local relative="$2"
    local result="$base"
    local rest
    local component

    DEPS_TARGET=""

    [[ -n "$relative" ]] || return 1
    [[ "${#relative}" -le "$CBS_FLUTTER_DEPS_RELATIVE_PATH_MAX" ]] || return 1
    [[ "$relative" =~ $CBS_FLUTTER_DEPS_RELATIVE_PATH_PATTERN ]] || return 1

    case "$relative" in
        /*) return 1 ;;
        */) relative="${relative%/}" ;;
    esac

    case "$relative" in
        *//*|"") return 1 ;;
    esac

    rest="$relative"

    while [[ -n "$rest" ]]; do
        component="${rest%%/*}"

        if [[ "$rest" == */* ]]; then
            rest="${rest#*/}"
        else
            rest=""
        fi

        case "$component" in
            .)
                ;;
            ..)
                [[ "$result" != "/" ]] || return 1
                result="${result%/*}"
                [[ -n "$result" ]] || result="/"
                ;;
            *)
                if [[ "$result" == "/" ]]; then
                    result="/$component"
                else
                    result="$result/$component"
                fi
                ;;
        esac
    done

    DEPS_TARGET="$result"
}

# --- Manifest --------------------------------------------------------------------

# Arguments: FILE. Sets DEPS_RECORDS. Fails when the file is not a plain
# readable file of a bounded size, or when it holds a form that cannot be read.
_cbs_flutter_deps_scan() {
    local file="$1"
    local size
    local count

    DEPS_RECORDS=""

    [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1

    size="$(wc -c < "$file" 2>/dev/null | tr -d ' ')" || return 1
    [[ "$size" =~ $CBS_FLUTTER_DEPS_UINT_PATTERN ]] || return 1
    [[ "$((10#$size))" -le "$CBS_FLUTTER_DEPS_MANIFEST_MAX_BYTES" ]] || return 1

    DEPS_RECORDS="$(LC_ALL=C awk "$CBS_FLUTTER_DEPS_AWK" "$file" 2>/dev/null)" || return 1

    case "$DEPS_RECORDS" in
        *'!'*UNSUPPORTED*) return 1 ;;
    esac

    if [[ -n "$DEPS_RECORDS" ]]; then
        count="$(printf '%s\n' "$DEPS_RECORDS" | wc -l | tr -d ' ')"
        [[ "$count" =~ $CBS_FLUTTER_DEPS_UINT_PATTERN && "$((10#$count))" -le "$CBS_FLUTTER_DEPS_RECORDS_MAX" ]] || return 1
    fi

    return 0
}

# Arguments: CHECKOUT ROOT. Classifies the records of the consumer manifest
# (DEPS_RECORDS). Sets DEPS_NEEDED (one "name<TAB>subpath" line per external
# declaration, "." when the package is the repository itself),
# DEPS_INTERNAL_COUNT and DEPS_EXTERNAL_COUNT. Returns 0, 1 (unsupported form,
# path outside the isolation root) or 2 (an internal path that does not exist).
_cbs_flutter_deps_classify() {
    local checkout="$1"
    local root="$2"
    local rest="$DEPS_RECORDS"
    local line
    local name
    local value
    local tail
    local repository
    local subpath
    local internal=0
    local external=0

    DEPS_NEEDED=""

    while [[ -n "$rest" ]]; do
        _cbs_flutter_deps_pop "$rest"
        line="$DEPS_LINE"
        rest="$DEPS_TAIL"

        tail="${line#*"$CBS_FLUTTER_DEPS_TAB"}"
        name="${tail%%"$CBS_FLUTTER_DEPS_TAB"*}"
        value="${tail#*"$CBS_FLUTTER_DEPS_TAB"}"

        [[ "$name" =~ $CBS_FLUTTER_DEPS_PACKAGE_NAME_PATTERN ]] || return 1
        _cbs_flutter_deps_target "$checkout" "$value" || return 1

        if [[ "$DEPS_TARGET" == "$checkout" || "$DEPS_TARGET" == "$checkout"/* ]]; then
            [[ -d "$DEPS_TARGET" && ! -L "$DEPS_TARGET" ]] || return 2
            internal=$((internal + 1))
            continue
        fi

        [[ "$DEPS_TARGET" == "$root"/* ]] || return 1

        tail="${DEPS_TARGET#"$root"/}"
        repository="${tail%%/*}"

        if [[ "$tail" == */* ]]; then
            subpath="${tail#*/}"
        else
            subpath="."
        fi

        cbs_flutter_qual_id_valid "$repository" || return 1

        case "$CBS_FLUTTER_DEPS_NL$DEPS_NEEDED$CBS_FLUTTER_DEPS_NL" in
            *"$CBS_FLUTTER_DEPS_NL$repository$CBS_FLUTTER_DEPS_TAB$subpath$CBS_FLUTTER_DEPS_NL"*) ;;
            *)
                if [[ -n "$DEPS_NEEDED" ]]; then
                    DEPS_NEEDED="$DEPS_NEEDED$CBS_FLUTTER_DEPS_NL$repository$CBS_FLUTTER_DEPS_TAB$subpath"
                else
                    DEPS_NEEDED="$repository$CBS_FLUTTER_DEPS_TAB$subpath"
                fi
                ;;
        esac

        external=$((external + 1))
    done

    DEPS_INTERNAL_COUNT="$internal"
    DEPS_EXTERNAL_COUNT="$external"
    return 0
}

# Arguments: NAME. Prints the subpaths needed from that repository, one per line.
_cbs_flutter_deps_subpaths_of() {
    local wanted="$1"
    local rest="$DEPS_NEEDED"
    local line
    local seen=""

    while [[ -n "$rest" ]]; do
        _cbs_flutter_deps_pop "$rest"
        line="$DEPS_LINE"
        rest="$DEPS_TAIL"

        if [[ "${line%%"$CBS_FLUTTER_DEPS_TAB"*}" == "$wanted" ]]; then
            if [[ -n "$seen" ]]; then
                seen="$seen$CBS_FLUTTER_DEPS_NL${line#*"$CBS_FLUTTER_DEPS_TAB"}"
            else
                seen="${line#*"$CBS_FLUTTER_DEPS_TAB"}"
            fi
        fi
    done

    printf '%s' "$seen"
}

# Arguments: NAME. Succeeds when a needed declaration names that repository.
_cbs_flutter_deps_is_needed() {
    local wanted="$1"
    local rest="$DEPS_NEEDED"
    local line

    while [[ -n "$rest" ]]; do
        _cbs_flutter_deps_pop "$rest"
        line="$DEPS_LINE"
        rest="$DEPS_TAIL"

        [[ "${line%%"$CBS_FLUTTER_DEPS_TAB"*}" == "$wanted" ]] && return 0
    done

    return 1
}

# --- Argument validation -------------------------------------------------------

# Arguments: ROOT. A canonical directory, valid as an authorized path.
_cbs_flutter_deps_check_root() {
    cbs_flutter_qual_validate_param isolation_root "$1" >/dev/null 2>&1 || return 1
    cbs_flutter_qual_dir_is_canonical "$1"
}

# Arguments: NAME SOURCE ORIGIN COMMIT. Registers one repository mapping.
_cbs_flutter_deps_add_mapping() {
    local name="$1"
    local source="$2"
    local origin="$3"
    local commit="$4"
    local index=0

    cbs_flutter_qual_id_valid "$name" || return 1
    cbs_flutter_qual_validate_param source_repository "$source" >/dev/null 2>&1 || return 1

    if [[ -n "$origin" ]]; then
        cbs_flutter_qual_validate_param expected_origin "$origin" >/dev/null 2>&1 || return 1
    fi

    if [[ -n "$commit" ]]; then
        cbs_flutter_qual_validate_param commit "$commit" >/dev/null 2>&1 || return 1
    fi

    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        [[ "${D_NAME[$index]}" != "$name" ]] || return 1
        index=$((index + 1))
    done

    [[ "$DEPS_COUNT" -lt "$CBS_FLUTTER_DEPS_REPOSITORIES_MAX" ]] || return 1

    D_NAME[$DEPS_COUNT]="$name"
    D_SOURCE[$DEPS_COUNT]="$source"
    D_ORIGIN[$DEPS_COUNT]="$origin"
    D_COMMIT[$DEPS_COUNT]="$commit"
    D_SUBS[$DEPS_COUNT]=""
    D_STATE[$DEPS_COUNT]="NOT_RUN"
    D_OBSERVED[$DEPS_COUNT]=""
    D_PACKAGE[$DEPS_COUNT]="NOT_RUN"
    DEPS_COUNT=$((DEPS_COUNT + 1))
}

# --- Source and package checks -------------------------------------------------

# Arguments: SOURCE COMMIT SUBPATH. Read-only: the commit exists locally and
# holds a regular pubspec.yaml at that package path (not a symbolic link, none
# of its directories a link).
_cbs_flutter_deps_source_has_package() {
    local source="$1"
    local commit="$2"
    local subpath="$3"
    local path="pubspec.yaml"
    local entry

    _cbs_flutter_deps_git -C "$source" cat-file -e "$commit^{commit}" >/dev/null 2>&1 || return 1

    [[ "$subpath" == "." ]] || path="$subpath/pubspec.yaml"

    entry="$(_cbs_flutter_deps_git -C "$source" ls-tree "$commit" -- "$path" 2>/dev/null)" || return 1

    case "$entry" in
        "100644 blob "*|"100755 blob "*) return 0 ;;
    esac

    return 1
}

# Arguments: ROOT NAME SUBPATH. The package directory of the worktree is a
# canonical directory (no link in any component) holding a plain pubspec.yaml.
_cbs_flutter_deps_package_ok() {
    local directory="$1/$2"

    [[ "$3" == "." ]] || directory="$directory/$3"

    cbs_flutter_qual_dir_is_canonical "$directory" || return 1
    [[ -f "$directory/pubspec.yaml" && ! -L "$directory/pubspec.yaml" ]]
}

# Arguments: ROOT CHECKOUT PACKAGE_DIRECTORY. The path dependencies of a
# materialized package must resolve inside the consumer checkout or inside a
# repository of this preparation, and exist. Nothing is materialized for them.
_cbs_flutter_deps_package_manifest_ok() {
    local root="$1"
    local checkout="$2"
    local directory="$3"
    local records
    local rest
    local line
    local tail
    local value
    local allowed
    local index
    local found

    _cbs_flutter_deps_scan "$directory/pubspec.yaml" || return 1
    records="$DEPS_RECORDS"
    rest="$records"

    while [[ -n "$rest" ]]; do
        _cbs_flutter_deps_pop "$rest"
        line="$DEPS_LINE"
        rest="$DEPS_TAIL"

        tail="${line#*"$CBS_FLUTTER_DEPS_TAB"}"
        value="${tail#*"$CBS_FLUTTER_DEPS_TAB"}"

        _cbs_flutter_deps_target "$directory" "$value" || return 1
        [[ -d "$DEPS_TARGET" && ! -L "$DEPS_TARGET" ]] || return 1

        found=0

        for allowed in "$checkout" "$root/${D_NAME[0]}"; do
            if [[ "$DEPS_TARGET" == "$allowed" || "$DEPS_TARGET" == "$allowed"/* ]]; then
                found=1
            fi
        done

        index=1
        while [[ "$index" -lt "$DEPS_COUNT" ]]; do
            allowed="$root/${D_NAME[$index]}"

            if [[ "$DEPS_TARGET" == "$allowed" || "$DEPS_TARGET" == "$allowed"/* ]]; then
                found=1
            fi

            index=$((index + 1))
        done

        [[ "$found" -eq 1 ]] || return 1
    done

    return 0
}

# --- prepare / verify ----------------------------------------------------------

# Arguments: OPERATION(prepare|verify) CONSUMER_ID CONSUMER_SOURCE ROOT
#            (NAME SOURCE ORIGIN COMMIT)...
cbs_flutter_deps_prepare() {
    local operation="$1"
    local consumer_id="$2"
    local consumer_source="$3"
    local root="$4"
    local checkout
    local manifest
    local index
    local package_dir
    local subpath
    local subs
    local rest
    local name
    local missing=0
    local classify_rc=0

    shift 4

    DEPS_CONSUMER_ID=""

    # ---- 1. arguments (data only; a refused value is never echoed)

    if [[ "$operation" == "prepare" ]]; then
        DEPS_OPERATION="PREPARE"
    else
        DEPS_OPERATION="VERIFY"
    fi

    if ! cbs_flutter_qual_id_valid "$consumer_id" ||
        ! cbs_flutter_qual_validate_param source_repository "$consumer_source" >/dev/null 2>&1 ||
        ! _cbs_flutter_deps_check_root "$root"; then
        _cbs_flutter_deps_set "INPUT_INVALID"
        return 0
    fi

    DEPS_CONSUMER_ID="$consumer_id"

    while [[ "$#" -ge 4 ]]; do
        # A repository named like the consumer would be its own checkout.
        if [[ "$1" == "$consumer_id" ]] || ! _cbs_flutter_deps_add_mapping "$1" "$2" "$3" "$4"; then
            _cbs_flutter_deps_set "INPUT_INVALID"
            return 0
        fi

        # The source and the isolation root are never the same place.
        if ! cbs_flutter_qual_paths_disjoint "$2" "$root" ||
            ! cbs_flutter_qual_paths_disjoint "$2" "$consumer_source"; then
            _cbs_flutter_deps_set "INPUT_INVALID"
            return 0
        fi

        shift 4
    done

    [[ "$#" -eq 0 ]] || { _cbs_flutter_deps_set "INPUT_INVALID"; return 0; }

    if [[ "$DEPS_COUNT" -ge 1 ]]; then
        index=0
        while [[ "$index" -lt "$DEPS_COUNT" ]]; do
            # A mapping is complete: origin and commit are explicit.
            if [[ -z "${D_ORIGIN[$index]}" || -z "${D_COMMIT[$index]}" ]]; then
                _cbs_flutter_deps_set "INPUT_INVALID"
                return 0
            fi

            index=$((index + 1))
        done
    fi

    if ! cbs_flutter_qual_paths_disjoint "$consumer_source" "$root"; then
        _cbs_flutter_deps_set "INPUT_INVALID"
        return 0
    fi

    if ! _cbs_flutter_deps_check_git; then
        _cbs_flutter_deps_set "GIT_UNSUPPORTED"
        return 0
    fi

    # ---- 2. the consumer isolation: owned, exact, detached and clean

    checkout="$root/$consumer_id"

    _cbs_flutter_deps_manager verify "$consumer_id" "$consumer_source" "$root" || true

    if ! _cbs_flutter_deps_manager_passed; then
        _cbs_flutter_deps_set "CONSUMER_REJECTED" "$(_cbs_flutter_deps_manager_detail)"
        return 0
    fi

    if cbs_flutter_qual_commit_valid "$DEPS_ISO_OBSERVED"; then
        DEPS_CONSUMER_COMMIT="$DEPS_ISO_OBSERVED"
    fi

    if [[ -L "$checkout" ]] || ! cbs_flutter_qual_dir_is_canonical "$checkout"; then
        _cbs_flutter_deps_set "CONSUMER_REJECTED" "CHECKOUT_NOT_CANONICAL"
        return 0
    fi

    # ---- 3. the manifest of that checkout

    manifest="$checkout/pubspec.yaml"

    if ! _cbs_flutter_deps_git -C "$checkout" ls-files --error-unmatch -- pubspec.yaml >/dev/null 2>&1; then
        _cbs_flutter_deps_set "MANIFEST_UNSUPPORTED" "MANIFEST_NOT_TRACKED"
        return 0
    fi

    if ! _cbs_flutter_deps_scan "$manifest"; then
        _cbs_flutter_deps_set "MANIFEST_UNSUPPORTED" "MANIFEST_NOT_READABLE"
        return 0
    fi

    _cbs_flutter_deps_classify "$checkout" "$root" || classify_rc=$?

    case "$classify_rc" in
        0) ;;
        2)
            _cbs_flutter_deps_set "PACKAGE_INVALID" "INTERNAL_PATH_MISSING"
            return 0
            ;;
        *)
            _cbs_flutter_deps_set "MANIFEST_UNSUPPORTED" "PATH_NOT_RESOLVABLE"
            return 0
            ;;
    esac

    # ---- 4. mapping: exactly what is needed, nothing guessed, nothing more

    rest="$DEPS_NEEDED"

    while [[ -n "$rest" ]]; do
        _cbs_flutter_deps_pop "$rest"
        name="${DEPS_LINE%%"$CBS_FLUTTER_DEPS_TAB"*}"
        rest="$DEPS_TAIL"

        index=0
        while [[ "$index" -lt "$DEPS_COUNT" && "${D_NAME[$index]}" != "$name" ]]; do
            index=$((index + 1))
        done

        if [[ "$index" -ge "$DEPS_COUNT" ]]; then
            _cbs_flutter_deps_set "DEPENDENCY_UNMAPPED"
            return 0
        fi
    done

    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        if ! _cbs_flutter_deps_is_needed "${D_NAME[$index]}"; then
            _cbs_flutter_deps_set "MAPPING_UNUSED"
            return 0
        fi

        D_SUBS[$index]="$(_cbs_flutter_deps_subpaths_of "${D_NAME[$index]}")"
        index=$((index + 1))
    done

    # Nothing to materialize: the manifest declares no external path.
    if [[ "$DEPS_COUNT" -eq 0 ]]; then
        _cbs_flutter_deps_pass
        return 0
    fi

    # ---- 5. the sources hold the packages at the explicit commits (read-only)

    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        subs="${D_SUBS[$index]}"

        while [[ -n "$subs" ]]; do
            _cbs_flutter_deps_pop "$subs"
            subpath="$DEPS_LINE"
            subs="$DEPS_TAIL"

            if ! _cbs_flutter_deps_source_has_package "${D_SOURCE[$index]}" "${D_COMMIT[$index]}" "$subpath"; then
                _cbs_flutter_deps_set "SOURCE_REJECTED" "PACKAGE_NOT_AT_COMMIT"
                return 0
            fi
        done

        index=$((index + 1))
    done

    # ---- 6. what is already there: verified or refused, before any creation

    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        name="${D_NAME[$index]}"

        if [[ -e "$root/$name" || -L "$root/$name" ]]; then
            _cbs_flutter_deps_manager verify "$name" "${D_SOURCE[$index]}" "$root" || true

            if _cbs_flutter_deps_manager_passed &&
                [[ "$DEPS_ISO_EXPECTED" == "${D_COMMIT[$index]}" && "$DEPS_ISO_OBSERVED" == "${D_COMMIT[$index]}" &&
                "$DEPS_ISO_ORIGIN" == "$(cbs_isolation_redact "${D_ORIGIN[$index]}")" ]]; then
                D_STATE[$index]="REUSED"
                D_OBSERVED[$index]="$DEPS_ISO_OBSERVED"
            else
                D_STATE[$index]="CONFLICT"
                _cbs_flutter_deps_set "DEPENDENCY_CONFLICT" "$(_cbs_flutter_deps_manager_detail)"
                [[ -n "$DEPS_DETAIL" ]] || _cbs_flutter_deps_set "DEPENDENCY_CONFLICT" "NOT_AS_REQUESTED"
                return 0
            fi
        else
            D_STATE[$index]="MISSING"
            missing=$((missing + 1))

            # An identifier is never reused, even after a cleanup (isolation
            # contract): refuse now rather than half way.
            if [[ "$operation" == "prepare" ]] &&
                [[ -e "$root/$CBS_ISOLATION_PROOF_DIR/$name.proof" || -L "$root/$CBS_ISOLATION_PROOF_DIR/$name.proof" ||
                -e "$root/$CBS_ISOLATION_PROOF_DIR/$name.cleaned" || -L "$root/$CBS_ISOLATION_PROOF_DIR/$name.cleaned" ]]; then
                D_STATE[$index]="CONFLICT"
                _cbs_flutter_deps_set "DEPENDENCY_CONFLICT" "IDENTIFIER_ALREADY_USED"
                return 0
            fi
        fi

        index=$((index + 1))
    done

    if [[ "$operation" == "verify" && "$missing" -gt 0 ]]; then
        _cbs_flutter_deps_set "DEPENDENCY_MISSING"
        return 0
    fi

    # ---- 7. materialization (only for prepare; the manager does the work)

    if [[ "$operation" == "prepare" ]]; then
        index=0
        while [[ "$index" -lt "$DEPS_COUNT" ]]; do
            if [[ "${D_STATE[$index]}" == "MISSING" ]]; then
                _cbs_flutter_deps_manager create "${D_NAME[$index]}" "${D_SOURCE[$index]}" \
                    "${D_ORIGIN[$index]}" "${D_COMMIT[$index]}" "$root" || true

                if ! _cbs_flutter_deps_manager_passed; then
                    _cbs_flutter_deps_set "MATERIALIZATION_FAILED" "$(_cbs_flutter_deps_manager_detail)"
                    return 0
                fi

                D_STATE[$index]="CREATED"
            fi

            index=$((index + 1))
        done
    fi

    # ---- 8. verification of every resource: provenance, commit, cleanliness

    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        name="${D_NAME[$index]}"

        _cbs_flutter_deps_manager verify "$name" "${D_SOURCE[$index]}" "$root" || true

        if ! _cbs_flutter_deps_manager_passed ||
            [[ "$DEPS_ISO_EXPECTED" != "${D_COMMIT[$index]}" || "$DEPS_ISO_OBSERVED" != "${D_COMMIT[$index]}" ||
            "$DEPS_ISO_ORIGIN" != "$(cbs_isolation_redact "${D_ORIGIN[$index]}")" ]]; then
            D_STATE[$index]="CONFLICT"
            _cbs_flutter_deps_set "PACKAGE_INVALID" "RESOURCE_NOT_VERIFIED"
            return 0
        fi

        D_OBSERVED[$index]="$DEPS_ISO_OBSERVED"
        [[ "$operation" != "verify" ]] || D_STATE[$index]="PRESENT"

        index=$((index + 1))
    done

    # ---- 9. the declared packages exist where Flutter will look for them

    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        subs="${D_SUBS[$index]}"
        D_PACKAGE[$index]="OK"

        while [[ -n "$subs" ]]; do
            _cbs_flutter_deps_pop "$subs"
            subpath="$DEPS_LINE"
            subs="$DEPS_TAIL"

            if ! _cbs_flutter_deps_package_ok "$root" "${D_NAME[$index]}" "$subpath"; then
                D_PACKAGE[$index]="INVALID"
            fi
        done

        if [[ "${D_PACKAGE[$index]}" != "OK" ]]; then
            _cbs_flutter_deps_set "PACKAGE_INVALID" "PACKAGE_NOT_FOUND"
            return 0
        fi

        index=$((index + 1))
    done

    # ---- 10. the path dependencies of those packages stay inside the set

    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        subs="${D_SUBS[$index]}"

        while [[ -n "$subs" ]]; do
            _cbs_flutter_deps_pop "$subs"
            subpath="$DEPS_LINE"
            subs="$DEPS_TAIL"

            if [[ "$subpath" == "." ]]; then
                package_dir="$root/${D_NAME[$index]}"
            else
                package_dir="$root/${D_NAME[$index]}/$subpath"
            fi

            if ! _cbs_flutter_deps_package_manifest_ok "$root" "$checkout" "$package_dir"; then
                D_PACKAGE[$index]="INVALID"
                _cbs_flutter_deps_set "PACKAGE_INVALID" "NESTED_PATH_NOT_RESOLVABLE"
                return 0
            fi
        done

        index=$((index + 1))
    done

    _cbs_flutter_deps_pass
    return 0
}

# --- cleanup ---------------------------------------------------------------------

# Arguments: ROOT (NAME SOURCE)...
cbs_flutter_deps_cleanup() {
    local root="$1"
    local index

    shift

    DEPS_OPERATION="CLEANUP"

    if ! _cbs_flutter_deps_check_root "$root"; then
        _cbs_flutter_deps_set "INPUT_INVALID"
        return 0
    fi

    while [[ "$#" -ge 2 ]]; do
        if ! _cbs_flutter_deps_add_mapping "$1" "$2" "" ""; then
            _cbs_flutter_deps_set "INPUT_INVALID"
            return 0
        fi

        if ! cbs_flutter_qual_paths_disjoint "$2" "$root"; then
            _cbs_flutter_deps_set "INPUT_INVALID"
            return 0
        fi

        shift 2
    done

    if [[ "$#" -ne 0 || "$DEPS_COUNT" -lt 1 ]]; then
        _cbs_flutter_deps_set "INPUT_INVALID"
        return 0
    fi

    if ! _cbs_flutter_deps_check_git; then
        _cbs_flutter_deps_set "GIT_UNSUPPORTED"
        return 0
    fi

    # Everything is verified first (read-only): nothing is removed unless every
    # requested resource is CBS-owned, exact and clean. The manager refuses an
    # unknown identifier, a directory without proof and a modified worktree.
    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        _cbs_flutter_deps_manager verify "${D_NAME[$index]}" "${D_SOURCE[$index]}" "$root" || true

        if ! _cbs_flutter_deps_manager_passed; then
            D_STATE[$index]="CONFLICT"
            _cbs_flutter_deps_set "CLEANUP_REFUSED" "$(_cbs_flutter_deps_manager_detail)"
            return 0
        fi

        D_OBSERVED[$index]="$DEPS_ISO_OBSERVED"
        D_COMMIT[$index]="$DEPS_ISO_EXPECTED"
        index=$((index + 1))
    done

    # Then one non-forced removal per resource, by the manager. A failure stops
    # everything: no retry, no sweep.
    index=0
    while [[ "$index" -lt "$DEPS_COUNT" ]]; do
        _cbs_flutter_deps_manager cleanup "${D_NAME[$index]}" "${D_SOURCE[$index]}" "$root" || true

        if ! _cbs_flutter_deps_manager_passed; then
            _cbs_flutter_deps_set "CLEANUP_FAILED" "$(_cbs_flutter_deps_manager_detail)"
            return 0
        fi

        D_STATE[$index]="REMOVED"
        index=$((index + 1))
    done

    _cbs_flutter_deps_pass
    return 0
}

# --- Entry -----------------------------------------------------------------------

cbs_flutter_deps_main() {
    local command="${1:-}"

    _cbs_flutter_deps_reset

    case "$command" in
        prepare|verify)
            # command + consumer id + consumer source + root + 4 per repository
            if [[ "$#" -lt 4 || $((($# - 4) % 4)) -ne 0 ]]; then
                DEPS_OPERATION="$(printf '%s' "$command" | tr 'a-z' 'A-Z')"
                _cbs_flutter_deps_set "USAGE"
            else
                shift
                cbs_flutter_deps_prepare "$command" "$@"
            fi
            ;;
        cleanup)
            # command + root + 2 per repository (at least one)
            if [[ "$#" -lt 4 || $((($# - 2) % 2)) -ne 0 ]]; then
                DEPS_OPERATION="CLEANUP"
                _cbs_flutter_deps_set "USAGE"
            else
                shift
                cbs_flutter_deps_cleanup "$@"
            fi
            ;;
        *)
            _cbs_flutter_deps_set "USAGE"
            ;;
    esac

    _cbs_flutter_deps_conclude
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    CBS_FLUTTER_DEPS_RC=0
    cbs_flutter_deps_main "$@" || CBS_FLUTTER_DEPS_RC=$?
    exit "$CBS_FLUTTER_DEPS_RC"
fi
