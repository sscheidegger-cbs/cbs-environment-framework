#!/usr/bin/env bash

# CBS Remote manifest loader.
#
# The manifest is a declarative KEY=VALUE file. It is parsed, never sourced:
# no shell code in a manifest is ever evaluated. Unknown keys, duplicate keys,
# empty values and any value outside the documented character set are
# rejected. The manifest contains no secret: SSH authentication relies on the
# workstation SSH configuration and agent only.

REMOTE_MANIFEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REMOTE_MANIFEST_DIR/contract.sh"

declare -gA CBS_REMOTE_CFG=()
declare -gA CBS_REMOTE_RESOLVED=()
declare -ga CBS_REMOTE_ACTIONS=()

cbs_remote_manifest_error() {
    local code="$1"
    local key="${2:-}"

    printf 'CBS_REMOTE_MANIFEST_ERROR=%s\n' "$code" >&2

    if [[ -n "$key" ]]; then
        printf 'CBS_REMOTE_MANIFEST_ERROR_KEY=%s\n' "$key" >&2
    fi

    return 1
}

# Value must be non-empty, free of leading/trailing space and match the
# pattern. Arguments: value pattern
cbs_remote_value_matches() {
    local value="$1"
    local pattern="$2"

    [[ "$value" =~ $pattern ]] || return 1
    [[ "$value" != " "* && "$value" != *" " ]] || return 1

    return 0
}

cbs_remote_path_has_parent_segment() {
    [[ "/$1/" == *"/../"* ]]
}

cbs_remote_manifest_static_key_is_known() {
    case "$1" in
        CBS_REMOTE_MANIFEST_VERSION|\
        CBS_REMOTE_ID|\
        CBS_REMOTE_SSH_DESTINATION|\
        CBS_REMOTE_SSH_PORT|\
        CBS_REMOTE_SSH_IDENTITY_FILE|\
        CBS_REMOTE_SSH_CONNECT_TIMEOUT|\
        CBS_REMOTE_PATH_PREPEND|\
        CBS_REMOTE_REPOSITORY_PATH|\
        CBS_REMOTE_REPOSITORY_ORIGIN|\
        CBS_REMOTE_EXPECTED_BRANCH|\
        CBS_REMOTE_EXPECTED_COMMIT|\
        CBS_REMOTE_LOCAL_REPOSITORY_PATH|\
        CBS_REMOTE_CBS_ENTRYPOINT|\
        CBS_REMOTE_ALLOWED_ACTIONS)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_remote_manifest_read() {
    local file="$1"
    local line
    local key
    local value
    local line_number=0

    CBS_REMOTE_CFG=()
    CBS_REMOTE_RESOLVED=()
    CBS_REMOTE_ACTIONS=()

    [[ -f "$file" && -r "$file" ]] ||
        cbs_remote_manifest_error "FILE_NOT_FOUND" ||
        return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))

        if [[ -z "$line" || "$line" == "#"* ]]; then
            continue
        fi

        if [[ ! "$line" =~ ^(CBS_REMOTE_[A-Z0-9_]+)=(.*)$ ]]; then
            printf 'CBS_REMOTE_MANIFEST_ERROR_LINE=%s\n' "$line_number" >&2
            cbs_remote_manifest_error "INVALID_LINE"
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        if [[ -n "${CBS_REMOTE_CFG[$key]+x}" ]]; then
            cbs_remote_manifest_error "DUPLICATE_KEY" "$key"
            return 1
        fi

        if [[ -z "$value" ]]; then
            cbs_remote_manifest_error "EMPTY_VALUE" "$key"
            return 1
        fi

        CBS_REMOTE_CFG["$key"]="$value"
    done < "$file"
}

cbs_remote_manifest_validate_actions() {
    local allowed="${CBS_REMOTE_CFG[CBS_REMOTE_ALLOWED_ACTIONS]}"
    local name
    local key
    local command
    local word
    local index
    local -a names=()
    local -a words=()
    local -A declared=()

    if [[ "$allowed" == *"  "* || "$allowed" == " "* || "$allowed" == *" " ]]; then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_ALLOWED_ACTIONS"
        return 1
    fi

    IFS=' ' read -r -a names <<<"$allowed"

    for name in "${names[@]}"; do
        if [[ ! "$name" =~ $CBS_REMOTE_PATTERN_ACTION_NAME ]]; then
            cbs_remote_manifest_error "INVALID_ACTION_NAME" "$name"
            return 1
        fi

        if [[ -n "${declared[$name]+x}" ]]; then
            cbs_remote_manifest_error "DUPLICATE_ACTION" "$name"
            return 1
        fi

        declared["$name"]=1
    done

    # Every key must be a known static key or the command of a declared action.
    for key in "${!CBS_REMOTE_CFG[@]}"; do
        if cbs_remote_manifest_static_key_is_known "$key"; then
            continue
        fi

        if [[ "$key" =~ ^CBS_REMOTE_ACTION_([A-Z][A-Z0-9_]*)_COMMAND$ ]]; then
            name="${BASH_REMATCH[1],,}"

            if [[ -n "${declared[$name]+x}" ]]; then
                continue
            fi

            cbs_remote_manifest_error "ACTION_NOT_DECLARED" "$key"
            return 1
        fi

        cbs_remote_manifest_error "UNKNOWN_KEY" "$key"
        return 1
    done

    for name in "${names[@]}"; do
        key="CBS_REMOTE_ACTION_${name^^}_COMMAND"

        if [[ -z "${CBS_REMOTE_CFG[$key]+x}" ]]; then
            cbs_remote_manifest_error "ACTION_COMMAND_MISSING" "$key"
            return 1
        fi

        command="${CBS_REMOTE_CFG[$key]}"

        if [[ "$command" == *"  "* || "$command" == " "* || "$command" == *" " ]]; then
            cbs_remote_manifest_error "INVALID_VALUE" "$key"
            return 1
        fi

        IFS=' ' read -r -a words <<<"$command"

        index=0
        for word in "${words[@]}"; do
            if [[ ! "$word" =~ $CBS_REMOTE_PATTERN_COMMAND_WORD ]] ||
                [[ "${#word}" -gt 256 ]] ||
                cbs_remote_path_has_parent_segment "$word"
            then
                cbs_remote_manifest_error "INVALID_COMMAND_WORD" "$key"
                return 1
            fi

            if [[ "$index" -eq 0 && "$word" == -* ]]; then
                cbs_remote_manifest_error "INVALID_COMMAND_WORD" "$key"
                return 1
            fi

            index=$((index + 1))
        done

        if ! cbs_remote_command_prefix_is_allowed \
            "${words[0]:-}" \
            "${words[1]:-}" \
            "${words[2]:-}"
        then
            cbs_remote_manifest_error "COMMAND_NOT_ALLOWED" "$key"
            return 1
        fi

        CBS_REMOTE_ACTIONS+=("$name")
        CBS_REMOTE_RESOLVED["ACTION_$name"]="$command"
    done
}

cbs_remote_manifest_validate() {
    local manifest_dir="$1"
    local required
    local value

    for required in \
        CBS_REMOTE_MANIFEST_VERSION \
        CBS_REMOTE_ID \
        CBS_REMOTE_SSH_DESTINATION \
        CBS_REMOTE_REPOSITORY_PATH \
        CBS_REMOTE_REPOSITORY_ORIGIN \
        CBS_REMOTE_EXPECTED_BRANCH \
        CBS_REMOTE_EXPECTED_COMMIT \
        CBS_REMOTE_ALLOWED_ACTIONS
    do
        if [[ -z "${CBS_REMOTE_CFG[$required]+x}" ]]; then
            cbs_remote_manifest_error "MISSING_KEY" "$required"
            return 1
        fi
    done

    if [[ "${CBS_REMOTE_CFG[CBS_REMOTE_MANIFEST_VERSION]}" != "$CBS_REMOTE_MANIFEST_VERSION" ]]; then
        cbs_remote_manifest_error "UNSUPPORTED_VERSION" "CBS_REMOTE_MANIFEST_VERSION"
        return 1
    fi

    value="${CBS_REMOTE_CFG[CBS_REMOTE_ID]}"
    cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_ID" ||
        { cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_ID"; return 1; }

    value="${CBS_REMOTE_CFG[CBS_REMOTE_SSH_DESTINATION]}"
    cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_DESTINATION" ||
        { cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_SSH_DESTINATION"; return 1; }

    if [[ -n "${CBS_REMOTE_CFG[CBS_REMOTE_SSH_PORT]+x}" ]]; then
        value="${CBS_REMOTE_CFG[CBS_REMOTE_SSH_PORT]}"

        if [[ ! "$value" =~ $CBS_REMOTE_PATTERN_UINT ]] ||
            ((10#$value < 1 || 10#$value > 65535))
        then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_SSH_PORT"
            return 1
        fi
    fi

    if [[ -n "${CBS_REMOTE_CFG[CBS_REMOTE_SSH_CONNECT_TIMEOUT]+x}" ]]; then
        value="${CBS_REMOTE_CFG[CBS_REMOTE_SSH_CONNECT_TIMEOUT]}"

        if [[ ! "$value" =~ $CBS_REMOTE_PATTERN_UINT ]] ||
            ((10#$value < 1 || 10#$value > 120))
        then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_SSH_CONNECT_TIMEOUT"
            return 1
        fi
    fi

    if [[ -n "${CBS_REMOTE_CFG[CBS_REMOTE_SSH_IDENTITY_FILE]+x}" ]]; then
        value="${CBS_REMOTE_CFG[CBS_REMOTE_SSH_IDENTITY_FILE]}"

        if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_PATH" ||
            [[ "$value" != /* ]] ||
            cbs_remote_path_has_parent_segment "$value"
        then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_SSH_IDENTITY_FILE"
            return 1
        fi
    fi

    if [[ -n "${CBS_REMOTE_CFG[CBS_REMOTE_PATH_PREPEND]+x}" ]]; then
        value="${CBS_REMOTE_CFG[CBS_REMOTE_PATH_PREPEND]}"

        if [[ ! "$value" =~ $CBS_REMOTE_PATTERN_PATH_LIST ]] ||
            cbs_remote_path_has_parent_segment "$value"
        then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_PATH_PREPEND"
            return 1
        fi
    fi

    value="${CBS_REMOTE_CFG[CBS_REMOTE_REPOSITORY_PATH]}"

    if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_PATH" ||
        [[ "$value" != /* ]] ||
        cbs_remote_path_has_parent_segment "$value"
    then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_REPOSITORY_PATH"
        return 1
    fi

    value="${CBS_REMOTE_CFG[CBS_REMOTE_REPOSITORY_ORIGIN]}"

    if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_ORIGIN"; then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_REPOSITORY_ORIGIN"
        return 1
    fi

    # An origin carrying a password or token is a secret: refuse it.
    if [[ "$value" =~ ://[^/@]*:[^/@]*@ ]]; then
        cbs_remote_manifest_error "SECRET_IN_VALUE" "CBS_REMOTE_REPOSITORY_ORIGIN"
        return 1
    fi

    value="${CBS_REMOTE_CFG[CBS_REMOTE_EXPECTED_BRANCH]}"

    if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_BRANCH" ||
        [[ "$value" == *".."* || "$value" == */ || "$value" == *.lock ]]
    then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_EXPECTED_BRANCH"
        return 1
    fi

    value="${CBS_REMOTE_CFG[CBS_REMOTE_EXPECTED_COMMIT]}"

    if [[ "$value" == "$CBS_REMOTE_EXPECTED_COMMIT_LOCAL_HEAD" ]]; then
        if [[ -z "${CBS_REMOTE_CFG[CBS_REMOTE_LOCAL_REPOSITORY_PATH]+x}" ]]; then
            cbs_remote_manifest_error "MISSING_KEY" "CBS_REMOTE_LOCAL_REPOSITORY_PATH"
            return 1
        fi

        value="${CBS_REMOTE_CFG[CBS_REMOTE_LOCAL_REPOSITORY_PATH]}"

        if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_PATH"; then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_LOCAL_REPOSITORY_PATH"
            return 1
        fi

        if [[ "$value" == /* ]]; then
            CBS_REMOTE_RESOLVED[LOCAL_REPOSITORY]="$value"
        else
            CBS_REMOTE_RESOLVED[LOCAL_REPOSITORY]="$manifest_dir/$value"
        fi
    else
        if [[ ! "$value" =~ $CBS_REMOTE_PATTERN_COMMIT ]]; then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_EXPECTED_COMMIT"
            return 1
        fi

        if [[ -n "${CBS_REMOTE_CFG[CBS_REMOTE_LOCAL_REPOSITORY_PATH]+x}" ]]; then
            cbs_remote_manifest_error "UNUSED_KEY" "CBS_REMOTE_LOCAL_REPOSITORY_PATH"
            return 1
        fi
    fi

    value="${CBS_REMOTE_CFG[CBS_REMOTE_CBS_ENTRYPOINT]:-$CBS_REMOTE_DEFAULT_ENTRYPOINT}"

    if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_PATH" ||
        [[ "$value" != */* || "$value" == */ ]] ||
        cbs_remote_path_has_parent_segment "$value"
    then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_CBS_ENTRYPOINT"
        return 1
    fi

    CBS_REMOTE_RESOLVED[ENTRYPOINT]="$value"

    cbs_remote_manifest_validate_actions
}

# Loads and validates a manifest. On success CBS_REMOTE_CFG and
# CBS_REMOTE_ACTIONS are populated. Returns 1 on any invalid manifest.
cbs_remote_manifest_load() {
    local manifest="${1:-}"
    local manifest_dir

    [[ -n "$manifest" ]] ||
        cbs_remote_manifest_error "MANIFEST_REQUIRED" ||
        return 1

    cbs_remote_manifest_read "$manifest" || return 1

    manifest_dir="$(cd "$(dirname "$manifest")" && pwd)"

    cbs_remote_manifest_validate "$manifest_dir"
}

cbs_remote_manifest_action_is_allowed() {
    local wanted="${1:-}"
    local name

    for name in "${CBS_REMOTE_ACTIONS[@]}"; do
        if [[ "$name" == "$wanted" ]]; then
            return 0
        fi
    done

    return 1
}
