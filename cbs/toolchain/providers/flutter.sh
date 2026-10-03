#!/usr/bin/env bash

set -Eeuo pipefail

operation="${1:-}"
toolchain_id="${2:-}"
requested_version="${3:-}"
toolchain_root="${4:-}"

fail_usage() {
    echo "CBS_TOOLCHAIN_PROVIDER_ERROR=USAGE" >&2
    exit 64
}

fail_provider() {
    local error="${1:-PROVIDER_FAILURE}"
    echo "CBS_TOOLCHAIN_PROVIDER_ERROR=$error" >&2
    exit 82
}

[[ -n "$operation" ]] || fail_usage
[[ -n "$toolchain_id" ]] || fail_usage
[[ -n "$requested_version" ]] || fail_usage
[[ -n "$toolchain_root" ]] || fail_usage

[[ "$toolchain_id" == "flutter" ]] ||
    fail_provider "UNSUPPORTED_TOOLCHAIN"

resolved_path="$toolchain_root/$toolchain_id/$requested_version"
flutter_bin="$resolved_path/bin/flutter"
dart_bin="$resolved_path/bin/dart"

release_metadata_source="${CBS_FLUTTER_RELEASES_FILE:-https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json}"

cbs_flutter_observed_version() {
    local binary="${1:-}"

    [[ -x "$binary" ]] || return 1

    "$binary" --version 2>&1 |
        awk '
            /^Flutter[[:space:]]+[0-9]/ {
                print $2
                exit
            }
        '
}

cbs_dart_observed_version() {
    local binary="${1:-}"

    [[ -x "$binary" ]] || return 1

    "$binary" --version 2>&1 |
        awk '
            /Dart SDK version:/ {
                for (i = 1; i <= NF; i++) {
                    if ($i == "version:") {
                        print $(i + 1)
                        exit
                    }
                }
            }

            /^Dart[[:space:]]+[0-9]/ {
                print $2
                exit
            }
        '
}

cbs_flutter_release_metadata() {
    python3 - "$release_metadata_source" "$requested_version" <<'PY'
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

source = sys.argv[1]
requested_version = sys.argv[2]

if source.startswith(("http://", "https://", "file://")):
    with urllib.request.urlopen(source) as response:
        data = json.load(response)
else:
    data = json.loads(Path(source).read_text())

release = None

for candidate in data.get("releases", []):
    if (
        candidate.get("version") == requested_version
        and candidate.get("channel") == "stable"
    ):
        release = candidate
        break

if release is None:
    raise SystemExit(2)

base_url = data.get("base_url", "")
archive = release.get("archive", "")
sha256 = release.get("sha256", "")
dart_version = release.get("dart_sdk_version", "")

if not base_url or not archive or not sha256:
    raise SystemExit(3)

print(f"BASE_URL={base_url}")
print(f"ARCHIVE={archive}")
print(f"SHA256={sha256}")
print(f"DART_VERSION={dart_version}")
PY
}

cbs_flutter_detect() {
    if [[ ! -e "$resolved_path" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=MISSING"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        return 0
    fi

    if [[ ! -x "$flutter_bin" || ! -x "$dart_bin" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=INVALID"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        return 0
    fi

    local observed_version=""
    observed_version="$(cbs_flutter_observed_version "$flutter_bin" || true)"

    if [[ -z "$observed_version" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=INVALID"
        echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
        return 0
    fi

    if [[ "$observed_version" == "$requested_version" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_COMPATIBLE"
    else
        echo "CBS_TOOLCHAIN_PROVIDER_INSTALLATION_STATE=PRESENT_INCOMPATIBLE"
    fi

    echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
}

cbs_flutter_ensure() {
    command -v python3 >/dev/null 2>&1 ||
        fail_provider "PYTHON3_MISSING"

    command -v curl >/dev/null 2>&1 ||
        fail_provider "CURL_MISSING"

    command -v tar >/dev/null 2>&1 ||
        fail_provider "TAR_MISSING"

    command -v sha256sum >/dev/null 2>&1 ||
        fail_provider "SHA256SUM_MISSING"

    local metadata=""
    local metadata_rc=0

    set +e
    metadata="$(cbs_flutter_release_metadata 2>&1)"
    metadata_rc=$?
    set -e

    if [[ "$metadata_rc" -ne 0 ]]; then
        echo "$metadata" >&2
        fail_provider "RELEASE_METADATA_RESOLUTION_FAILED"
    fi

    local base_url=""
    local archive=""
    local expected_sha256=""

    while IFS= read -r line
    do
        case "$line" in
            BASE_URL=*)
                base_url="${line#BASE_URL=}"
                ;;
            ARCHIVE=*)
                archive="${line#ARCHIVE=}"
                ;;
            SHA256=*)
                expected_sha256="${line#SHA256=}"
                ;;
        esac
    done <<<"$metadata"

    [[ -n "$base_url" ]] ||
        fail_provider "RELEASE_BASE_URL_MISSING"

    [[ -n "$archive" ]] ||
        fail_provider "RELEASE_ARCHIVE_MISSING"

    [[ -n "$expected_sha256" ]] ||
        fail_provider "RELEASE_SHA256_MISSING"

    local archive_url="${base_url%/}/$archive"
    local work_dir=""
    local archive_file=""
    local extraction_dir=""

    work_dir="$(mktemp -d)"
    archive_file="$work_dir/flutter.tar.xz"
    extraction_dir="$work_dir/extracted"

    cleanup() {
        rm -rf "$work_dir"
    }

    trap cleanup RETURN

    mkdir -p "$extraction_dir"

    if ! curl \
        --fail \
        --silent \
        --show-error \
        --location \
        "$archive_url" \
        -o "$archive_file"
    then
        fail_provider "DOWNLOAD_FAILED"
    fi

    local observed_sha256=""
    observed_sha256="$(sha256sum "$archive_file" | awk '{print $1}')"

    if [[ "$observed_sha256" != "$expected_sha256" ]]; then
        fail_provider "CHECKSUM_MISMATCH"
    fi

    if ! tar \
        -xJf "$archive_file" \
        -C "$extraction_dir"
    then
        fail_provider "EXTRACTION_FAILED"
    fi

    [[ -d "$extraction_dir/flutter" ]] ||
        fail_provider "ARCHIVE_LAYOUT_INVALID"

    [[ ! -e "$resolved_path" ]] ||
        fail_provider "TARGET_ALREADY_EXISTS"

    mkdir -p "$(dirname "$resolved_path")"

    mv "$extraction_dir/flutter" "$resolved_path"

    [[ -x "$flutter_bin" ]] ||
        fail_provider "FLUTTER_BINARY_MISSING"

    [[ -x "$dart_bin" ]] ||
        fail_provider "DART_BINARY_MISSING"

    echo "CBS_TOOLCHAIN_PROVIDER_RESOLVED_PATH=$resolved_path"
    echo "CBS_TOOLCHAIN_PROVIDER_ENSURE_RESULT=PASS"
}

cbs_flutter_verify() {
    [[ -x "$flutter_bin" ]] || {
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        exit 82
    }

    [[ -x "$dart_bin" ]] || {
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        exit 82
    }

    local flutter_version=""
    local dart_version=""

    flutter_version="$(cbs_flutter_observed_version "$flutter_bin" || true)"
    dart_version="$(cbs_dart_observed_version "$dart_bin" || true)"

    echo "CBS_TOOLCHAIN_PROVIDER_VERSION_OBSERVED=$flutter_version"
    echo "CBS_FLUTTER_DART_VERSION_OBSERVED=$dart_version"

    if [[ "$flutter_version" != "$requested_version" ]]; then
        echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=FAIL"
        exit 82
    fi

    echo "CBS_TOOLCHAIN_PROVIDER_VERIFY_RESULT=PASS"
}

case "$operation" in
    DETECT)
        cbs_flutter_detect
        ;;

    ENSURE)
        cbs_flutter_ensure
        ;;

    VERIFY)
        cbs_flutter_verify
        ;;

    *)
        echo "CBS_TOOLCHAIN_PROVIDER_ERROR=UNSUPPORTED_OPERATION" >&2
        exit 82
        ;;
esac
