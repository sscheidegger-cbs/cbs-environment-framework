#!/usr/bin/env bash

# TEST ONLY - find wrapper restricted to the subset understood by both GNU
# find and BSD find (macOS). Any other syntax makes the call fail loudly.
#
#   CBS_SHIM_REAL_FIND   absolute path of the real find (required)
#   CBS_SHIM_TOOLLOG     file receiving one line per accepted call

set -u

REAL="${CBS_SHIM_REAL_FIND:-}"

if [[ -z "$REAL" || ! -x "$REAL" ]]; then
    echo "strict find: CBS_SHIM_REAL_FIND is not usable" >&2
    exit 98
fi

reject() {
    echo "strict find: non-portable usage: $1" >&2

    if [[ -n "${CBS_SHIM_TOOLLOG:-}" ]]; then
        printf 'REJECTED find %s\n' "$1" >> "$CBS_SHIM_TOOLLOG"
    fi

    exit 97
}

# BSD find requires an explicit path operand before any expression.
case "${1:-}" in
    ""|-*|"("|"!")
        reject "path operand must come first"
        ;;
esac

expect=""
first=1
number_pattern='^[+-]?[0-9]+$'

for arg in "$@"; do
    if [[ "$first" -eq 1 ]]; then
        first=0
        continue
    fi

    if [[ -n "$expect" ]]; then
        case "$expect" in
            perm)
                case "$arg" in
                    /*|+*)
                        reject "-perm $arg"
                        ;;
                    -*|[0-7]*)
                        ;;
                    *)
                        reject "-perm $arg"
                        ;;
                esac
                ;;
            number)
                [[ "$arg" =~ $number_pattern ]] || reject "numeric operand $arg"
                ;;
        esac

        expect=""
        continue
    fi

    case "$arg" in
        -maxdepth|-mindepth|-links)
            expect="number"
            ;;
        -perm)
            expect="perm"
            ;;
        -user|-type|-name)
            expect="any"
            ;;
        -print|-o|-a|"("|")"|"!"|-empty)
            ;;
        *)
            reject "$arg"
            ;;
    esac
done

[[ -z "$expect" ]] || reject "missing operand"

if [[ -n "${CBS_SHIM_TOOLLOG:-}" ]]; then
    printf 'find %s\n' "$*" >> "$CBS_SHIM_TOOLLOG"
fi

exec "$REAL" "$@"
