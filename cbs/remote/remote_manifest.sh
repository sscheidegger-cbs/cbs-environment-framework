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

# Keyed stores (Bash 3.2 has no associative array): indexed arrays of
# "KEY=VALUE" entries, read only through the accessors below. A manifest key is
# never used as a variable name or as a subscript.
#   CBS_REMOTE_CFG_ENTRIES       manifest key -> declared value
#   CBS_REMOTE_RESOLVED_ENTRIES  ENTRYPOINT, LOCAL_REPOSITORY, ACTION_<name>
CBS_REMOTE_CFG_ENTRIES=()
CBS_REMOTE_RESOLVED_ENTRIES=()
CBS_REMOTE_ACTIONS=()

# Arguments: KEY
cbs_remote_cfg_has() {
    cbs_remote_entries_has "$1" \
        ${CBS_REMOTE_CFG_ENTRIES[@]+"${CBS_REMOTE_CFG_ENTRIES[@]}"}
}

# Arguments: KEY [DEFAULT]. Prints the declared value (DEFAULT, empty unless
# given, when the key is absent). Use cbs_remote_cfg_has to test presence.
cbs_remote_cfg_get() {
    cbs_remote_entries_get "$1" "${2-}" \
        ${CBS_REMOTE_CFG_ENTRIES[@]+"${CBS_REMOTE_CFG_ENTRIES[@]}"}
}

# Arguments: KEY VALUE. The key must not already be present.
cbs_remote_cfg_add() {
    CBS_REMOTE_CFG_ENTRIES+=("$1=$2")
}

# Arguments: KEY
cbs_remote_resolved_has() {
    cbs_remote_entries_has "$1" \
        ${CBS_REMOTE_RESOLVED_ENTRIES[@]+"${CBS_REMOTE_RESOLVED_ENTRIES[@]}"}
}

# Arguments: KEY [DEFAULT]
cbs_remote_resolved_get() {
    cbs_remote_entries_get "$1" "${2-}" \
        ${CBS_REMOTE_RESOLVED_ENTRIES[@]+"${CBS_REMOTE_RESOLVED_ENTRIES[@]}"}
}

# Arguments: KEY VALUE. Replaces the value of an existing key.
cbs_remote_resolved_set() {
    local key="$1"
    local value="$2"
    local count="${#CBS_REMOTE_RESOLVED_ENTRIES[@]}"
    local index

    for ((index = 0; index < count; index++)); do
        if [[ "${CBS_REMOTE_RESOLVED_ENTRIES[$index]%%=*}" == "$key" ]]; then
            CBS_REMOTE_RESOLVED_ENTRIES[$index]="$key=$value"
            return 0
        fi
    done

    CBS_REMOTE_RESOLVED_ENTRIES+=("$key=$value")
}

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

    CBS_REMOTE_CFG_ENTRIES=()
    CBS_REMOTE_RESOLVED_ENTRIES=()
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

        if cbs_remote_cfg_has "$key"; then
            cbs_remote_manifest_error "DUPLICATE_KEY" "$key"
            return 1
        fi

        if [[ -z "$value" ]]; then
            cbs_remote_manifest_error "EMPTY_VALUE" "$key"
            return 1
        fi

        cbs_remote_cfg_add "$key" "$value"
    done < "$file"
}

cbs_remote_manifest_validate_actions() {
    local allowed
    local name
    local key
    local entry
    local suffix
    local command
    local word
    local index
    local -a names=()
    local -a words=()
    local -a declared=()

    allowed="$(cbs_remote_cfg_get CBS_REMOTE_ALLOWED_ACTIONS)"

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

        if cbs_remote_word_in_list "$name" \
            ${declared[@]+"${declared[@]}"}
        then
            cbs_remote_manifest_error "DUPLICATE_ACTION" "$name"
            return 1
        fi

        declared+=("$name")
    done

    # Every key must be a known static key or the command of a declared action.
    for entry in ${CBS_REMOTE_CFG_ENTRIES[@]+"${CBS_REMOTE_CFG_ENTRIES[@]}"}; do
        key="${entry%%=*}"

        if cbs_remote_manifest_static_key_is_known "$key"; then
            continue
        fi

        if [[ "$key" =~ ^CBS_REMOTE_ACTION_([A-Z][A-Z0-9_]*)_COMMAND$ ]]; then
            suffix="${BASH_REMATCH[1]}"
            name="$(cbs_remote_ascii_lower "$suffix")"

            if cbs_remote_word_in_list "$name" \
                ${declared[@]+"${declared[@]}"}
            then
                continue
            fi

            cbs_remote_manifest_error "ACTION_NOT_DECLARED" "$key"
            return 1
        fi

        cbs_remote_manifest_error "UNKNOWN_KEY" "$key"
        return 1
    done

    for name in "${names[@]}"; do
        suffix="$(cbs_remote_ascii_upper "$name")"
        key="CBS_REMOTE_ACTION_${suffix}_COMMAND"

        if ! cbs_remote_cfg_has "$key"; then
            cbs_remote_manifest_error "ACTION_COMMAND_MISSING" "$key"
            return 1
        fi

        command="$(cbs_remote_cfg_get "$key")"

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
        cbs_remote_resolved_set "ACTION_$name" "$command"
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
        if ! cbs_remote_cfg_has "$required"; then
            cbs_remote_manifest_error "MISSING_KEY" "$required"
            return 1
        fi
    done

    if [[ "$(cbs_remote_cfg_get CBS_REMOTE_MANIFEST_VERSION)" != "$CBS_REMOTE_MANIFEST_VERSION" ]]; then
        cbs_remote_manifest_error "UNSUPPORTED_VERSION" "CBS_REMOTE_MANIFEST_VERSION"
        return 1
    fi

    value="$(cbs_remote_cfg_get CBS_REMOTE_ID)"
    cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_ID" ||
        { cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_ID"; return 1; }

    value="$(cbs_remote_cfg_get CBS_REMOTE_SSH_DESTINATION)"
    cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_DESTINATION" ||
        { cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_SSH_DESTINATION"; return 1; }

    if cbs_remote_cfg_has CBS_REMOTE_SSH_PORT; then
        value="$(cbs_remote_cfg_get CBS_REMOTE_SSH_PORT)"

        if [[ ! "$value" =~ $CBS_REMOTE_PATTERN_UINT ]] ||
            ((10#$value < 1 || 10#$value > 65535))
        then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_SSH_PORT"
            return 1
        fi
    fi

    if cbs_remote_cfg_has CBS_REMOTE_SSH_CONNECT_TIMEOUT; then
        value="$(cbs_remote_cfg_get CBS_REMOTE_SSH_CONNECT_TIMEOUT)"

        if [[ ! "$value" =~ $CBS_REMOTE_PATTERN_UINT ]] ||
            ((10#$value < 1 || 10#$value > 120))
        then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_SSH_CONNECT_TIMEOUT"
            return 1
        fi
    fi

    if cbs_remote_cfg_has CBS_REMOTE_SSH_IDENTITY_FILE; then
        value="$(cbs_remote_cfg_get CBS_REMOTE_SSH_IDENTITY_FILE)"

        if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_PATH" ||
            [[ "$value" != /* ]] ||
            cbs_remote_path_has_parent_segment "$value"
        then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_SSH_IDENTITY_FILE"
            return 1
        fi
    fi

    if cbs_remote_cfg_has CBS_REMOTE_PATH_PREPEND; then
        value="$(cbs_remote_cfg_get CBS_REMOTE_PATH_PREPEND)"

        if [[ ! "$value" =~ $CBS_REMOTE_PATTERN_PATH_LIST ]] ||
            cbs_remote_path_has_parent_segment "$value"
        then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_PATH_PREPEND"
            return 1
        fi
    fi

    value="$(cbs_remote_cfg_get CBS_REMOTE_REPOSITORY_PATH)"

    if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_PATH" ||
        [[ "$value" != /* ]] ||
        cbs_remote_path_has_parent_segment "$value"
    then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_REPOSITORY_PATH"
        return 1
    fi

    value="$(cbs_remote_cfg_get CBS_REMOTE_REPOSITORY_ORIGIN)"

    if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_ORIGIN" ||
        [[ "${#value}" -gt "$CBS_REMOTE_ORIGIN_MAX_LENGTH" ]]
    then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_REPOSITORY_ORIGIN"
        return 1
    fi

    # An origin carrying a password or token is a secret: refuse it.
    if [[ "$value" =~ ://[^/@]*:[^/@]*@ ]]; then
        cbs_remote_manifest_error "SECRET_IN_VALUE" "CBS_REMOTE_REPOSITORY_ORIGIN"
        return 1
    fi

    value="$(cbs_remote_cfg_get CBS_REMOTE_EXPECTED_BRANCH)"

    if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_BRANCH" ||
        [[ "$value" == *".."* || "$value" == */ || "$value" == *.lock ]]
    then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_EXPECTED_BRANCH"
        return 1
    fi

    value="$(cbs_remote_cfg_get CBS_REMOTE_EXPECTED_COMMIT)"

    if [[ "$value" == "$CBS_REMOTE_EXPECTED_COMMIT_LOCAL_HEAD" ]]; then
        if ! cbs_remote_cfg_has CBS_REMOTE_LOCAL_REPOSITORY_PATH; then
            cbs_remote_manifest_error "MISSING_KEY" "CBS_REMOTE_LOCAL_REPOSITORY_PATH"
            return 1
        fi

        value="$(cbs_remote_cfg_get CBS_REMOTE_LOCAL_REPOSITORY_PATH)"

        if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_PATH"; then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_LOCAL_REPOSITORY_PATH"
            return 1
        fi

        if [[ "$value" == /* ]]; then
            cbs_remote_resolved_set LOCAL_REPOSITORY "$value"
        else
            cbs_remote_resolved_set LOCAL_REPOSITORY "$manifest_dir/$value"
        fi
    else
        if [[ ! "$value" =~ $CBS_REMOTE_PATTERN_COMMIT ]]; then
            cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_EXPECTED_COMMIT"
            return 1
        fi

        if cbs_remote_cfg_has CBS_REMOTE_LOCAL_REPOSITORY_PATH; then
            cbs_remote_manifest_error "UNUSED_KEY" "CBS_REMOTE_LOCAL_REPOSITORY_PATH"
            return 1
        fi
    fi

    value="$(cbs_remote_cfg_get CBS_REMOTE_CBS_ENTRYPOINT "$CBS_REMOTE_DEFAULT_ENTRYPOINT")"

    if ! cbs_remote_value_matches "$value" "$CBS_REMOTE_PATTERN_PATH" ||
        [[ "$value" != */* || "$value" == */ ]] ||
        cbs_remote_path_has_parent_segment "$value"
    then
        cbs_remote_manifest_error "INVALID_VALUE" "CBS_REMOTE_CBS_ENTRYPOINT"
        return 1
    fi

    cbs_remote_resolved_set ENTRYPOINT "$value"

    cbs_remote_manifest_validate_actions
}

# Loads and validates a manifest. On success CBS_REMOTE_CFG_ENTRIES,
# CBS_REMOTE_RESOLVED_ENTRIES and CBS_REMOTE_ACTIONS are populated. Returns 1
# on any invalid manifest.
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
