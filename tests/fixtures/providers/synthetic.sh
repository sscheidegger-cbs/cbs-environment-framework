#!/usr/bin/env bash

set -Eeuo pipefail

operation="${1:-}"
toolchain_id="${2:-}"
requested_version="${3:-}"
toolchain_root="${4:-}"

if [[ -z "$operation" || -z "$toolchain_id" || -z "$requested_version" || -z "$toolchain_root" ]]; then
    echo "CBS_TOOLCHAIN_PROVIDER_ERROR=USAGE" >&2
    exit 64
fi

resolved_path="$toolchain_root/$toolchain_id/$requested_version"
binary_path="$resolved_path/bin/synthetic"

case "$operation" in
    DETECT)
        if [[ -x "$binary_path" ]]; then
            echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE"
        else
            echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING"
        fi

        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        ;;

    ENSURE)
        mkdir -p "$resolved_path/bin"

        cat > "$binary_path" <<BINARY
#!/usr/bin/env bash
echo "$requested_version"
BINARY

        chmod +x "$binary_path"

        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        echo "CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=PASS"
        ;;

    VERIFY)
        if [[ ! -x "$binary_path" ]]; then
            echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
            exit 82
        fi

        observed="$("$binary_path")"

        echo "CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=$observed"

        if [[ "$observed" == "$requested_version" ]]; then
            echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS"
        else
            echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
            exit 82
        fi
        ;;

    *)
        echo "CBS_TOOLCHAIN_PROVIDER_ERROR=UNSUPPORTED_OPERATION" >&2
        exit 82
        ;;
esac
