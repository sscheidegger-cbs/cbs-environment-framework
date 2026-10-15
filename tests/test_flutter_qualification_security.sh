#!/usr/bin/env bash

# D04b-C.2b step 1: hermetic security test of the Flutter/iOS qualification
# contract: inputs are data, paths are bounded, secrets are never kept or
# echoed, nothing is executed or written.
#
# Never runs Flutter, Dart, Xcode, simctl, Git or SSH: forbidden-tool shims
# are placed first in PATH and must remain uncalled.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/cbs/qualification/flutter/contract.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_SECURITY"

source "$ROOT/tests/fixtures/flutter_qualification/lib.sh"

fq_init
fq_shims_install
export PATH="$FQ_SHIM_BIN:$PATH"

source "$CONTRACT"

# Nothing may be created by the validators: they run in an empty directory
# and a marker lets us look for files written anywhere in the repository.
WORK="$FQ_TMP/work"
mkdir "$WORK"
: > "$FQ_TMP/marker"
sleep 1
cd "$WORK"

PWNED="$FQ_TMP/pwned"

# ---------------------------------------------------------------- 1. injection: inputs are data

PAYLOADS=(
    "\$(touch $PWNED)"
    "\`touch $PWNED\`"
    ";touch $PWNED;"
    "a[\$(touch $PWNED)]"
    "\$((\$(touch $PWNED)))"
    "x' ; touch $PWNED ; '"
    "x\" ; touch $PWNED ; \""
    "| touch $PWNED"
    "&& touch $PWNED"
    "\${IFS}touch\${IFS}$PWNED"
    "$(printf 'x\ntouch %s' "$PWNED")"
    "-oProxyCommand=touch $PWNED"
    "--dart-define=A=\$(touch $PWNED)"
)

ALL_KEYS="contract_version qualification_id isolation_id source_repository expected_origin commit isolation_root evidence_root target actions timeout_seconds log_max_bytes evidence_retention cleanup_policy test_scope test_targets simulator_udid simulator_policy"

for payload in "${PAYLOADS[@]}"; do
    for key in $ALL_KEYS; do
        fq_request_reset
        fq_request_set "$key" "$payload"
        fq_validate_request
        [[ "$FQ_RC" -ne 0 ]] || fq_fail "INJECTION_ACCEPTED_$key"
        [[ ! -e "$PWNED" ]] || fq_fail "INJECTION_EXECUTED_$key"
    done

    # The payload as a key, as an extra argument, as an action, as a tool code.
    set +e
    cbs_flutter_qual_validate_request "${payload}=x" >/dev/null 2>&1
    [[ $? -ne 0 ]] || { set -e; fq_fail "INJECTION_KEY_ACCEPTED"; }
    cbs_flutter_qual_validate_request "$payload" >/dev/null 2>&1
    [[ $? -ne 0 ]] || { set -e; fq_fail "INJECTION_ARG_ACCEPTED"; }
    cbs_flutter_qual_validate_action_call analyze "$payload" >/dev/null 2>&1
    [[ $? -eq 123 ]] || { set -e; fq_fail "INJECTION_ACTION_ARG"; }
    cbs_flutter_qual_validate_action "$payload" >/dev/null 2>&1
    [[ $? -eq 122 ]] || { set -e; fq_fail "INJECTION_ACTION"; }
    cbs_flutter_qual_emit_operation ANALYZE FAIL COMMAND_FAILED "$payload" >/dev/null 2>&1
    [[ $? -eq 64 ]] || { set -e; fq_fail "INJECTION_TOOL_RC"; }
    cbs_flutter_qual_uint_in_range "$payload" 1 10 >/dev/null 2>&1
    [[ $? -ne 0 ]] || { set -e; fq_fail "INJECTION_UINT"; }
    cbs_flutter_qual_path_valid "$payload" >/dev/null 2>&1
    [[ $? -ne 0 ]] || { set -e; fq_fail "INJECTION_PATH"; }
    cbs_flutter_qual_redact "$payload" >/dev/null 2>&1
    cbs_flutter_qual_text_contains_secret "$payload" >/dev/null 2>&1
    cbs_flutter_qual_entries_get "$payload" "a=b" >/dev/null 2>&1
    set -e

    [[ ! -e "$PWNED" ]] || fq_fail "INJECTION_EXECUTED_AUX"
done

# Keys and entries are compared as plain strings, never as patterns.
fq_expect_rc 1 "ENTRIES_GET_GLOB" cbs_flutter_qual_entries_get '*' "a=1"
fq_expect_rc 1 "ENTRIES_GET_PREFIX" cbs_flutter_qual_entries_get "a" "ab=1"
fq_expect_rc 1 "ENTRIES_GET_NO_EQUAL" cbs_flutter_qual_entries_get "a" "a"
fq_expect_rc 0 "ENTRIES_GET_EXACT" cbs_flutter_qual_entries_get "a" "b=2" "a=1"
[[ "$(cbs_flutter_qual_entries_get a "a=1" "a=2")" == "1" ]] || fq_fail "ENTRIES_GET_FIRST"
[[ "$(cbs_flutter_qual_entries_get a "a=x=y")" == "x=y" ]] || fq_fail "ENTRIES_GET_VALUE_WITH_EQUAL"

# A filename that looks like an option or a glob is just text.
touch "$WORK/-n" "$WORK/token" "$WORK/a"
fq_request_reset
fq_request_set qualification_id "*"
fq_validate_request
[[ "$FQ_RC" -eq 121 ]] || fq_fail "GLOB_ID_RC_$FQ_RC"

echo "${TEST_PREFIX}_NO_INJECTION=PASS"

# The environment cannot relax the bounds of the contract.
(
    env -i PATH="$PATH" \
        CBS_FLUTTER_QUAL_TIMEOUT_MAX=999999 \
        CBS_FLUTTER_QUAL_LOG_MAX_BYTES_MAX=999999999999 \
        CBS_FLUTTER_QUAL_REQUIRED_KEYS="" \
        CBS_FLUTTER_QUAL_PATTERN_PATH='.*' \
        CBS_FLUTTER_QUAL_SECRET_WORDS="" \
        bash -c '
            source "$1" || exit 90
            cbs_flutter_qual_uint_in_range 5000 1 "$CBS_FLUTTER_QUAL_TIMEOUT_MAX" && exit 91
            cbs_flutter_qual_path_valid "relative/x" && exit 92
            cbs_flutter_qual_text_contains_secret "token=abc" || exit 93
            cbs_flutter_qual_validate_request "contract_version=1" >/dev/null 2>&1
            [ "$?" -eq 121 ] || exit 94
            exit 0
        ' _ "$CONTRACT"
) || fq_fail "ENVIRONMENT_OVERRIDE_RC_$?"

echo "${TEST_PREFIX}_ENVIRONMENT_NOT_TRUSTED=PASS"

# ---------------------------------------------------------------- 2. paths

for value in "relative/path" "./x" "../x" "/" "/tmp" "/etc" "/srv/../etc/passwd" "/srv/cbs/../../etc" \
    "/srv/./x" "/srv//x" "/srv/cbs/" '~/x' "~root/x" '/srv/$HOME/x' '/srv/${HOME}/x' '/srv/`id`/x' \
    "/srv/a b/x" "/srv/a;b/x" "/srv/a|b/x" "/srv/a&b/x" "/srv/a>b/x" "/srv/a<b/x" "/srv/a*b/x" \
    "/srv/a?b/x" "/srv/a[b]/x" "/srv/a{b}/x" "/srv/a(b)/x" "/srv/a'b/x" '/srv/a"b/x' '/srv/a\b/x' \
    "/srv/a!b/x" "/srv/a#b/x" "/srv/a%b/x" "/srv/a=b/x" "/srv/a,b/x" "/srv/a:b/x" \
    "/srv/cbs/.git/x" "/srv/cbs/.GIT/x" "/srv/cbs/.Git" "/srv/cbs/.local/share" "/srv/.ssh/x" \
    "/srv/.gnupg/x" "/srv/.aws/x" "/srv/.kube/x" "/srv/.docker/x" "/srv/.netrc/x" "/srv/.env/x" \
    "$(printf '\n/srv/x/y')" "$(printf '/srv/x\n/y')" "$(printf '/srv/x\t/y')" "" "-/srv/x" "file:///srv/x"; do
    if cbs_flutter_qual_path_valid "$value"; then
        fq_fail "PATH_ACCEPTED_$(printf '%s' "$value" | tr -c 'A-Za-z0-9._/-' '_')"
    fi
done

for value in "/srv/cbs" "/srv/cbs/source/app" "/Users/ci/cbs-iso" "/var/folders/pj/d12rdmjs2gx_zcq/T/cbs-flutter-qual.abc" \
    "/home/user/.cache/cbs" "/srv/cbs/a.b/c-d_e+f@g" "/srv/cbs/..data" "/srv/cbs/.cbs-isolation-root" "/srv/gitrepo/x" "/srv/x.git/y"; do
    cbs_flutter_qual_path_valid "$value" || fq_fail "PATH_REFUSED_$value"
done

# Over-long path.
long="/srv"
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do
    long="$long/$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50)"
done
[[ "${#long}" -gt 1024 ]] || fq_fail "LONG_PATH_FIXTURE"
if cbs_flutter_qual_path_valid "$long"; then
    fq_fail "PATH_TOO_LONG_ACCEPTED"
fi

# within / disjoint are lexical on whole components.
cbs_flutter_qual_path_is_within /srv/cbs /srv/cbs/a || fq_fail "WITHIN_BASIC"
fq_expect_rc 1 "WITHIN_EQUAL" cbs_flutter_qual_path_is_within /srv/cbs /srv/cbs
fq_expect_rc 1 "WITHIN_PREFIX_NAME" cbs_flutter_qual_path_is_within /srv/cbs /srv/cbs-other/a
fq_expect_rc 1 "WITHIN_REVERSED" cbs_flutter_qual_path_is_within /srv/cbs/a /srv/cbs
fq_expect_rc 1 "WITHIN_TRAVERSAL" cbs_flutter_qual_path_is_within /srv/cbs /srv/cbs/../etc
fq_expect_rc 1 "WITHIN_INVALID_ROOT" cbs_flutter_qual_path_is_within "/" /srv/cbs
fq_expect_rc 1 "WITHIN_INVALID_PATH" cbs_flutter_qual_path_is_within /srv/cbs "/srv/cbs/a b"

cbs_flutter_qual_paths_disjoint /srv/cbs/a /srv/cbs/b || fq_fail "DISJOINT_BASIC"
cbs_flutter_qual_paths_disjoint /srv/cbs/a /srv/cbs/a-b || fq_fail "DISJOINT_PREFIX_NAME"
fq_expect_rc 1 "DISJOINT_EQUAL" cbs_flutter_qual_paths_disjoint /srv/cbs/a /srv/cbs/a
fq_expect_rc 1 "DISJOINT_NESTED" cbs_flutter_qual_paths_disjoint /srv/cbs/a /srv/cbs/a/b
fq_expect_rc 1 "DISJOINT_NESTED_REVERSED" cbs_flutter_qual_paths_disjoint /srv/cbs/a/b /srv/cbs/a
fq_expect_rc 1 "DISJOINT_INVALID" cbs_flutter_qual_paths_disjoint /srv/cbs/a "relative"

# Symbolic links: a real filesystem, canonical form only.
if cbs_flutter_qual_path_valid "$FQ_TMP"; then
    mkdir -p "$FQ_TMP/fs/real/sub" "$FQ_TMP/fs/other"
    ln -s "$FQ_TMP/fs/real" "$FQ_TMP/fs/link"
    ln -s "$FQ_TMP/fs/other" "$FQ_TMP/fs/real/inner-link"
    ln -s "$FQ_TMP/fs/real/sub" "$FQ_TMP/fs/dir-link"
    ln -s "$FQ_TMP/fs/does-not-exist" "$FQ_TMP/fs/dangling"
    : > "$FQ_TMP/fs/file"

    cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/real" || fq_fail "CANONICAL_REAL"
    cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/real/sub" || fq_fail "CANONICAL_REAL_SUB"

    fq_expect_rc 1 "CANONICAL_LINK" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/link"
    fq_expect_rc 1 "CANONICAL_THROUGH_LINK" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/link/sub"
    fq_expect_rc 1 "CANONICAL_INNER_LINK" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/real/inner-link"
    fq_expect_rc 1 "CANONICAL_DIR_LINK" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/dir-link"
    fq_expect_rc 1 "CANONICAL_DANGLING" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/dangling"
    fq_expect_rc 1 "CANONICAL_MISSING" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/missing"
    fq_expect_rc 1 "CANONICAL_FILE" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/file"
    fq_expect_rc 1 "CANONICAL_DOTDOT" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/real/sub/.."
    fq_expect_rc 1 "CANONICAL_RELATIVE" cbs_flutter_qual_dir_is_canonical "fs/real"
    fq_expect_rc 1 "CANONICAL_EMPTY" cbs_flutter_qual_dir_is_canonical ""

    # An evidence root redirected onto the source repository is not canonical.
    mkdir -p "$FQ_TMP/fs/source-repo"
    ln -s "$FQ_TMP/fs/source-repo" "$FQ_TMP/fs/evidence-hijack"
    fq_expect_rc 1 "CANONICAL_HIJACKED_EVIDENCE" cbs_flutter_qual_dir_is_canonical "$FQ_TMP/fs/evidence-hijack"

    # A dangling or redirecting link is not followed and nothing is created.
    [[ ! -e "$FQ_TMP/fs/does-not-exist" ]] || fq_fail "CANONICAL_CREATED_TARGET"

    echo "${TEST_PREFIX}_SYMLINKS=PASS"
else
    echo "${TEST_PREFIX}_SYMLINKS=NOT_RUN"
fi

echo "${TEST_PREFIX}_PATHS=PASS"

# ---------------------------------------------------------------- 3. secrets: redaction

# redaction case: <label> <forbidden fragment> <input>
expect_redacted() {
    local label="$1"
    local forbidden="$2"
    local input="$3"
    local first
    local second

    first="$(cbs_flutter_qual_redact "$input")"

    if grep -Fq -e "$forbidden" <<<"$first"; then
        fq_fail "REDACT_LEAK_$label"
    fi

    grep -Fq "[REDACTED" <<<"$first" || fq_fail "REDACT_NO_MARKER_$label"

    # Idempotent.
    second="$(cbs_flutter_qual_redact "$first")"
    [[ "$first" == "$second" ]] || fq_fail "REDACT_NOT_IDEMPOTENT_$label"

    # The detector agrees with the redactor.
    cbs_flutter_qual_text_contains_secret "$input" || fq_fail "DETECT_MISS_$label"
    if cbs_flutter_qual_text_contains_secret "$first"; then
        fq_fail "DETECT_REDACTED_STILL_SECRET_$label"
    fi
}

expect_redacted TOKEN_EQ "abc123SECRET" "token=abc123SECRET"
expect_redacted TOKEN_UPPER "abc123SECRET" "TOKEN=abc123SECRET"
expect_redacted TOKEN_COLON "abc123SECRET" "Token: abc123SECRET"
expect_redacted TOKEN_PREFIXED "abc123SECRET" "GITLAB_ACCESS_TOKEN=abc123SECRET"
expect_redacted PASSWORD "hunter2" "password=hunter2"
expect_redacted PASSWD "hunter2" "PASSWD=hunter2"
expect_redacted DB_PASSWORD "hunter2" "db_password: hunter2"
expect_redacted PASSPHRASE "hunter2" "ssh.passphrase=hunter2"
expect_redacted SECRET "s3cr3t-v" "client_secret=s3cr3t-v"
expect_redacted AWS_SECRET "wJalrXUtnFEMI" "aws_secret_access_key=wJalrXUtnFEMI"
expect_redacted API_KEY "AIzaSyD-xyz" "api_key=AIzaSyD-xyz"
expect_redacted API_KEY_DASH "AIzaSyD-xyz" "API-KEY=AIzaSyD-xyz"
expect_redacted APIKEY "AIzaSyD-xyz" "apiKey=AIzaSyD-xyz"
expect_redacted PRIVATE_KEY_VAR "MIIEvQIBADAN" "private_key=MIIEvQIBADAN"
expect_redacted CREDENTIALS "user-cred-v" "credentials=user-cred-v"
expect_redacted AUTHORIZATION_BEARER "eyJhbGciOiJIUzI1NiJ9" "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9"
expect_redacted BEARER_LOWER "eyJhbGciOiJIUzI1NiJ9" "header bearer eyJhbGciOiJIUzI1NiJ9 end"
expect_redacted JSON_TOKEN "abc123json" '{"token": "abc123json"}'
expect_redacted JSON_NO_SPACE "abc123json" '{"password":"abc123json"}'
expect_redacted URL_CREDENTIALS "s3cr3t-token" "git clone https://user:s3cr3t-token@example.invalid/x.git"
expect_redacted URL_USER_ONLY "ghuser-only" "remote https://ghuser-only@example.invalid/x.git"
expect_redacted SSH_URL_USER "ssh-user-v" "ssh://ssh-user-v@example.invalid/x.git"
expect_redacted DART_DEFINE_EQ "sek-123" "flutter build ios --dart-define=API_URL=sek-123"
expect_redacted DART_DEFINE_SPACE "sek-123" "flutter build ios --dart-define PLAIN_NAME=sek-123"
expect_redacted DART_DEFINE_KEYED "sek-123" "--dart-define=MY_TOKEN=sek-123 --dart-define=OTHER=sek-123"
expect_redacted DART_DEFINE_URL "u:p@h" "--dart-define=BASE_URL=https://u:p@h/"
expect_redacted DART_DEFINE_FILE "secrets-file.json" "--dart-define-from-file=/home/u/secrets-file.json"
expect_redacted GITHUB_PAT "abcdefghijklmnopqrstuvwxyz0123456789" "using ghp_abcdefghijklmnopqrstuvwxyz0123456789 now"
expect_redacted AWS_ACCESS_KEY "AKIAIOSFODNN7EXAMPLE" "key AKIAIOSFODNN7EXAMPLE seen"
expect_redacted SLACK "xoxb-123456789012-abcdefghij" "hook xoxb-123456789012-abcdefghij"
expect_redacted GITLAB_PAT "glpat-abcdefghij1234567890" "pat glpat-abcdefghij1234567890"

PRIVATE_KEY_TEXT="before
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAbodyline1
bodyline2zzz
-----END RSA PRIVATE KEY-----
after"
REDACTED_KEY="$(cbs_flutter_qual_redact "$PRIVATE_KEY_TEXT")"
if grep -Fq -e "MIIEpAIBAAKCAQEAbodyline1" -e "bodyline2zzz" -e "BEGIN RSA" <<<"$REDACTED_KEY"; then
    fq_fail "REDACT_LEAK_PRIVATE_KEY_BLOCK"
fi
grep -Fxq "before" <<<"$REDACTED_KEY" || fq_fail "REDACT_PRIVATE_KEY_BEFORE_LOST"
grep -Fxq "after" <<<"$REDACTED_KEY" || fq_fail "REDACT_PRIVATE_KEY_AFTER_LOST"
cbs_flutter_qual_text_contains_secret "$PRIVATE_KEY_TEXT" || fq_fail "DETECT_PRIVATE_KEY_BLOCK"

# Several secrets on several lines: no line is skipped.
MULTI="line one token=aaa111zzz
line two password=bbb222zzz
line three https://u:ccc333zzz@h/x
line four --dart-define=K=ddd444zzz"
REDACTED_MULTI="$(cbs_flutter_qual_redact_stream <<<"$MULTI")"
if grep -Fq -e "aaa111zzz" -e "bbb222zzz" -e "ccc333zzz" -e "ddd444zzz" <<<"$REDACTED_MULTI"; then
    fq_fail "REDACT_LEAK_MULTILINE"
fi
[[ "$(grep -c . <<<"$REDACTED_MULTI")" -eq 4 ]] || fq_fail "REDACT_MULTILINE_LINE_COUNT"

# Ordinary build output is left alone.
for text in "Running flutter analyze in the isolated checkout" "No issues found!" "All tests passed!" \
    "Tests passed: 42" "Xcode 15.4 Build version 15F31d" "build/ios/iphonesimulator/Runner.app" \
    "test/token_test.dart" "git@example.invalid:org/app.git" "version: 3.19.0 channel stable" \
    "https://example.invalid/org/app.git" "commit 0123456789abcdef0123456789abcdef01234567" \
    "timeout_seconds=600" "Passed: 3, Failed: 0" ""; do
    [[ "$(cbs_flutter_qual_redact "$text")" == "$text" ]] || fq_fail "REDACT_ALTERED_BENIGN_$text"

    if cbs_flutter_qual_text_contains_secret "$text"; then
        fq_fail "DETECT_FALSE_POSITIVE_$text"
    fi
done

# Redaction produces no output on its own channel other than the text.
ERR="$(cbs_flutter_qual_redact "token=abc123SECRET" 2>&1 >/dev/null)"
[[ -z "$ERR" ]] || fq_fail "REDACT_STDERR"

echo "${TEST_PREFIX}_REDACTION=PASS"

# ---------------------------------------------------------------- 4. secrets: names and parameters

for key in api_token API_KEY apikey password passwd db_password client_secret secret_value \
    dart_define dart-define DART_DEFINE_X dart_define_from_file auth_header authorization \
    private_key privatekey passphrase credentials credential access_token refresh_token github_token; do
    cbs_flutter_qual_key_is_sensitive "$key" || fq_fail "SENSITIVE_MISSED_$key"
done

# No parameter of the contract is itself named like a secret.
for key in $ALL_KEYS; do
    if cbs_flutter_qual_key_is_sensitive "$key"; then
        fq_fail "ALLOWED_KEY_LOOKS_SENSITIVE_$key"
    fi

    cbs_flutter_qual_key_is_allowed "$key" || fq_fail "ALLOWED_KEY_MISSING_$key"
done

for key in "" "x" "timeout" "extra_args" "command" "flutter_args" "dart_defines_file_x"; do
    if [[ -n "$key" ]] && cbs_flutter_qual_key_is_allowed "$key"; then
        fq_fail "UNKNOWN_KEY_ALLOWED_$key"
    fi
done

# A sensitive parameter is refused as a secret (125), never silently ignored.
for key in api_token password client_secret dart_define dart_define_from_file auth_header \
    github_token passphrase private_key; do
    for value in "A=b" "hunter2" ""; do
        fq_request_reset
        set +e
        cbs_flutter_qual_validate_request "${FQ_REQUEST[@]}" "$key=$value" >/dev/null 2>&1
        FQ_RC=$?
        set -e
        [[ "$FQ_RC" -eq 125 ]] || fq_fail "SENSITIVE_PARAM_${key}_RC_$FQ_RC"
        fq_expect_reason "SECRET_REFUSED" "SENSITIVE_PARAM_$key"
    done
done

# A secret smuggled into an accepted parameter is refused, whichever it is.
for key in qualification_id isolation_id source_repository expected_origin commit isolation_root \
    evidence_root target actions timeout_seconds log_max_bytes evidence_retention cleanup_policy \
    test_scope test_targets simulator_udid simulator_policy; do
    for secret in "token=s3cr3tvalue" "password=s3cr3tvalue" "Bearer s3cr3tvalue" \
        "https://u:s3cr3tvalue@h/x" "--dart-define=A=s3cr3tvalue" "ghp_abcdefghijklmnopqrstuvwxyz0123456789"; do
        fq_request_reset
        fq_request_set "$key" "$secret"
        fq_validate_request
        [[ "$FQ_RC" -eq 125 ]] || fq_fail "SECRET_IN_${key}_RC_$FQ_RC"
        fq_expect_reason "SECRET_REFUSED" "SECRET_IN_$key"
    done
done

echo "${TEST_PREFIX}_SECRET_PARAMETERS=PASS"

# ---------------------------------------------------------------- 5. a refused value is never echoed or kept

SECRET_MARK="s3cr3tvalue-do-not-leak"

leak_probe() {
    # leak_probe <label> <command...> : output of the command, and the recorded
    # validation state, must not contain the secret.
    local label="$1"
    local out

    shift
    set +e
    out="$("$@" 2>&1)"
    set -e

    if grep -Fq "$SECRET_MARK" <<<"$out"; then
        fq_fail "ECHOED_$label"
    fi

    set +e
    "$@" >/dev/null 2>&1
    set -e

    case "$CBS_FLUTTER_QUAL_VALIDATION_REASON$CBS_FLUTTER_QUAL_VALIDATION_KEY" in
        *"$SECRET_MARK"*) fq_fail "STATE_KEEPS_SECRET_$label" ;;
    esac
}

leak_probe ORIGIN_CREDENTIALS cbs_flutter_qual_validate_param expected_origin "https://u:$SECRET_MARK@h/x.git"
leak_probe TOKEN_IN_ID cbs_flutter_qual_validate_param qualification_id "token=$SECRET_MARK"
leak_probe SENSITIVE_KEY cbs_flutter_qual_validate_param "api_token" "$SECRET_MARK"
leak_probe SENSITIVE_KEY_VALUE_BAD_FORM cbs_flutter_qual_validate_param "--dart-define=A" "$SECRET_MARK"
leak_probe REQUEST_ENTRY cbs_flutter_qual_validate_request "dart_define=K=$SECRET_MARK"
leak_probe REQUEST_ARG cbs_flutter_qual_validate_request "--dart-define=K=$SECRET_MARK"
leak_probe REQUEST_BAD_KEY cbs_flutter_qual_validate_request "Token_$SECRET_MARK=x"
leak_probe REQUEST_KEY_AS_SECRET cbs_flutter_qual_validate_request "$SECRET_MARK"
leak_probe ACTION_CALL cbs_flutter_qual_validate_action_call analyze "$SECRET_MARK"
leak_probe ACTION cbs_flutter_qual_validate_action "$SECRET_MARK"
leak_probe ACTIONS cbs_flutter_qual_validate_actions "preflight,$SECRET_MARK"
leak_probe TEST_TARGETS cbs_flutter_qual_validate_test_targets "test/$SECRET_MARK"
leak_probe EMIT_OPERATION cbs_flutter_qual_emit_operation ANALYZE FAIL COMMAND_FAILED "$SECRET_MARK"
leak_probe EMIT_RESULT cbs_flutter_qual_emit_result BLOCKED "$SECRET_MARK"
leak_probe EMIT_OPERATION_NAME cbs_flutter_qual_emit_operation "$SECRET_MARK" PASS
leak_probe DETECT cbs_flutter_qual_text_contains_secret "token=$SECRET_MARK"

# Every refused request records only a closed reason and a well-formed key.
fq_request_reset
set +e
cbs_flutter_qual_validate_request "${FQ_REQUEST[@]}" "Token_$SECRET_MARK=x" >/dev/null 2>&1
set -e
[[ -z "$CBS_FLUTTER_QUAL_VALIDATION_KEY" ]] || fq_fail "MALFORMED_KEY_RECORDED"
cbs_flutter_qual_reason_is_valid "$CBS_FLUTTER_QUAL_VALIDATION_REASON" || fq_fail "REASON_NOT_CLOSED_SET"

echo "${TEST_PREFIX}_NO_ECHO=PASS"

# ---------------------------------------------------------------- 6. nothing executed, nothing written

fq_shims_assert_unused "SECURITY"

# The working directory is untouched (apart from the files created above).
LEFT_COUNT="$(ls -A "$WORK" | wc -l)"
[[ "$LEFT_COUNT" -eq 3 ]] || fq_fail "WORKDIR_CHANGED_$LEFT_COUNT"

# No file was written next to the contract by the validators (the working
# directory was checked above; the scope is limited to cbs/ so that editing a
# test while the suite runs is not mistaken for a write by the contract).
CHANGED="$(find "$ROOT/cbs" -type f -newer "$FQ_TMP/marker" -print)"
[[ -z "$CHANGED" ]] || fq_fail "REPOSITORY_WRITTEN_$(printf '%s' "$CHANGED" | head -n 1)"

echo "${TEST_PREFIX}_NO_EXECUTION_NO_WRITE=PASS"

# ---------------------------------------------------------------- 7. static scan of the contract

[[ -f "$CONTRACT" ]] || fq_fail "STATIC_CONTRACT_MISSING"

# No eval, and a single sourced file: the isolation contract, at a path derived
# from the contract's own location (never from an input).
if fq_code_matches "$CONTRACT" '(^|[;&|({[:space:]])eval([[:space:]]|$)'; then
    fq_fail "STATIC_EVAL"
fi

SOURCED="$(grep -En '^[[:space:]]*(source|\.)[[:space:]]' "$CONTRACT" |
    grep -Ev '^[0-9]+:[[:space:]]*#' | sed -e 's/^[0-9]*://' -e 's/^[[:space:]]*//')"
[[ "$SOURCED" == 'source "$_cbs_flutter_qual_isolation_contract"' ]] || fq_fail "STATIC_SOURCED_FILES"

if fq_code_matches "$CONTRACT" '(^|[;&|({[:space:]])(exec|trap|set[[:space:]]+[-+][a-zA-Z]|shopt|unset[[:space:]]+-[fv]|export|alias|enable|builtin|command[[:space:]]+-)([[:space:]]|$)'; then
    fq_fail "STATIC_SHELL_STATE_OR_EXEC"
fi

# No external tool that executes, writes, removes, fetches or connects.
# (tr, sed, printf, dirname, cd, pwd are the only commands the contract runs.)
if fq_code_matches "$CONTRACT" '(^|[;&|({]|\$\()[[:space:]]*(flutter|dart|pub|xcrun|xcodebuild|simctl|git|ssh|scp|sftp|rsync|curl|wget|nc|open|rm|rmdir|mv|cp|mkdir|touch|chmod|chown|ln|tee|dd|install|kill|pkill|sudo|nohup|timeout|gtimeout|flock|mktemp|sleep|find|xargs|env|bash|sh|zsh|python|python3|perl|ruby|node)[[:space:]]'; then
    fq_fail "STATIC_EXTERNAL_TOOL"
fi

# No flutter/xcode/git word used as a command argument either.
if grep -En 'flutter (analyze|test|build|pub|doctor|run|clean)|xcodebuild|xcrun|simctl|git (clone|fetch|pull|push|checkout|reset|clean|worktree|add|commit)' "$CONTRACT" |
    grep -Ev '^[0-9]+:[[:space:]]*#' | grep -Eq .; then
    fq_fail "STATIC_TOOL_INVOCATION"
fi

# Only the null device and stderr are redirection targets: no file is written.
STRIPPED="$(grep -Ev '^[[:space:]]*#' "$CONTRACT" | sed -e 's#2>/dev/null##g' -e 's#>/dev/null##g' -e 's#>&2##g' -e 's#<<<##g')"
if grep -Fq '>' <<<"$STRIPPED"; then
    fq_fail "STATIC_FILE_REDIRECTION"
fi

if fq_code_matches "$CONTRACT" '(^|[^A-Za-z_])rm[[:space:]]|[[:space:]]-delete|git[[:space:]]+(reset|clean)'; then
    fq_fail "STATIC_DESTRUCTIVE"
fi

# No backtick command substitution: the only substitutions are $( ).
if fq_code_matches "$CONTRACT" '`'; then
    fq_fail "STATIC_BACKTICK"
fi

# No dependency on a business application, on the remote transport or on the
# worktree manager.
[[ -f "$ROOT/cbs/qualification/flutter/README.md" ]] || fq_fail "STATIC_README_MISSING"

APP_PATTERN="AMH""-USR"
# Application references in documentation are permitted as historical
# evidence or consumer examples. The executable contract remains generic.
if grep -Eiq -e "$APP_PATTERN" -e "amh[_-]usr" "$CONTRACT"; then
    fq_fail "STATIC_APPLICATION_DEPENDENCY"
fi

if fq_code_matches "$CONTRACT" 'remote_(runner|transport|checker|verifier|manifest)|worktree_manager|isolation_manager|stack_environment|bin/cbs'; then
    fq_fail "STATIC_COMPONENT_COUPLING"
fi

echo "${TEST_PREFIX}_STATIC_SCAN=PASS"

# Negative regression: the application-dependency rule must reject an
# application reference injected into an isolated copy of the contract.
NEGATIVE_CONTRACT="$FQ_TMP/negative-contract.sh"
cp "$CONTRACT" "$NEGATIVE_CONTRACT"
printf '\n# AMH-USR forbidden dependency fixture\n' >> "$NEGATIVE_CONTRACT"

if ! grep -Eiq -e "$APP_PATTERN" -e "amh[_-]usr" "$NEGATIVE_CONTRACT"; then
    fq_fail "STATIC_APPLICATION_DEPENDENCY_NEGATIVE"
fi

if grep -Eiq -e "$APP_PATTERN" -e "amh[_-]usr" "$CONTRACT"; then
    fq_fail "STATIC_APPLICATION_DEPENDENCY_SOURCE"
fi

echo "${TEST_PREFIX}_APPLICATION_DEPENDENCY_NEGATIVE=PASS"
echo "${TEST_PREFIX}_RESULT=PASS"
