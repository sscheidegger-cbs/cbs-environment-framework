#!/usr/bin/env bash

set -Eeuo pipefail

# CBS Workstation Contract
#
# Shared machine-readable constants and validation helpers only.
# This file performs no workstation inspection or mutation.

CBS_WORKSTATION_CONTRACT_VERSION=1

# Generic result states
CBS_RESULT_PASS="PASS"
CBS_RESULT_FAIL="FAIL"
CBS_RESULT_UNKNOWN="UNKNOWN"

# Prerequisite states
CBS_PREREQUISITE_PRESENT="PRESENT"
CBS_PREREQUISITE_MISSING="MISSING"
CBS_PREREQUISITE_UNAVAILABLE="UNAVAILABLE"
CBS_PREREQUISITE_UNKNOWN="UNKNOWN"

# Isolation resource classification
CBS_RESOURCE_EXPECTED="RESOURCE_EXPECTED"
CBS_RESOURCE_EXTERNAL="RESOURCE_EXTERNAL"
CBS_RESOURCE_CONFLICT="RESOURCE_CONFLICT"
CBS_RESOURCE_UNKNOWN="RESOURCE_UNKNOWN"

# Workstation aggregate states
CBS_WORKSTATION_READY="READY"
CBS_WORKSTATION_INCOMPLETE="INCOMPLETE"
CBS_WORKSTATION_CONFLICT="CONFLICT"
CBS_WORKSTATION_UNKNOWN="UNKNOWN"

# Return codes
CBS_RC_OK=0
CBS_RC_PREREQUISITE_FAILURE=10
CBS_RC_ISOLATION_CONFLICT=20
CBS_RC_INVALID_INPUT=30
CBS_RC_INVALID_CONTEXT=64

cbs_workstation_contract_validate_resource_classification() {
    case "${1:-}" in
        "$CBS_RESOURCE_EXPECTED"|"$CBS_RESOURCE_EXTERNAL"|"$CBS_RESOURCE_CONFLICT"|"$CBS_RESOURCE_UNKNOWN")
            return "$CBS_RC_OK"
            ;;
        *)
            return "$CBS_RC_INVALID_INPUT"
            ;;
    esac
}

cbs_workstation_contract_validate_prerequisite_state() {
    case "${1:-}" in
        "$CBS_PREREQUISITE_PRESENT"|"$CBS_PREREQUISITE_MISSING"|"$CBS_PREREQUISITE_UNAVAILABLE"|"$CBS_PREREQUISITE_UNKNOWN")
            return "$CBS_RC_OK"
            ;;
        *)
            return "$CBS_RC_INVALID_INPUT"
            ;;
    esac
}

cbs_workstation_contract_validate_workstation_state() {
    case "${1:-}" in
        "$CBS_WORKSTATION_READY"|"$CBS_WORKSTATION_INCOMPLETE"|"$CBS_WORKSTATION_CONFLICT"|"$CBS_WORKSTATION_UNKNOWN")
            return "$CBS_RC_OK"
            ;;
        *)
            return "$CBS_RC_INVALID_INPUT"
            ;;
    esac
}
