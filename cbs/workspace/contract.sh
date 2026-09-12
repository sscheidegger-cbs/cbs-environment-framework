#!/usr/bin/env bash

CBS_WORKSPACE_CONTRACT_VERSION=1

CBS_WORKSPACE_READY="READY"
CBS_WORKSPACE_MISSING="MISSING"
CBS_WORKSPACE_INVALID="INVALID"
CBS_WORKSPACE_UNKNOWN="UNKNOWN"

CBS_WORKSPACE_PATH_DIRECTORY="DIRECTORY"
CBS_WORKSPACE_PATH_FILE="FILE"
CBS_WORKSPACE_PATH_OTHER="OTHER"
CBS_WORKSPACE_PATH_ABSENT="ABSENT"

CBS_WORKSPACE_RC_OK=0
CBS_WORKSPACE_RC_MISSING=40
CBS_WORKSPACE_RC_INVALID=41
CBS_WORKSPACE_RC_UNKNOWN=42
CBS_WORKSPACE_RC_USAGE=64

cbs_workspace_classify_path() {
    local path="${1:-}"

    if [[ -z "$path" ]]; then
        printf '%s\n' "$CBS_WORKSPACE_PATH_ABSENT"
        return "$CBS_WORKSPACE_RC_OK"
    fi

    if [[ -d "$path" ]]; then
        printf '%s\n' "$CBS_WORKSPACE_PATH_DIRECTORY"
        return "$CBS_WORKSPACE_RC_OK"
    fi

    if [[ -f "$path" ]]; then
        printf '%s\n' "$CBS_WORKSPACE_PATH_FILE"
        return "$CBS_WORKSPACE_RC_OK"
    fi

    if [[ -e "$path" ]]; then
        printf '%s\n' "$CBS_WORKSPACE_PATH_OTHER"
        return "$CBS_WORKSPACE_RC_OK"
    fi

    printf '%s\n' "$CBS_WORKSPACE_PATH_ABSENT"
    return "$CBS_WORKSPACE_RC_OK"
}

cbs_workspace_state_from_path_class() {
    local path_class="${1:-}"

    case "$path_class" in
        "$CBS_WORKSPACE_PATH_DIRECTORY")
            printf '%s\n' "$CBS_WORKSPACE_READY"
            ;;
        "$CBS_WORKSPACE_PATH_ABSENT")
            printf '%s\n' "$CBS_WORKSPACE_MISSING"
            ;;
        "$CBS_WORKSPACE_PATH_FILE"|"$CBS_WORKSPACE_PATH_OTHER")
            printf '%s\n' "$CBS_WORKSPACE_INVALID"
            ;;
        *)
            printf '%s\n' "$CBS_WORKSPACE_UNKNOWN"
            ;;
    esac
}

cbs_workspace_rc_from_state() {
    local state="${1:-}"

    case "$state" in
        "$CBS_WORKSPACE_READY")
            return "$CBS_WORKSPACE_RC_OK"
            ;;
        "$CBS_WORKSPACE_MISSING")
            return "$CBS_WORKSPACE_RC_MISSING"
            ;;
        "$CBS_WORKSPACE_INVALID")
            return "$CBS_WORKSPACE_RC_INVALID"
            ;;
        *)
            return "$CBS_WORKSPACE_RC_UNKNOWN"
            ;;
    esac
}
