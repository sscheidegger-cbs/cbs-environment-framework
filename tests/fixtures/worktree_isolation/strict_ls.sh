#!/usr/bin/env bash

# TEST ONLY - ls wrapper restricted to POSIX options available on macOS.
#
#   CBS_SHIM_REAL_LS     absolute path of the real ls (required)
#   CBS_SHIM_TOOLLOG     file receiving one line per accepted call

set -u

REAL="${CBS_SHIM_REAL_LS:-}"

if [[ -z "$REAL" || ! -x "$REAL" ]]; then
    echo "strict ls: CBS_SHIM_REAL_LS is not usable" >&2
    exit 98
fi

for arg in "$@"; do
    case "$arg" in
        -d|-i|-di|-id|-A|-l|-ld|-dl)
            ;;
        -*)
            echo "strict ls: non-portable option: $arg" >&2

            if [[ -n "${CBS_SHIM_TOOLLOG:-}" ]]; then
                printf 'REJECTED ls %s\n' "$arg" >> "$CBS_SHIM_TOOLLOG"
            fi

            exit 97
            ;;
    esac
done

if [[ -n "${CBS_SHIM_TOOLLOG:-}" ]]; then
    printf 'ls %s\n' "$*" >> "$CBS_SHIM_TOOLLOG"
fi

exec "$REAL" "$@"
