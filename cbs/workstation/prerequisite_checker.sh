#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$SCRIPT_DIR/contract.sh"

source "$CONTRACT"

cbs_prerequisite_emit() {
    local name="$1"
    local state="$2"
    local value="${3:-}"

    printf 'CBS_PREREQUISITE_NAME=%s\n' "$name"
    printf 'CBS_PREREQUISITE_STATE=%s\n' "$state"

    if [[ -n "$value" ]]; then
        printf 'CBS_PREREQUISITE_VALUE=%s\n' "$value"
    fi
}

cbs_prerequisite_check_command() {
    local name="$1"
    local command_name="$2"
    local value=""

    if ! command -v "$command_name" >/dev/null 2>&1; then
        cbs_prerequisite_emit \
            "$name" \
            "$CBS_PREREQUISITE_MISSING"

        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    value="$(command -v "$command_name")"

    cbs_prerequisite_emit \
        "$name" \
        "$CBS_PREREQUISITE_PRESENT" \
        "$value"

    return "$CBS_RC_OK"
}

cbs_prerequisite_check_docker_engine() {
    if ! command -v docker >/dev/null 2>&1; then
        cbs_prerequisite_emit \
            "DOCKER_ENGINE" \
            "$CBS_PREREQUISITE_MISSING"

        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    if ! docker info >/dev/null 2>&1; then
        cbs_prerequisite_emit \
            "DOCKER_ENGINE" \
            "$CBS_PREREQUISITE_UNAVAILABLE"

        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    cbs_prerequisite_emit \
        "DOCKER_ENGINE" \
        "$CBS_PREREQUISITE_PRESENT"

    return "$CBS_RC_OK"
}

cbs_prerequisite_check_docker_compose() {
    if ! command -v docker >/dev/null 2>&1; then
        cbs_prerequisite_emit \
            "DOCKER_COMPOSE" \
            "$CBS_PREREQUISITE_MISSING"

        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    if ! docker compose version >/dev/null 2>&1; then
        cbs_prerequisite_emit \
            "DOCKER_COMPOSE" \
            "$CBS_PREREQUISITE_UNAVAILABLE"

        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    local version
    version="$(docker compose version 2>/dev/null | head -n 1)"

    cbs_prerequisite_emit \
        "DOCKER_COMPOSE" \
        "$CBS_PREREQUISITE_PRESENT" \
        "$version"

    return "$CBS_RC_OK"
}

cbs_prerequisite_check_python_312() {
    if ! command -v uv >/dev/null 2>&1; then
        cbs_prerequisite_emit \
            "PYTHON_312" \
            "$CBS_PREREQUISITE_UNKNOWN"

        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    local python_path

    if ! python_path="$(uv python find 3.12 2>/dev/null)"; then
        cbs_prerequisite_emit \
            "PYTHON_312" \
            "$CBS_PREREQUISITE_MISSING"

        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    cbs_prerequisite_emit \
        "PYTHON_312" \
        "$CBS_PREREQUISITE_PRESENT" \
        "$python_path"

    return "$CBS_RC_OK"
}

cbs_prerequisite_check_all() {
    local failures=0

    cbs_prerequisite_check_command "GIT" git ||
        failures=$((failures + 1))

    cbs_prerequisite_check_command "SSH" ssh ||
        failures=$((failures + 1))

    cbs_prerequisite_check_command "CURL" curl ||
        failures=$((failures + 1))

    cbs_prerequisite_check_command "DOCKER" docker ||
        failures=$((failures + 1))

    cbs_prerequisite_check_command "UV" uv ||
        failures=$((failures + 1))

    cbs_prerequisite_check_docker_engine ||
        failures=$((failures + 1))

    cbs_prerequisite_check_docker_compose ||
        failures=$((failures + 1))

    cbs_prerequisite_check_python_312 ||
        failures=$((failures + 1))

    printf 'CBS_PREREQUISITE_REQUIRED_FAILURES=%d\n' "$failures"

    if ((failures > 0)); then
        printf 'CBS_PREREQUISITE_RESULT=%s\n' "$CBS_RESULT_FAIL"
        return "$CBS_RC_PREREQUISITE_FAILURE"
    fi

    printf 'CBS_PREREQUISITE_RESULT=%s\n' "$CBS_RESULT_PASS"

    return "$CBS_RC_OK"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cbs_prerequisite_check_all
fi
