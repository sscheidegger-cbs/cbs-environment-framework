#!/usr/bin/env bash

set -Eeuo pipefail

cbs_context_error() {
    printf "CBS_CONTEXT_ERROR=%s\n" "$1" >&2
}

cbs_context_is_allowed_key() {
    case "$1" in
        CBS_CONTEXT_VERSION|CBS_CONTEXT_CLIENT|CBS_CONTEXT_ENTITY_TYPE|CBS_CONTEXT_ENTITY_NAME|CBS_CONTEXT_REPOSITORY_PATH|CBS_CONTEXT_BRANCH|CBS_CONTEXT_ENVIRONMENT)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cbs_context_read() {
    local file="$1"
    local line
    local key
    local value
    local line_number=0

    [[ -f "$file" ]] || {
        cbs_context_error "FILE_NOT_FOUND"
        return 10
    }

    unset CBS_CONTEXT_VERSION
    unset CBS_CONTEXT_CLIENT
    unset CBS_CONTEXT_ENTITY_TYPE
    unset CBS_CONTEXT_ENTITY_NAME
    unset CBS_CONTEXT_REPOSITORY_PATH
    unset CBS_CONTEXT_BRANCH
    unset CBS_CONTEXT_ENVIRONMENT

    declare -A seen=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))

        [[ -n "$line" ]] || {
            cbs_context_error "EMPTY_LINE"
            printf "CBS_CONTEXT_ERROR_LINE=%s\n" "$line_number" >&2
            return 11
        }

        [[ "$line" == *=* ]] || {
            cbs_context_error "INVALID_LINE"
            printf "CBS_CONTEXT_ERROR_LINE=%s\n" "$line_number" >&2
            return 11
        }

        key="${line%%=*}"
        value="${line#*=}"

        cbs_context_is_allowed_key "$key" || {
            cbs_context_error "UNKNOWN_KEY"
            printf "CBS_CONTEXT_ERROR_KEY=%s\n" "$key" >&2
            return 12
        }

        [[ -z "${seen[$key]+x}" ]] || {
            cbs_context_error "DUPLICATE_KEY"
            printf "CBS_CONTEXT_ERROR_KEY=%s\n" "$key" >&2
            return 13
        }

        [[ -n "$value" ]] || {
            cbs_context_error "EMPTY_VALUE"
            printf "CBS_CONTEXT_ERROR_KEY=%s\n" "$key" >&2
            return 14
        }

        seen["$key"]=1
        printf -v "$key" "%s" "$value"
    done < "$file"
}

cbs_context_validate() {
    local required

    for required in \
        CBS_CONTEXT_VERSION \
        CBS_CONTEXT_CLIENT \
        CBS_CONTEXT_ENTITY_TYPE \
        CBS_CONTEXT_ENTITY_NAME \
        CBS_CONTEXT_REPOSITORY_PATH \
        CBS_CONTEXT_BRANCH \
        CBS_CONTEXT_ENVIRONMENT
    do
        [[ -n "${!required:-}" ]] || {
            cbs_context_error "MISSING_KEY"
            printf "CBS_CONTEXT_ERROR_KEY=%s\n" "$required" >&2
            return 15
        }
    done

    [[ "$CBS_CONTEXT_VERSION" == "1" ]] || {
        cbs_context_error "UNSUPPORTED_VERSION"
        return 16
    }

    case "$CBS_CONTEXT_ENTITY_TYPE" in
        platform|project)
            ;;
        *)
            cbs_context_error "INVALID_ENTITY_TYPE"
            return 17
            ;;
    esac

    case "$CBS_CONTEXT_ENVIRONMENT" in
        LOCAL|TEST|PREPROD|PROD)
            ;;
        *)
            cbs_context_error "INVALID_ENVIRONMENT"
            return 18
            ;;
    esac

    return 0
}

cbs_context_load() {
    local file="$1"

    cbs_context_read "$file" || return $?
    cbs_context_validate
}
