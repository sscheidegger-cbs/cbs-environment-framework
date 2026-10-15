#!/usr/bin/env bash

# TEST ONLY - sed wrapper restricted to the subset understood by both GNU sed
# and BSD sed (macOS). Any GNU-only option or script extension fails loudly.
#
#   CBS_SHIM_REAL_SED    absolute path of the real sed (required)
#   CBS_SHIM_TOOLLOG     file receiving one line per accepted call

set -u

REAL="${CBS_SHIM_REAL_SED:-}"

if [[ -z "$REAL" || ! -x "$REAL" ]]; then
    echo "strict sed: CBS_SHIM_REAL_SED is not usable" >&2
    exit 98
fi

reject() {
    echo "strict sed: non-portable usage: $1" >&2

    if [[ -n "${CBS_SHIM_TOOLLOG:-}" ]]; then
        printf 'REJECTED sed %s\n' "$1" >> "$CBS_SHIM_TOOLLOG"
    fi

    exit 97
}

check_script() {
    local script="$1"
    local delimiter
    local flags

    # GNU extensions of basic regular expressions and escapes.
    case "$script" in
        *'\+'*|*'\?'*|*'\|'*)
            reject "GNU regular expression escape in: $script"
            ;;
        *'\n'*|*'\t'*|*'\w'*|*'\W'*|*'\s'*|*'\S'*|*'\b'*|*'\<'*|*'\>'*)
            reject "GNU escape sequence in: $script"
            ;;
        *'~'*)
            case "$script" in
                [0-9]*'~'[0-9]*)
                    reject "GNU step address in: $script"
                    ;;
            esac
            ;;
    esac

    # Substitution flags: only g, p and digits are portable.
    case "$script" in
        s?*)
            delimiter="${script:1:1}"
            flags="${script##*"$delimiter"}"

            if [[ ! "$flags" =~ ^[gp0-9]*$ ]]; then
                reject "substitution flag '$flags' in: $script"
            fi
            ;;
    esac
}

script_seen=0
expect_script=0

for arg in "$@"; do
    if [[ "$expect_script" -eq 1 ]]; then
        check_script "$arg"
        script_seen=1
        expect_script=0
        continue
    fi

    case "$arg" in
        -n|-E)
            ;;
        -e)
            expect_script=1
            ;;
        -*)
            if [[ "$arg" != "-" ]]; then
                reject "option $arg"
            fi
            ;;
        *)
            if [[ "$script_seen" -eq 0 ]]; then
                check_script "$arg"
                script_seen=1
            fi
            ;;
    esac
done

if [[ -n "${CBS_SHIM_TOOLLOG:-}" ]]; then
    printf 'sed %s\n' "$*" >> "$CBS_SHIM_TOOLLOG"
fi

exec "$REAL" "$@"
